---@mod gitlad.ui.views.status_navigation Status buffer navigation module
---@brief [[
--- Extracted navigation functionality for the status buffer.
--- Provides cursor movement, file visiting, and line jumping.
---@brief ]]

local M = {}

-- Import shared helper
local status_staging = require("gitlad.ui.views.status_staging")
local join_path = status_staging.join_path
local has_conflict_markers = status_staging._has_conflict_markers

-- Import diff cache key helper
local status_render = require("gitlad.ui.views.status_render")
local diff_cache_key = status_render.diff_cache_key

--- Open diffview for merge conflict resolution
---@param repo_root string Repository root path
---@param file_path? string Optional specific file to focus on
---@param repo_state? RepoState Repository state to refresh when diffview closes
local function open_diffview_merge(repo_root, file_path, repo_state)
  local ok, diffview = pcall(require, "diffview")
  if ok then
    -- Capture list of conflicted files before opening diffview
    local conflicted_files = {}
    if repo_state and repo_state.status and repo_state.status.conflicted then
      for _, entry in ipairs(repo_state.status.conflicted) do
        table.insert(conflicted_files, entry.path)
      end
    end

    -- Set up autocommand to check resolved files when diffview closes
    if repo_state then
      local group = vim.api.nvim_create_augroup("GitladDiffviewRefresh", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "DiffviewViewClosed",
        once = true,
        callback = function()
          vim.schedule(function()
            -- Check each previously conflicted file for resolution
            local resolved_files = {}
            for _, path in ipairs(conflicted_files) do
              local full_path = join_path(repo_root, path)
              if not has_conflict_markers(full_path) then
                table.insert(resolved_files, { path = path, section = "conflicted" })
              end
            end

            -- Auto-stage resolved files
            if #resolved_files > 0 then
              repo_state:stage_files(resolved_files, function(success)
                if success then
                  local msg = #resolved_files == 1
                      and string.format("Staged resolved file: %s", resolved_files[1].path)
                    or string.format("Staged %d resolved files", #resolved_files)
                  vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
                end
                -- Re-open status view (refresh happens via stage_files)
                local status_view = require("gitlad.ui.views.status")
                status_view.open()
              end)
            else
              -- No files resolved, just refresh and re-open
              repo_state:refresh_status(true)
              local status_view = require("gitlad.ui.views.status")
              status_view.open()
            end
          end)
        end,
      })
    end

    -- Open diffview which shows merge view when in merge state
    diffview.open({})
  else
    -- Fallback: just open the file with conflict markers
    if file_path then
      local full_path = join_path(repo_root, file_path)
      vim.cmd("edit " .. vim.fn.fnameescape(full_path))
      vim.notify(
        "[gitlad] diffview.nvim not installed. Opening file with conflict markers.",
        vim.log.levels.INFO
      )
    else
      vim.notify(
        "[gitlad] diffview.nvim not installed. Install with: { 'sindrets/diffview.nvim' }",
        vim.log.levels.WARN
      )
    end
  end
end

--- Navigate to next file entry
---@param self StatusBuffer
local function goto_next_file(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(self.bufnr)

  for line = current_line + 1, total_lines do
    if self.line_map[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous file entry
---@param self StatusBuffer
local function goto_prev_file(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    if self.line_map[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to next section header
---@param self StatusBuffer
local function goto_next_section(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(self.bufnr)

  for line = current_line + 1, total_lines do
    if self.section_lines[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous section header
---@param self StatusBuffer
local function goto_prev_section(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    if self.section_lines[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Calculate the target line number when on a diff line
--- Returns the line number in the file that corresponds to the current cursor position
---@param self StatusBuffer
---@param path string File path
---@param section string Section type
---@param hunk_index number Hunk index (1-based)
---@return number|nil target_line Line number to jump to, or nil if can't calculate
local function get_diff_line_target(self, path, section, hunk_index)
  local diff_data = self.diff_cache[diff_cache_key(path, section)]
  if not diff_data or not diff_data.hunks[hunk_index] then
    return nil
  end

  local hunk = diff_data.hunks[hunk_index]
  -- Parse the @@ header to get the new file starting line
  local _, _, new_start = hunk.header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  new_start = tonumber(new_start) or 1

  -- Find the current buffer line
  local cursor = vim.api.nvim_win_get_cursor(0)
  local buffer_line = cursor[1]

  -- Find where this file's diff starts in the buffer by scanning backward
  -- Stop when we hit the file entry line (hunk_index = nil) or a different file
  local diff_start_line = buffer_line
  for line = buffer_line, 1, -1 do
    local info = self.line_map[line]
    if not info or info.path ~= path or info.section ~= section or not info.hunk_index then
      diff_start_line = line + 1
      break
    end
    if line == 1 then
      diff_start_line = 1
    end
  end

  -- Calculate display_line index (0-based offset from diff start)
  local display_index = buffer_line - diff_start_line + 1

  -- Find where in display_lines this hunk starts
  local hunk_start_display = 0
  local current_hunk = 0
  for i, line in ipairs(diff_data.display_lines) do
    if line:match("^@@") then
      current_hunk = current_hunk + 1
      if current_hunk == hunk_index then
        hunk_start_display = i
        break
      end
    end
  end

  -- If we're on the @@ header line itself, jump to new_start
  if display_index == hunk_start_display then
    return new_start
  end

  -- Count lines from hunk start to current position
  -- Only count context lines and additions (+) since those exist in the new file
  local line_offset = 0
  for i = hunk_start_display + 1, display_index do
    local line = diff_data.display_lines[i]
    if line then
      local first_char = line:sub(1, 1)
      if first_char == " " or first_char == "+" then
        line_offset = line_offset + 1
      end
      -- Deletions (-) don't count towards new file line numbers
    end
  end

  return new_start + line_offset - 1 -- -1 because line_offset is 1-based count
end

--- Visit the file at cursor
---@param self StatusBuffer
local function visit_file(self)
  -- Check if on a submodule - open its directory
  local submodule = self:_get_current_submodule()
  if submodule then
    local submodule_path = join_path(self.repo_state.repo_root, submodule.path)
    -- Close status and open submodule directory
    self:close()
    vim.cmd("edit " .. vim.fn.fnameescape(submodule_path))
    return
  end

  local path, section, hunk_index = self:_get_current_file()
  if path then
    -- For conflicted files, open diffview merge tool instead of the raw file
    if section == "conflicted" then
      self:close()
      open_diffview_merge(self.repo_state.repo_root, path, self.repo_state)
      return
    end

    local full_path = join_path(self.repo_state.repo_root, path)
    local target_line = nil

    -- If on a diff line (inside expanded hunk), calculate target line
    if hunk_index then
      target_line = get_diff_line_target(self, path, section, hunk_index)
    end

    -- Close status and open file
    self:close()
    vim.cmd("edit " .. vim.fn.fnameescape(full_path))

    -- Jump to target line if we calculated one
    if target_line then
      vim.api.nvim_win_set_cursor(0, { target_line, 0 })
    end
    return
  end

  -- If not on a file, check if on a commit - show commit diff (shortcut for d d)
  local commit = self:_get_current_commit()
  if commit then
    local diff_popup = require("gitlad.popups.diff")
    diff_popup._diff_commit(self.repo_state, commit)
    return
  end

  -- If not on a commit, check if on a stash - show stash diff
  local stash = self:_get_current_stash()
  if stash then
    local diff_popup = require("gitlad.popups.diff")
    diff_popup._diff_stash(self.repo_state, stash)
    return
  end
end

--- Go to the first item in the buffer (for initial cursor positioning)
---@param self StatusBuffer
local function goto_first_item(self)
  -- Ensure we have a valid window for this buffer
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local total_lines = vim.api.nvim_buf_line_count(self.bufnr)

  for line = 1, total_lines do
    if self.line_map[line] then
      vim.api.nvim_win_set_cursor(self.winnr, { line, 0 })
      return
    end
  end

  -- No items found, stay at line 1
  vim.api.nvim_win_set_cursor(self.winnr, { 1, 0 })
end

--- Attach navigation methods to StatusBuffer class
---@param StatusBuffer table The StatusBuffer class
function M.setup(StatusBuffer)
  StatusBuffer._goto_next_file = goto_next_file
  StatusBuffer._goto_prev_file = goto_prev_file
  StatusBuffer._goto_next_section = goto_next_section
  StatusBuffer._goto_prev_section = goto_prev_section
  StatusBuffer._get_diff_line_target = get_diff_line_target
  StatusBuffer._visit_file = visit_file
  StatusBuffer._goto_first_item = goto_first_item
end

return M
