---@mod gitlad.ui.views.status_staging Status buffer staging module
---@brief [[
--- Extracted staging functionality for the status buffer.
--- Provides staging, unstaging, and discard operations.
---@brief ]]

local M = {}

local git = require("gitlad.git")

--- Join repository root path with a relative file path
--- Handles trailing slashes in repo_root to avoid double slashes
---@param repo_root string Repository root path (may have trailing slash)
---@param rel_path string Relative path within the repo
---@return string Full path
local function join_path(repo_root, rel_path)
  -- Remove trailing slash from repo_root if present
  local base = repo_root:gsub("/$", "")
  return base .. "/" .. rel_path
end

--- Get the cache key for a file's diff
---@param path string
---@param section string
---@return string
local function diff_cache_key(path, section)
  return section .. ":" .. path
end

--- Check if a file contains conflict markers
---@param file_path string Absolute path to the file
---@return boolean has_markers True if conflict markers found
local function has_conflict_markers(file_path)
  -- Use vim.fn.readfile which handles paths better than io.open
  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok or not lines then
    return false
  end

  for _, line in ipairs(lines) do
    -- Check for conflict marker start (7 '<' characters at line start)
    if line:match("^<<<<<<<") then
      return true
    end
  end

  return false
end

--- Get the visual selection line range (1-indexed)
---@return number start_line
---@return number end_line
local function get_visual_selection_range()
  -- Exit visual mode to update '< and '> marks
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  return start_line, end_line
end

--- Collect file entries from a line range for staging/unstaging
---@param line_map table<number, LineInfo|CommitLineInfo|StashLineInfo|SubmoduleLineInfo>
---@param start_line number
---@param end_line number
---@param allowed_sections table<string, boolean> Map of section names that are valid
---@return table[] files Array of {path, section} for file entries in range
---@return LineInfo|nil first_diff First diff line info if any diff lines selected
local function collect_files_in_range(line_map, start_line, end_line, allowed_sections)
  local files = {}
  local seen_paths = {}
  local first_diff = nil

  for buf_line = start_line, end_line do
    local info = line_map[buf_line]
    if info and info.path then
      if info.hunk_index then
        -- This is a diff line
        if not first_diff then
          first_diff = info
        end
      elseif allowed_sections[info.section] then
        -- This is a file entry line
        local key = info.section .. ":" .. info.path
        if not seen_paths[key] then
          seen_paths[key] = true
          table.insert(files, { path = info.path, section = info.section })
        end
      end
    end
  end

  return files, first_diff
end

--- Collect all files in a specific section from the status object
---@param status table The git status object
---@param section_type string The section type: "staged", "unstaged", "untracked"
---@return table[] files Array of {path, section} for all files in the section
local function collect_section_files(status, section_type)
  local files = {}

  if section_type == "untracked" and status.untracked then
    for _, entry in ipairs(status.untracked) do
      table.insert(files, { path = entry.path, section = "untracked" })
    end
  elseif section_type == "unstaged" and status.unstaged then
    for _, entry in ipairs(status.unstaged) do
      table.insert(files, { path = entry.path, section = "unstaged" })
    end
  elseif section_type == "staged" and status.staged then
    for _, entry in ipairs(status.staged) do
      table.insert(files, { path = entry.path, section = "staged" })
    end
  elseif section_type == "conflicted" and status.conflicted then
    for _, entry in ipairs(status.conflicted) do
      table.insert(files, { path = entry.path, section = "conflicted" })
    end
  end

  return files
end

--- Stage visual selection
---@param self StatusBuffer
local function stage_visual(self)
  local start_line, end_line = get_visual_selection_range()

  -- Collect all file entries and diff lines in the selection
  local allowed_sections = { unstaged = true, untracked = true, conflicted = true }
  local files, first_diff =
    collect_files_in_range(self.line_map, start_line, end_line, allowed_sections)

  -- If we have file entries selected, stage them all in a single git command
  if #files > 0 then
    self.repo_state:stage_files(files)
    return
  end

  -- No file entries - try partial hunk staging on diff lines
  if not first_diff then
    vim.notify("[gitlad] No stageable files or diff lines in selection", vim.log.levels.INFO)
    return
  end

  local path = first_diff.path
  local section = first_diff.section
  local hunk_index = first_diff.hunk_index

  if section ~= "unstaged" and section ~= "untracked" then
    vim.notify(
      "[gitlad] Partial hunk staging only works on unstaged or untracked files",
      vim.log.levels.INFO
    )
    return
  end

  local key = diff_cache_key(path, section)
  local diff_data = self.diff_cache[key]
  if not diff_data then
    return
  end

  -- Find which display_lines indices correspond to the buffer selection
  -- We need to map buffer lines back to display_lines indices
  local selected_display_indices = {}

  -- Find the file entry line for this path to calculate offset
  local file_entry_line = nil
  for line_num, line_info in pairs(self.line_map) do
    if line_info.path == path and line_info.section == section and not line_info.hunk_index then
      file_entry_line = line_num
      break
    end
  end

  if not file_entry_line then
    return
  end

  -- The diff lines start at file_entry_line + 1
  -- display_lines index = buffer_line - file_entry_line
  for buf_line = start_line, end_line do
    local line_info = self.line_map[buf_line]
    if line_info and line_info.hunk_index == hunk_index then
      local display_idx = buf_line - file_entry_line
      selected_display_indices[display_idx] = true
    end
  end

  local patch_lines =
    self:_build_partial_hunk_patch(diff_data, hunk_index, selected_display_indices, false)
  if not patch_lines then
    vim.notify("[gitlad] No changes selected", vim.log.levels.INFO)
    return
  end

  if section == "untracked" then
    -- For untracked files, we need to:
    -- 1. Run git add -N first to mark intent-to-add
    -- 2. Then apply the partial patch
    -- Note: The patch from --no-index (with "--- /dev/null") works fine after git add -N

    git.stage_intent(path, { cwd = self.repo_state.repo_root }, function(success, err)
      if not success then
        vim.notify("[gitlad] Intent-to-add error: " .. (err or "unknown"), vim.log.levels.ERROR)
        return
      end

      -- Now apply the partial patch
      git.apply_patch(
        patch_lines,
        false,
        { cwd = self.repo_state.repo_root },
        function(apply_success, apply_err)
          if not apply_success then
            vim.notify(
              "[gitlad] Stage selection error: " .. (apply_err or "unknown"),
              vim.log.levels.ERROR
            )
          else
            self.repo_state:refresh_status(true)
          end
        end
      )
    end)
  else
    -- Regular unstaged file - apply patch directly
    git.apply_patch(patch_lines, false, { cwd = self.repo_state.repo_root }, function(success, err)
      if not success then
        vim.notify("[gitlad] Stage selection error: " .. (err or "unknown"), vim.log.levels.ERROR)
      else
        self.repo_state:refresh_status(true)
      end
    end)
  end
end

--- Unstage visual selection
---@param self StatusBuffer
local function unstage_visual(self)
  local start_line, end_line = get_visual_selection_range()

  -- Collect all file entries and diff lines in the selection
  local allowed_sections = { staged = true }
  local files, first_diff =
    collect_files_in_range(self.line_map, start_line, end_line, allowed_sections)

  -- If we have file entries selected, unstage them all in a single git command
  if #files > 0 then
    local paths = {}
    for _, file in ipairs(files) do
      table.insert(paths, file.path)
    end
    self.repo_state:unstage_files(paths)
    return
  end

  -- No file entries - try partial hunk unstaging on diff lines
  if not first_diff then
    vim.notify("[gitlad] No unstageable files or diff lines in selection", vim.log.levels.INFO)
    return
  end

  local path = first_diff.path
  local section = first_diff.section
  local hunk_index = first_diff.hunk_index

  if section ~= "staged" then
    vim.notify("[gitlad] Partial hunk unstaging only works on staged changes", vim.log.levels.INFO)
    return
  end

  local key = diff_cache_key(path, section)
  local diff_data = self.diff_cache[key]
  if not diff_data then
    return
  end

  -- Find which display_lines indices correspond to the buffer selection
  local selected_display_indices = {}

  local file_entry_line = nil
  for line_num, line_info in pairs(self.line_map) do
    if line_info.path == path and line_info.section == section and not line_info.hunk_index then
      file_entry_line = line_num
      break
    end
  end

  if not file_entry_line then
    return
  end

  for buf_line = start_line, end_line do
    local line_info = self.line_map[buf_line]
    if line_info and line_info.hunk_index == hunk_index then
      local display_idx = buf_line - file_entry_line
      selected_display_indices[display_idx] = true
    end
  end

  local patch_lines =
    self:_build_partial_hunk_patch(diff_data, hunk_index, selected_display_indices, true)
  if not patch_lines then
    vim.notify("[gitlad] No changes selected", vim.log.levels.INFO)
    return
  end

  -- Reverse apply to unstage
  git.apply_patch(patch_lines, true, { cwd = self.repo_state.repo_root }, function(success, err)
    if not success then
      vim.notify("[gitlad] Unstage selection error: " .. (err or "unknown"), vim.log.levels.ERROR)
    else
      self.repo_state:refresh_status(true)
    end
  end)
end

--- Stage the file or hunk under cursor, or entire section if on section header
---@param self StatusBuffer
local function stage_current(self)
  -- First check if we're on a section header
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local section_info = self.section_lines[line]

  if section_info then
    -- We're on a section header - stage all files in this section
    local section_type = section_info.section
    if section_type == "unstaged" or section_type == "untracked" then
      local files = collect_section_files(self.repo_state.status, section_type)
      if #files > 0 then
        self.repo_state:stage_files(files)
      end
    elseif section_type == "conflicted" then
      -- Check for conflict markers in any conflicted file
      local files = collect_section_files(self.repo_state.status, section_type)
      if #files > 0 then
        local files_with_markers = {}
        for _, file in ipairs(files) do
          local full_path = join_path(self.repo_state.repo_root, file.path)
          if has_conflict_markers(full_path) then
            table.insert(files_with_markers, file.path)
          end
        end

        if #files_with_markers > 0 then
          local msg = string.format(
            "%d file(s) still contain conflict markers. Stage all anyway?",
            #files_with_markers
          )
          vim.ui.select({ "No", "Yes" }, {
            prompt = msg,
          }, function(choice)
            if choice == "Yes" then
              self.repo_state:stage_files(files)
            end
          end)
        else
          -- No conflict markers - safe to stage all
          self.repo_state:stage_files(files)
        end
      end
    end
    -- Do nothing if on staged section (already staged)
    return
  end

  -- Not on section header - check for file or hunk
  local path, section, hunk_index = self:_get_current_file()
  if not path then
    return
  end

  if section == "unstaged" then
    -- Check if we're on a hunk line
    if hunk_index then
      local key = diff_cache_key(path, section)
      local diff_data = self.diff_cache[key]
      if diff_data then
        local patch_lines = self:_build_hunk_patch(diff_data, hunk_index)
        if patch_lines then
          git.apply_patch(
            patch_lines,
            false,
            { cwd = self.repo_state.repo_root },
            function(success, err)
              if not success then
                vim.notify(
                  "[gitlad] Stage hunk error: " .. (err or "unknown"),
                  vim.log.levels.ERROR
                )
              else
                self.repo_state:refresh_status(true)
              end
            end
          )
          return
        end
      end
    end
    -- Stage the whole file
    self.repo_state:stage(path, section)
  elseif section == "untracked" then
    self.repo_state:stage(path, section)
  elseif section == "conflicted" then
    -- Check for conflict markers before staging
    local full_path = join_path(self.repo_state.repo_root, path)
    if has_conflict_markers(full_path) then
      -- Warn user and ask for confirmation
      vim.ui.select({ "No", "Yes" }, {
        prompt = "File still contains conflict markers. Stage anyway?",
      }, function(choice)
        if choice == "Yes" then
          self.repo_state:stage(path, section)
        end
      end)
    else
      -- No conflict markers - safe to stage
      self.repo_state:stage(path, section)
    end
  end
end

--- Stage the untracked file under cursor with intent-to-add (git add -N)
--- This allows subsequent partial staging of the file's content
---@param self StatusBuffer
local function stage_intent_current(self)
  local path, section = self:_get_current_file()
  if not path then
    return
  end

  if section ~= "untracked" then
    vim.notify("[gitlad] Intent-to-add (gs) only applies to untracked files", vim.log.levels.INFO)
    return
  end

  self.repo_state:stage_intent(path)
end

--- Unstage the file or hunk under cursor, or entire section if on section header
---@param self StatusBuffer
local function unstage_current(self)
  -- First check if we're on a section header
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local section_info = self.section_lines[line]

  if section_info then
    -- We're on a section header - unstage all files in this section
    local section_type = section_info.section
    if section_type == "staged" then
      local files = collect_section_files(self.repo_state.status, section_type)
      if #files > 0 then
        local paths = {}
        for _, file in ipairs(files) do
          table.insert(paths, file.path)
        end
        self.repo_state:unstage_files(paths)
      end
    end
    -- Do nothing if on unstaged/untracked section (can't unstage)
    return
  end

  -- Not on section header - check for file or hunk
  local path, section, hunk_index = self:_get_current_file()
  if not path then
    return
  end

  if section == "staged" then
    -- Find the next staged file to move cursor to after unstaging
    -- First try next file, then try previous file
    local _, next_path = self:_find_next_file_in_section(line, "staged", path)
    if not next_path then
      _, next_path = self:_find_prev_file_in_section(line, "staged", path)
    end

    -- Store the target for cursor positioning after render
    if next_path then
      self.pending_cursor_target = { path = next_path, section = "staged" }
    end

    -- Check if we're on a hunk line
    if hunk_index then
      local key = diff_cache_key(path, section)
      local diff_data = self.diff_cache[key]
      if diff_data then
        local patch_lines = self:_build_hunk_patch(diff_data, hunk_index)
        if patch_lines then
          -- Use reverse apply to unstage
          git.apply_patch(
            patch_lines,
            true,
            { cwd = self.repo_state.repo_root },
            function(success, err)
              if not success then
                vim.notify(
                  "[gitlad] Unstage hunk error: " .. (err or "unknown"),
                  vim.log.levels.ERROR
                )
              else
                self.repo_state:refresh_status(true)
              end
            end
          )
          return
        end
      end
    end
    -- Unstage the whole file
    self.repo_state:unstage(path)
  elseif section == "unstaged" then
    -- Check if this is an intent-to-add file (.A) - if so, allow undoing it
    local status = self.repo_state.status
    for _, entry in ipairs(status.unstaged) do
      if entry.path == path and entry.worktree_status == "A" and entry.index_status == "." then
        -- This is an intent-to-add file - undo it (move back to untracked)
        self.repo_state:unstage_intent(path)
        return
      end
    end
    -- Not an intent-to-add file - can't unstage from unstaged section
  end
end

--- Find the next file line in a section starting after a given line
---@param self StatusBuffer
---@param start_line number Line to start searching after
---@param section string Section to search within
---@param exclude_path? string Path to exclude from results
---@return number|nil line Line number of next file, or nil if not found
---@return string|nil path Path of next file, or nil if not found
local function find_next_file_in_section(self, start_line, section, exclude_path)
  local total_lines = vim.api.nvim_buf_line_count(self.bufnr)
  for line_num = start_line + 1, total_lines do
    local info = self.line_map[line_num]
    if info and info.section == section and info.type == "file" and not info.hunk_index then
      if not exclude_path or info.path ~= exclude_path then
        return line_num, info.path
      end
    end
  end
  return nil, nil
end

--- Find the previous file line in a section starting before a given line
---@param self StatusBuffer
---@param start_line number Line to start searching before
---@param section string Section to search within
---@param exclude_path? string Path to exclude from results
---@return number|nil line Line number of previous file, or nil if not found
---@return string|nil path Path of previous file, or nil if not found
local function find_prev_file_in_section(self, start_line, section, exclude_path)
  for line_num = start_line - 1, 1, -1 do
    local info = self.line_map[line_num]
    if info and info.section == section and info.type == "file" and not info.hunk_index then
      if not exclude_path or info.path ~= exclude_path then
        return line_num, info.path
      end
    end
  end
  return nil, nil
end

--- Stage all unstaged and untracked files
---@param self StatusBuffer
local function stage_all(self)
  self.repo_state:stage_all()
end

--- Unstage all staged files
---@param self StatusBuffer
local function unstage_all(self)
  self.repo_state:unstage_all()
end

--- Discard changes for file at cursor, or entire section if on section header
---@param self StatusBuffer
local function discard_current(self)
  -- First check if we're on a section header
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local section_info = self.section_lines[line]

  if section_info then
    -- We're on a section header - discard all files in this section
    local section_type = section_info.section
    if section_type == "staged" then
      vim.notify("[gitlad] Cannot discard staged changes. Unstage first.", vim.log.levels.WARN)
      return
    end

    local files = collect_section_files(self.repo_state.status, section_type)
    if #files == 0 then
      return
    end

    -- Build confirmation message
    local prompt
    if section_type == "untracked" then
      prompt = string.format("Delete all %d untracked file(s)?", #files)
    else
      prompt = string.format("Discard changes to all %d file(s)?", #files)
    end

    vim.ui.select({ "Yes", "No" }, {
      prompt = prompt,
    }, function(choice)
      if choice == "Yes" then
        self.repo_state:discard_files(files)
      end
    end)
    return
  end

  -- Not on section header - check for file or hunk
  local path, section, hunk_index = self:_get_current_file()
  if not path then
    return
  end

  if section == "staged" then
    vim.notify("[gitlad] Cannot discard staged changes. Unstage first.", vim.log.levels.WARN)
    return
  end

  -- Check if we're on a hunk line in unstaged section
  if section == "unstaged" and hunk_index then
    local key = diff_cache_key(path, section)
    local diff_data = self.diff_cache[key]
    if diff_data then
      local patch_lines = self:_build_hunk_patch(diff_data, hunk_index)
      if patch_lines then
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Discard this hunk?",
        }, function(choice)
          if choice == "Yes" then
            -- Apply reverse patch to worktree (cached=false)
            git.apply_patch(
              patch_lines,
              true,
              { cwd = self.repo_state.repo_root },
              function(success, err)
                if not success then
                  local msg = err or "unknown error"
                  if msg:find("patch does not apply") then
                    msg = "Diff may be stale. Try refreshing (gr) first."
                  end
                  vim.notify("[gitlad] Discard hunk error: " .. msg, vim.log.levels.ERROR)
                else
                  self.repo_state:refresh_status(true)
                end
              end,
              false
            )
          end
        end)
        return
      end
    end
  end

  if section == "untracked" then
    -- Confirm deletion of untracked file
    vim.ui.select({ "Yes", "No" }, {
      prompt = string.format("Delete untracked file '%s'?", path),
    }, function(choice)
      if choice == "Yes" then
        self.repo_state:discard(path, section)
      end
    end)
  else
    -- Confirm discard of changes
    vim.ui.select({ "Yes", "No" }, {
      prompt = string.format("Discard changes to '%s'?", path),
    }, function(choice)
      if choice == "Yes" then
        self.repo_state:discard(path, section)
      end
    end)
  end
end

--- Discard changes for visually selected files or diff lines
---@param self StatusBuffer
local function discard_visual(self)
  local start_line, end_line = get_visual_selection_range()

  -- Collect all file entries and diff lines in the selection
  local allowed_sections = { unstaged = true, untracked = true }
  local files, first_diff =
    collect_files_in_range(self.line_map, start_line, end_line, allowed_sections)

  -- If we have file entries selected, discard them all
  if #files > 0 then
    -- Build confirmation message
    local untracked_count = 0
    local unstaged_count = 0
    for _, file in ipairs(files) do
      if file.section == "untracked" then
        untracked_count = untracked_count + 1
      else
        unstaged_count = unstaged_count + 1
      end
    end

    local prompt_parts = {}
    if unstaged_count > 0 then
      table.insert(prompt_parts, string.format("discard changes to %d file(s)", unstaged_count))
    end
    if untracked_count > 0 then
      table.insert(prompt_parts, string.format("delete %d untracked file(s)", untracked_count))
    end
    local prompt = table.concat(prompt_parts, " and ") .. "?"

    vim.ui.select({ "Yes", "No" }, {
      prompt = string.format("Really %s", prompt),
    }, function(choice)
      if choice == "Yes" then
        self.repo_state:discard_files(files)
      end
    end)
    return
  end

  -- No file entries - try partial hunk discard on diff lines
  if not first_diff then
    vim.notify("[gitlad] No discardable files or diff lines in selection", vim.log.levels.INFO)
    return
  end

  local path = first_diff.path
  local section = first_diff.section
  local hunk_index = first_diff.hunk_index

  if section ~= "unstaged" then
    vim.notify("[gitlad] Partial hunk discard only works on unstaged changes", vim.log.levels.INFO)
    return
  end

  local key = diff_cache_key(path, section)
  local diff_data = self.diff_cache[key]
  if not diff_data then
    return
  end

  -- Find which display_lines indices correspond to the buffer selection
  local selected_display_indices = {}

  local file_entry_line = nil
  for line_num, line_info in pairs(self.line_map) do
    if line_info.path == path and line_info.section == section and not line_info.hunk_index then
      file_entry_line = line_num
      break
    end
  end

  if not file_entry_line then
    return
  end

  for buf_line = start_line, end_line do
    local line_info = self.line_map[buf_line]
    if line_info and line_info.hunk_index == hunk_index then
      local display_idx = buf_line - file_entry_line
      selected_display_indices[display_idx] = true
    end
  end

  -- Use reverse=true so unselected + lines become context (they're in the working tree)
  local patch_lines =
    self:_build_partial_hunk_patch(diff_data, hunk_index, selected_display_indices, true)
  if not patch_lines then
    vim.notify("[gitlad] No changes selected", vim.log.levels.INFO)
    return
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = "Discard selected changes?",
  }, function(choice)
    if choice == "Yes" then
      -- Reverse apply to worktree (cached=false)
      git.apply_patch(patch_lines, true, { cwd = self.repo_state.repo_root }, function(success, err)
        if not success then
          local msg = err or "unknown error"
          if msg:find("patch does not apply") then
            msg = "Diff may be stale. Try refreshing (gr) first."
          end
          vim.notify("[gitlad] Discard selection error: " .. msg, vim.log.levels.ERROR)
        else
          self.repo_state:refresh_status(true)
        end
      end, false)
    end
  end)
end

--- Pop stash at point (apply and remove)
---@param self StatusBuffer
---@param stash StashEntry
local function stash_pop(self, stash)
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Pop %s?", stash.ref),
  }, function(choice)
    if choice == "Yes" then
      vim.notify("[gitlad] Popping stash...", vim.log.levels.INFO)
      git.stash_pop(stash.ref, { cwd = self.repo_state.repo_root }, function(success, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Popped " .. stash.ref, vim.log.levels.INFO)
            self.repo_state:refresh_status(true)
          else
            vim.notify("[gitlad] Pop failed: " .. (err or "unknown"), vim.log.levels.ERROR)
          end
        end)
      end)
    end
  end)
end

--- Apply stash at point (without removing it)
---@param self StatusBuffer
---@param stash StashEntry
local function stash_apply(self, stash)
  vim.notify("[gitlad] Applying stash...", vim.log.levels.INFO)
  git.stash_apply(stash.ref, { cwd = self.repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Applied " .. stash.ref, vim.log.levels.INFO)
        self.repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Apply failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Drop stash at point (remove without applying)
---@param self StatusBuffer
---@param stash StashEntry
local function stash_drop(self, stash)
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Drop %s? This cannot be undone.", stash.ref),
  }, function(choice)
    if choice == "Yes" then
      vim.notify("[gitlad] Dropping stash...", vim.log.levels.INFO)
      git.stash_drop(stash.ref, { cwd = self.repo_state.repo_root }, function(success, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Dropped " .. stash.ref, vim.log.levels.INFO)
            self.repo_state:refresh_status(true)
          else
            vim.notify("[gitlad] Drop failed: " .. (err or "unknown"), vim.log.levels.ERROR)
          end
        end)
      end)
    end
  end)
end

--- Attach staging methods to StatusBuffer class
---@param StatusBuffer table The StatusBuffer class
function M.setup(StatusBuffer)
  StatusBuffer._stage_visual = stage_visual
  StatusBuffer._unstage_visual = unstage_visual
  StatusBuffer._stage_current = stage_current
  StatusBuffer._stage_intent_current = stage_intent_current
  StatusBuffer._unstage_current = unstage_current
  StatusBuffer._find_next_file_in_section = find_next_file_in_section
  StatusBuffer._find_prev_file_in_section = find_prev_file_in_section
  StatusBuffer._stage_all = stage_all
  StatusBuffer._unstage_all = unstage_all
  StatusBuffer._discard_current = discard_current
  StatusBuffer._discard_visual = discard_visual
  StatusBuffer._stash_pop = stash_pop
  StatusBuffer._stash_apply = stash_apply
  StatusBuffer._stash_drop = stash_drop
end

-- Export helper function for use by other modules (e.g., diffview integration)
M._has_conflict_markers = has_conflict_markers
M.join_path = join_path

return M
