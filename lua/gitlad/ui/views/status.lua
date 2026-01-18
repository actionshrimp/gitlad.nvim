---@mod gitlad.ui.views.status Status buffer view
---@brief [[
--- Main status buffer showing staged, unstaged, and untracked files.
---@brief ]]

local M = {}

local state = require("gitlad.state")
local config = require("gitlad.config")
local history_view = require("gitlad.ui.views.history")
local git = require("gitlad.git")
local keymap = require("gitlad.utils.keymap")
local hl = require("gitlad.ui.hl")
local log_list = require("gitlad.ui.components.log_list")

-- Namespace for sign column indicators
local ns_signs = vim.api.nvim_create_namespace("gitlad_signs")

---@class LineInfo
---@field path string File path
---@field section "staged"|"unstaged"|"untracked"|"conflicted" Section type
---@field hunk_index number|nil Index of hunk if this is a diff line

---@class DiffHunk
---@field header string The @@ header line
---@field lines string[] The hunk content lines

---@class DiffData
---@field header string[] The diff header lines (diff --git, index, ---, +++)
---@field hunks DiffHunk[] Array of parsed hunks
---@field display_lines string[] Flattened lines for display (without diff header)

---@class SectionInfo
---@field name string Section name
---@field section "staged"|"unstaged"|"untracked"|"conflicted" Section type

---@class SignInfo
---@field expanded boolean Whether the item is expanded

---@class StatusBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field line_map table<number, LineInfo|CommitLineInfo> Map of line numbers to file or commit info
---@field section_lines table<number, SectionInfo> Map of line numbers to section headers
---@field expanded_files table<string, boolean> Map of "section:path" to expanded state
---@field expanded_commits table<string, boolean> Map of commit hash to expanded state
---@field diff_cache table<string, DiffData> Map of "section:path" to parsed diff data
---@field sign_lines table<number, SignInfo> Map of line numbers to sign info
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

-- Active status buffers by repo root
local status_buffers = {}

--- Create or get a status buffer for a repository
---@param repo_state RepoState
---@return StatusBuffer
local function get_or_create_buffer(repo_state)
  local key = repo_state.repo_root

  if status_buffers[key] and vim.api.nvim_buf_is_valid(status_buffers[key].bufnr) then
    return status_buffers[key]
  end

  local self = setmetatable({}, StatusBuffer)
  self.repo_state = repo_state
  self.line_map = {} -- Maps line numbers to file info or commit info
  self.section_lines = {} -- Maps line numbers to section headers
  self.expanded_files = {} -- Tracks which files have diffs expanded
  self.expanded_commits = {} -- Tracks which commits have details expanded
  self.collapsed_sections = {} -- Tracks which commit sections are collapsed
  self.diff_cache = {} -- Caches fetched diff lines

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://status")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Listen for status updates
  repo_state:on("status", function()
    vim.schedule(function()
      -- Clear diff/expansion data when status changes to avoid stale data
      self.expanded_files = {}
      self.expanded_commits = {}
      self.diff_cache = {}
      self:render()
    end)
  end)

  status_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function StatusBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Staging single file/hunk
  keymap.set(bufnr, "n", "s", function()
    self:_stage_current()
  end, "Stage file/hunk")
  keymap.set(bufnr, "n", "u", function()
    self:_unstage_current()
  end, "Unstage file/hunk")

  -- Visual mode staging (for partial hunk staging)
  keymap.set(bufnr, "v", "s", function()
    self:_stage_visual()
  end, "Stage selection")
  keymap.set(bufnr, "v", "u", function()
    self:_unstage_visual()
  end, "Unstage selection")

  -- Staging all
  keymap.set(bufnr, "n", "S", function()
    self:_stage_all()
  end, "Stage all")
  keymap.set(bufnr, "n", "U", function()
    self:_unstage_all()
  end, "Unstage all")

  -- Discard
  keymap.set(bufnr, "n", "x", function()
    self:_discard_current()
  end, "Discard changes")
  keymap.set(bufnr, "v", "x", function()
    self:_discard_visual()
  end, "Discard selection")

  -- Refresh (gr to free up g prefix for vim motions like gg)
  keymap.set(bufnr, "n", "gr", function()
    self.repo_state:refresh_status(true)
  end, "Refresh status")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close status")

  -- Navigation (evil-collection-magit style: gj/gk for items, j/k for normal line movement)
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_file()
  end, "Next file/commit")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_file()
  end, "Previous file/commit")
  keymap.set(bufnr, "n", "<M-n>", function()
    self:_goto_next_section()
  end, "Next section")
  keymap.set(bufnr, "n", "<M-p>", function()
    self:_goto_prev_section()
  end, "Previous section")

  -- Visit file
  keymap.set(bufnr, "n", "<CR>", function()
    self:_visit_file()
  end, "Visit file")

  -- Diff toggle
  keymap.set(bufnr, "n", "<Tab>", function()
    self:_toggle_diff()
  end, "Toggle diff")

  -- Git command history
  keymap.set(bufnr, "n", "$", function()
    history_view.open()
  end, "Show git command history")

  -- Help
  keymap.set(bufnr, "n", "?", function()
    local help_popup = require("gitlad.popups.help")
    help_popup.open(self)
  end, "Show help")

  -- Commit popup
  keymap.set(bufnr, "n", "c", function()
    local commit_popup = require("gitlad.popups.commit")
    commit_popup.open(self.repo_state)
  end, "Commit popup")

  -- Push popup (evil-collection-magit style: p instead of P)
  keymap.set(bufnr, "n", "p", function()
    local push_popup = require("gitlad.popups.push")
    push_popup.open(self.repo_state)
  end, "Push popup")

  -- Fetch popup
  keymap.set(bufnr, "n", "f", function()
    local fetch_popup = require("gitlad.popups.fetch")
    fetch_popup.open(self.repo_state)
  end, "Fetch popup")

  -- Pull popup
  keymap.set(bufnr, "n", "F", function()
    local pull_popup = require("gitlad.popups.pull")
    pull_popup.open(self.repo_state)
  end, "Pull popup")

  -- Branch popup
  keymap.set(bufnr, "n", "b", function()
    local branch_popup = require("gitlad.popups.branch")
    branch_popup.open(self.repo_state)
  end, "Branch popup")

  -- Log popup
  keymap.set(bufnr, "n", "l", function()
    local log_popup = require("gitlad.popups.log")
    log_popup.open(self.repo_state)
  end, "Log popup")

  -- Diff popup
  keymap.set(bufnr, "n", "d", function()
    local diff_popup = require("gitlad.popups.diff")
    local context = self:_get_diff_context()
    diff_popup.open(self.repo_state, context)
  end, "Diff popup")
  keymap.set(bufnr, "n", "y", function()
    self:_yank_commit_hash()
  end, "Yank commit hash")

  -- Stash popup
  keymap.set(bufnr, "n", "z", function()
    local stash_popup = require("gitlad.popups.stash")
    stash_popup.open(self.repo_state)
  end, "Stash popup")
end

--- Get the file path at the current cursor position
---@return string|nil path
---@return string|nil section "staged"|"unstaged"|"untracked"|"conflicted"
---@return number|nil hunk_index Index of hunk if on a diff line
function StatusBuffer:_get_current_file()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.path then
    return info.path, info.section, info.hunk_index
  end

  return nil, nil, nil
end

--- Get the commit at the current cursor position
---@return GitCommitInfo|nil commit
---@return string|nil section The commit section type
function StatusBuffer:_get_current_commit()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.type == "commit" then
    return info.commit, info.section
  end

  return nil, nil
end

--- Get selected commits (normal mode: single, visual mode: range)
---@return GitCommitInfo[] Selected commits
function StatusBuffer:_get_selected_commits()
  local mode = vim.fn.mode()
  if mode:match("[vV]") then
    -- Visual mode: get range
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "nx", false)
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    return log_list.get_commits_in_range(self.line_map, start_line, end_line)
  else
    -- Normal mode: single commit
    local commit = self:_get_current_commit()
    if commit then
      return { commit }
    end
  end
  return {}
end

--- Get diff context for current cursor position
---@return DiffContext
function StatusBuffer:_get_diff_context()
  local file_path, section = self:_get_current_file()
  local commit = self:_get_current_commit()
  return { file_path = file_path, section = section, commit = commit }
end

--- Yank commit hash to clipboard
function StatusBuffer:_yank_commit_hash()
  local commit = self:_get_current_commit()
  if not commit then
    return
  end

  vim.fn.setreg("+", commit.hash)
  vim.fn.setreg('"', commit.hash)
  vim.notify("[gitlad] Yanked: " .. commit.hash, vim.log.levels.INFO)
end

--- Get the cache key for a file's diff
---@param path string
---@param section string
---@return string
local function diff_cache_key(path, section)
  return section .. ":" .. path
end

--- Build a patch for a single hunk
---@param diff_data DiffData
---@param hunk_index number
---@return string[]|nil patch_lines
function StatusBuffer:_build_hunk_patch(diff_data, hunk_index)
  if not diff_data.hunks[hunk_index] then
    return nil
  end

  local patch_lines = {}

  -- Add the diff header
  for _, line in ipairs(diff_data.header) do
    table.insert(patch_lines, line)
  end

  -- Add the single hunk
  local hunk = diff_data.hunks[hunk_index]
  table.insert(patch_lines, hunk.header)
  for _, line in ipairs(hunk.lines) do
    table.insert(patch_lines, line)
  end

  return patch_lines
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

--- Build a partial patch from selected lines within a hunk
--- For staging (reverse=false): selected +/- lines are kept, unselected + omitted, unselected - become context
--- For unstaging (reverse=true): selected +/- lines are kept, unselected + become context, unselected - omitted
---@param diff_data DiffData
---@param hunk_index number
---@param selected_display_indices table<number, boolean> Map of display line indices (1-based within display_lines) that are selected
---@param reverse boolean Whether this patch will be applied with --reverse (for unstaging)
---@return string[]|nil patch_lines
function StatusBuffer:_build_partial_hunk_patch(
  diff_data,
  hunk_index,
  selected_display_indices,
  reverse
)
  if not diff_data.hunks[hunk_index] then
    return nil
  end

  local hunk = diff_data.hunks[hunk_index]

  -- Parse the original @@ header to get starting line numbers
  local old_start, old_count, new_start, new_count =
    hunk.header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  old_start = tonumber(old_start) or 1
  old_count = tonumber(old_count) or 1
  new_start = tonumber(new_start) or 1
  new_count = tonumber(new_count) or 1

  -- Build the new hunk lines based on selection
  local new_hunk_lines = {}
  local new_old_count = 0
  local new_new_count = 0

  -- Calculate the display line index for this hunk's header
  local hunk_header_display_idx = 0
  local current_hunk = 0
  for i, line in ipairs(diff_data.display_lines) do
    if line:match("^@@") then
      current_hunk = current_hunk + 1
      if current_hunk == hunk_index then
        hunk_header_display_idx = i
        break
      end
    end
  end

  for i, line in ipairs(hunk.lines) do
    local display_idx = hunk_header_display_idx + i
    local is_selected = selected_display_indices[display_idx]
    local first_char = line:sub(1, 1)

    if first_char == "+" then
      if is_selected then
        -- Keep as addition
        table.insert(new_hunk_lines, line)
        new_new_count = new_new_count + 1
      elseif reverse then
        -- Unstaging: unselected + becomes context (stays in index)
        table.insert(new_hunk_lines, " " .. line:sub(2))
        new_old_count = new_old_count + 1
        new_new_count = new_new_count + 1
      end
      -- Staging: unselected + is omitted (stays only in working tree)
    elseif first_char == "-" then
      if is_selected then
        -- Keep as deletion
        table.insert(new_hunk_lines, line)
        new_old_count = new_old_count + 1
      elseif not reverse then
        -- Staging: unselected - becomes context (stays in index)
        table.insert(new_hunk_lines, " " .. line:sub(2))
        new_old_count = new_old_count + 1
        new_new_count = new_new_count + 1
      end
      -- Unstaging: unselected - is omitted (stays removed from index)
    else
      -- Context line - always keep
      table.insert(new_hunk_lines, line)
      new_old_count = new_old_count + 1
      new_new_count = new_new_count + 1
    end
  end

  -- If no actual changes remain, don't create a patch
  local has_changes = false
  for _, line in ipairs(new_hunk_lines) do
    local fc = line:sub(1, 1)
    if fc == "+" or fc == "-" then
      has_changes = true
      break
    end
  end
  if not has_changes then
    return nil
  end

  -- Build the new @@ header
  local new_header =
    string.format("@@ -%d,%d +%d,%d @@", old_start, new_old_count, new_start, new_new_count)

  -- Assemble the patch
  local patch_lines = {}
  for _, line in ipairs(diff_data.header) do
    table.insert(patch_lines, line)
  end
  table.insert(patch_lines, new_header)
  for _, line in ipairs(new_hunk_lines) do
    table.insert(patch_lines, line)
  end

  return patch_lines
end

--- Collect file entries from a line range for staging/unstaging
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
  end

  return files
end

--- Stage visual selection
function StatusBuffer:_stage_visual()
  local start_line, end_line = get_visual_selection_range()

  -- Collect all file entries and diff lines in the selection
  local allowed_sections = { unstaged = true, untracked = true }
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

  if section ~= "unstaged" then
    vim.notify("[gitlad] Partial hunk staging only works on unstaged changes", vim.log.levels.INFO)
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

  git.apply_patch(patch_lines, false, { cwd = self.repo_state.repo_root }, function(success, err)
    if not success then
      vim.notify("[gitlad] Stage selection error: " .. (err or "unknown"), vim.log.levels.ERROR)
    else
      self.repo_state:refresh_status(true)
    end
  end)
end

--- Unstage visual selection
function StatusBuffer:_unstage_visual()
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
function StatusBuffer:_stage_current()
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
  end
end

--- Unstage the file or hunk under cursor, or entire section if on section header
function StatusBuffer:_unstage_current()
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
  end
end

--- Parse a git diff into structured data with header and hunks
---@param lines string[]
---@return DiffData
local function parse_diff(lines)
  local data = {
    header = {},
    hunks = {},
    display_lines = {},
  }

  local current_hunk = nil

  for _, line in ipairs(lines) do
    if line:match("^@@") then
      -- Start a new hunk
      if current_hunk then
        table.insert(data.hunks, current_hunk)
      end
      current_hunk = {
        header = line,
        lines = {},
      }
      -- Keep the @@ header line to show line ranges
      table.insert(data.display_lines, line)
    elseif current_hunk then
      -- Add line to current hunk
      table.insert(current_hunk.lines, line)
      table.insert(data.display_lines, line)
    else
      -- This is part of the diff header (before first @@)
      table.insert(data.header, line)
    end
  end

  -- Don't forget the last hunk
  if current_hunk then
    table.insert(data.hunks, current_hunk)
  end

  return data
end

--- Toggle diff view for current file or collapse section
function StatusBuffer:_toggle_diff()
  -- First check if we're on a section header (for commit sections)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local section_info = self.section_lines[line]

  if section_info then
    -- Check if this is a collapsible commit section
    local collapsible_sections = {
      unpulled_upstream = true,
      unpushed_upstream = true,
      unpulled_push = true,
      unpushed_push = true,
      recent = true,
    }
    if collapsible_sections[section_info.section] then
      -- Toggle the section collapsed state
      local section_key = section_info.section
      self.collapsed_sections[section_key] = not self.collapsed_sections[section_key]
      self:render()
      return
    end
  end

  local path, section = self:_get_current_file()
  if not path then
    return
  end

  local key = diff_cache_key(path, section)

  -- Toggle expanded state - if expanded, collapse
  if self.expanded_files[key] then
    self.expanded_files[key] = false
    self.diff_cache[key] = nil
    self:render()
    return
  end

  -- Expand - always fetch fresh diff
  -- Use appropriate diff function based on section
  local function on_diff_result(diff_lines, err)
    if err then
      vim.notify("[gitlad] Diff error: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      self.diff_cache[key] = parse_diff(diff_lines or {})
      self.expanded_files[key] = true
      self:render()
    end)
  end

  if section == "untracked" then
    -- Untracked files: use git diff --no-index for proper diff output
    git.diff_untracked(path, { cwd = self.repo_state.repo_root }, on_diff_result)
    return
  end

  -- Fetch the diff for staged/unstaged files
  local staged = (section == "staged")
  git.diff(path, staged, { cwd = self.repo_state.repo_root }, function(diff_lines, err)
    if err then
      vim.notify("[gitlad] Diff error: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      -- Parse the diff into structured data with hunks
      self.diff_cache[key] = parse_diff(diff_lines or {})
      self.expanded_files[key] = true
      self:render()
    end)
  end)
end

--- Navigate to next file entry
function StatusBuffer:_goto_next_file()
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
function StatusBuffer:_goto_prev_file()
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
function StatusBuffer:_goto_next_section()
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
function StatusBuffer:_goto_prev_section()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    if self.section_lines[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Visit the file at cursor
function StatusBuffer:_visit_file()
  local path = self:_get_current_file()
  if path then
    local full_path = self.repo_state.repo_root .. path
    -- Close status and open file
    self:close()
    vim.cmd("edit " .. vim.fn.fnameescape(full_path))
    return
  end

  -- If not on a file, check if on a commit - toggle expand
  local commit = self:_get_current_commit()
  if commit then
    self:_toggle_diff()
  end
end

--- Stage all unstaged and untracked files
function StatusBuffer:_stage_all()
  self.repo_state:stage_all()
end

--- Unstage all staged files
function StatusBuffer:_unstage_all()
  self.repo_state:unstage_all()
end

--- Discard changes for file at cursor, or entire section if on section header
function StatusBuffer:_discard_current()
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

  -- Not on section header - check for file
  local path, section = self:_get_current_file()
  if not path then
    return
  end

  if section == "staged" then
    vim.notify("[gitlad] Cannot discard staged changes. Unstage first.", vim.log.levels.WARN)
    return
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

--- Discard changes for visually selected files
function StatusBuffer:_discard_visual()
  local start_line, end_line = get_visual_selection_range()

  -- Collect all file entries in the selection that can be discarded
  local allowed_sections = { unstaged = true, untracked = true }
  local files, _ = collect_files_in_range(self.line_map, start_line, end_line, allowed_sections)

  if #files == 0 then
    vim.notify("[gitlad] No discardable files in selection", vim.log.levels.INFO)
    return
  end

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
end

--- Render the status buffer
function StatusBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local status = self.repo_state.status
  if not status then
    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "Loading..." })
    return
  end

  local cfg = config.get()
  local lines = {}
  self.line_map = {} -- Reset line map
  self.section_lines = {} -- Reset section lines
  self.sign_lines = {} -- Reset sign lines

  -- Helper to add a section header and track its line number
  local function add_section_header(name, section, count)
    table.insert(lines, string.format("%s (%d)", name, count))
    self.section_lines[#lines] = { name = name, section = section }
  end

  -- Helper to add a file entry and track its line number
  local function add_file_line(entry, section, sign, status_char, use_display)
    local display = use_display
        and entry.orig_path
        and string.format("%s -> %s", entry.orig_path, entry.path)
      or entry.path

    -- Check if this file is expanded
    local key = diff_cache_key(entry.path, section)
    local is_expanded = self.expanded_files[key]

    -- Format without expand indicator (it goes in sign column)
    local line_text = status_char and string.format("%s %s %s", sign, status_char, display)
      or string.format("%s   %s", sign, display)
    table.insert(lines, line_text)
    self.line_map[#lines] = { path = entry.path, section = section }
    self.sign_lines[#lines] = { expanded = is_expanded }

    -- Add diff lines if expanded
    if is_expanded and self.diff_cache[key] then
      local diff_data = self.diff_cache[key]
      local current_hunk_index = 0

      for _, diff_line in ipairs(diff_data.display_lines) do
        -- Track which hunk we're in
        if diff_line:match("^@@") then
          current_hunk_index = current_hunk_index + 1
        end

        table.insert(lines, "  " .. diff_line)
        -- Diff lines map to the file and include hunk index
        self.line_map[#lines] = {
          path = entry.path,
          section = section,
          hunk_index = current_hunk_index > 0 and current_hunk_index or nil,
        }
      end
    end
  end

  -- Helper to render a commit section using log_list component
  local function add_commit_section(title, commits, section_type)
    if #commits == 0 then
      return
    end

    local is_collapsed = self.collapsed_sections[section_type]
    -- No indicator in text - it goes in sign column
    table.insert(lines, string.format("%s (%d)", title, #commits))
    self.section_lines[#lines] = { name = title, section = section_type }
    self.sign_lines[#lines] = { expanded = not is_collapsed }

    -- Only render commits if section is not collapsed
    if not is_collapsed then
      local result = log_list.render(commits, self.expanded_commits, {
        indent = 0,
        section = section_type,
      })

      for i, line in ipairs(result.lines) do
        table.insert(lines, line)
        local info = result.line_info[i]
        if info then
          -- Commits now tracked in line_map with CommitLineInfo
          self.line_map[#lines] = info
        end
      end
    end
    table.insert(lines, "")
  end

  -- Header
  local head_line = "Head:     " .. status.branch
  if status.head_commit_msg then
    head_line = head_line .. "  " .. status.head_commit_msg
  end
  if self.repo_state.refreshing then
    head_line = head_line .. "  (Refreshing...)"
  end
  table.insert(lines, head_line)

  -- Merge (upstream) line
  if status.upstream then
    local merge_line = "Merge:    " .. status.upstream
    if status.merge_commit_msg then
      merge_line = merge_line .. "  " .. status.merge_commit_msg
    end
    if status.ahead > 0 or status.behind > 0 then
      merge_line = merge_line .. string.format(" [+%d/-%d]", status.ahead, status.behind)
    end
    table.insert(lines, merge_line)
  end

  -- Push line (only if different from merge)
  if status.push_remote then
    local push_line = "Push:     " .. status.push_remote
    if status.push_commit_msg then
      push_line = push_line .. "  " .. status.push_commit_msg
    end
    if status.push_ahead > 0 or status.push_behind > 0 then
      push_line = push_line .. string.format(" [+%d/-%d]", status.push_ahead, status.push_behind)
    end
    table.insert(lines, push_line)
  end

  table.insert(lines, "")

  -- === File sections (staged/unstaged/untracked/conflicted) - shown first, magit style ===

  -- Untracked files
  if #status.untracked > 0 then
    add_section_header("Untracked", "untracked", #status.untracked)
    for _, entry in ipairs(status.untracked) do
      add_file_line(entry, "untracked", cfg.signs.untracked, nil, false)
    end
    table.insert(lines, "")
  end

  -- Unstaged changes
  if #status.unstaged > 0 then
    add_section_header("Unstaged", "unstaged", #status.unstaged)
    for _, entry in ipairs(status.unstaged) do
      add_file_line(entry, "unstaged", cfg.signs.unstaged, entry.worktree_status, false)
    end
    table.insert(lines, "")
  end

  -- Staged changes
  if #status.staged > 0 then
    add_section_header("Staged", "staged", #status.staged)
    for _, entry in ipairs(status.staged) do
      add_file_line(entry, "staged", cfg.signs.staged, entry.index_status, true)
    end
    table.insert(lines, "")
  end

  -- Conflicted files
  if #status.conflicted > 0 then
    add_section_header("Conflicted", "conflicted", #status.conflicted)
    for _, entry in ipairs(status.conflicted) do
      add_file_line(entry, "conflicted", cfg.signs.conflict, nil, false)
    end
    table.insert(lines, "")
  end

  -- Clean working tree message
  if
    #status.staged == 0
    and #status.unstaged == 0
    and #status.untracked == 0
    and #status.conflicted == 0
  then
    table.insert(lines, "Nothing to commit, working tree clean")
    table.insert(lines, "")
  end

  -- === Commit sections (unpulled/unpushed/recent) - shown after file changes, magit style ===

  -- Track whether we have any unpushed commits (used to decide whether to show recent commits)
  local has_unpushed_upstream = status.upstream
    and status.unpushed_upstream
    and #status.unpushed_upstream > 0

  -- Unpulled/Unpushed sections for upstream (merge branch)
  if status.upstream then
    add_commit_section(
      "Unpulled from " .. status.upstream,
      status.unpulled_upstream or {},
      "unpulled_upstream"
    )

    if has_unpushed_upstream then
      add_commit_section(
        "Unmerged into " .. status.upstream,
        status.unpushed_upstream or {},
        "unpushed_upstream"
      )
    end
  end

  -- Unpulled/Unpushed sections for push remote (if different)
  if status.push_remote then
    add_commit_section(
      "Unpulled from " .. status.push_remote,
      status.unpulled_push or {},
      "unpulled_push"
    )
    add_commit_section(
      "Unpushed to " .. status.push_remote,
      status.unpushed_push or {},
      "unpushed_push"
    )
  end

  -- Show "Recent commits" when there's nothing to push (like magit)
  -- This provides context even when the branch is in sync with upstream
  local has_any_unpushed = has_unpushed_upstream
    or (status.unpushed_push and #status.unpushed_push > 0)

  if not has_any_unpushed and status.recent_commits and #status.recent_commits > 0 then
    add_commit_section("Recent commits", status.recent_commits, "recent")
  end

  -- Help line
  table.insert(lines, "")
  table.insert(lines, "Press ? for help")

  -- Allow modification while updating buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply syntax highlighting
  hl.apply_status_highlights(self.bufnr, lines, self.line_map, self.section_lines)

  -- Apply treesitter highlighting to expanded diffs
  hl.apply_diff_treesitter_highlights(self.bufnr, lines, self.line_map, self.diff_cache)

  -- Place expand/collapse indicators in sign column
  self:_place_signs()

  -- Make buffer non-modifiable to prevent accidental edits
  vim.bo[self.bufnr].modifiable = false
end

--- Place expand/collapse signs in the sign column
function StatusBuffer:_place_signs()
  -- Clear existing signs
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns_signs, 0, -1)

  -- Place signs for lines that have expand indicators
  for line_num, sign_info in pairs(self.sign_lines) do
    local sign_text = sign_info.expanded and "v" or ">"
    local sign_hl = "GitladExpandIndicator"

    vim.api.nvim_buf_set_extmark(self.bufnr, ns_signs, line_num - 1, 0, {
      sign_text = sign_text,
      sign_hl_group = sign_hl,
      priority = 10,
    })
  end
end

--- Open the status buffer in a window
function StatusBuffer:open()
  -- Check if already open in a window with the status buffer displayed
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    local win_buf = vim.api.nvim_win_get_buf(self.winnr)
    if win_buf == self.bufnr then
      -- Status buffer is already displayed in this window, just focus it
      vim.api.nvim_set_current_win(self.winnr)
      return
    end
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window-local options for clean status display
  vim.wo[self.winnr].number = false
  vim.wo[self.winnr].relativenumber = false
  vim.wo[self.winnr].signcolumn = "yes:1"
  vim.wo[self.winnr].foldcolumn = "0"
  vim.wo[self.winnr].wrap = false

  -- Initial render
  self:render()

  -- Trigger refresh
  self.repo_state:refresh_status()
end

--- Close the status buffer
function StatusBuffer:close()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = nil
    return
  end

  -- Check if this is the last window
  local windows = vim.api.nvim_list_wins()
  if #windows == 1 then
    -- Can't close last window, switch to an empty buffer instead
    local empty_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(self.winnr, empty_buf)
  else
    -- Try to close the window, but handle the case where it's actually
    -- the last "real" window (can happen with floating windows)
    local ok, err = pcall(vim.api.nvim_win_close, self.winnr, false)
    if not ok and err and err:match("E444") then
      -- Fall back to switching to empty buffer
      local empty_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(self.winnr, empty_buf)
    elseif not ok then
      -- Re-throw other errors
      error(err)
    end
  end

  self.winnr = nil
end

--- Open status view for current repository
---@param repo_state_override? RepoState Optional repo state to use instead of detecting from cwd
function M.open(repo_state_override)
  local repo_state = repo_state_override or state.get()
  if not repo_state then
    vim.notify("[gitlad] Not in a git repository", vim.log.levels.WARN)
    return
  end

  local buf = get_or_create_buffer(repo_state)
  buf:open()
end

--- Close status view
function M.close()
  local repo_state = state.get()
  if not repo_state then
    return
  end

  local key = repo_state.repo_root
  local buf = status_buffers[key]
  if buf then
    buf:close()
  end
end

--- Clear all status buffers (useful for testing)
function M.clear_all()
  for _, buf in pairs(status_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  status_buffers = {}
end

return M
