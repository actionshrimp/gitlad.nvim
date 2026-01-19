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
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")
local log_list = require("gitlad.ui.components.log_list")
local signs_util = require("gitlad.ui.utils.signs")

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
---@field section "staged"|"unstaged"|"untracked"|"conflicted"|"stashes" Section type

---@class StashLineInfo
---@field type "stash" Discriminator for union type
---@field stash StashEntry Full stash entry
---@field section "stashes" Section identifier

---@class SubmoduleLineInfo
---@field type "submodule" Discriminator for union type
---@field submodule SubmoduleEntry Full submodule entry
---@field section "submodules" Section identifier

---@class SignInfo
---@field expanded boolean Whether the item is expanded

---@class StatusBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field line_map table<number, LineInfo|CommitLineInfo|StashLineInfo|SubmoduleLineInfo> Map of line numbers to file, commit, stash, or submodule info
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
  -- Initialize submodules section visibility from config
  local cfg = require("gitlad.config").get()
  self.show_submodules_section = cfg.status and cfg.status.show_submodules_section or false

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

  -- Discard (context-aware: drops stash when on stash entry)
  keymap.set(bufnr, "n", "x", function()
    local stash = self:_get_current_stash()
    if stash then
      self:_stash_drop(stash)
    else
      self:_discard_current()
    end
  end, "Discard changes / Drop stash")
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
  -- Context-aware: pops stash when on stash entry
  keymap.set(bufnr, "n", "p", function()
    local stash = self:_get_current_stash()
    if stash then
      self:_stash_pop(stash)
    else
      local push_popup = require("gitlad.popups.push")
      push_popup.open(self.repo_state)
    end
  end, "Push popup / Pop stash")

  -- Apply stash at point
  keymap.set(bufnr, "n", "a", function()
    local stash = self:_get_current_stash()
    if stash then
      self:_stash_apply(stash)
    end
  end, "Apply stash")

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
  -- Yank bindings (evil-collection style: y prefix)
  -- yy is left to vim's default (yank line)
  keymap.set(bufnr, "n", "ys", function()
    self:_yank_section_value()
  end, "Yank section value")
  keymap.set(bufnr, "n", "yr", function()
    local refs_popup = require("gitlad.popups.refs")
    refs_popup.open(self.repo_state)
  end, "Show references")

  -- Stash popup (passes stash at point for context-aware operations)
  keymap.set(bufnr, "n", "z", function()
    local stash_popup = require("gitlad.popups.stash")
    local stash = self:_get_current_stash()
    local context = stash and { stash = stash } or nil
    stash_popup.open(self.repo_state, context)
  end, "Stash popup")

  -- Cherry-pick popup
  keymap.set(bufnr, "n", "A", function()
    local cherrypick_popup = require("gitlad.popups.cherrypick")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    cherrypick_popup.open(self.repo_state, context)
  end, "Cherry-pick popup")

  -- Revert popup (evil-collection-magit uses '_' - you're "subtracting" a commit)
  keymap.set(bufnr, "n", "_", function()
    local revert_popup = require("gitlad.popups.revert")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    revert_popup.open(self.repo_state, context)
  end, "Revert popup")

  -- Reset popup (neogit/evil-collection-magit style: X for destructive reset)
  keymap.set(bufnr, "n", "X", function()
    local reset_popup = require("gitlad.popups.reset")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    reset_popup.open(self.repo_state, context)
  end, "Reset popup")

  -- Rebase popup
  keymap.set(bufnr, "n", "r", function()
    local rebase_popup = require("gitlad.popups.rebase")
    rebase_popup.open(self.repo_state)
  end, "Rebase popup")

  -- Submodule popup (evil-collection-magit style: ' for submodule)
  keymap.set(bufnr, "n", "'", function()
    local submodule_popup = require("gitlad.popups.submodule")
    local submodule = self:_get_current_submodule()
    local context = submodule and { submodule = submodule } or nil
    submodule_popup.open(self.repo_state, context)
  end, "Submodule popup")

  -- Visual mode submodule popup (for operations on selected submodules)
  keymap.set(bufnr, "v", "'", function()
    local submodule_popup = require("gitlad.popups.submodule")
    local paths = self:_get_selected_submodule_paths()
    local context = #paths > 0 and { paths = paths } or nil
    submodule_popup.open(self.repo_state, context)
  end, "Submodule popup (selection)")
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

--- Get the submodule at the current cursor position
--- Works for both the dedicated Submodules section and submodule files in unstaged/staged
---@return SubmoduleEntry|nil submodule
function StatusBuffer:_get_current_submodule()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if not info then
    return nil
  end

  -- Check if in dedicated Submodules section
  if info.type == "submodule" then
    return info.submodule
  end

  -- Check if it's a file entry that is a submodule (from unstaged/staged sections)
  if info.type == "file" and info.entry and info.entry.submodule then
    -- Create a SubmoduleEntry-like object from the file entry
    return {
      path = info.entry.path,
      sha = "", -- Not available from status entry
      status = "modified",
      describe = nil,
    }
  end

  return nil
end

--- Get the stash at the current cursor position
---@return StashEntry|nil stash
function StatusBuffer:_get_current_stash()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.type == "stash" then
    return info.stash
  end

  return nil
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

--- Get selected submodule paths (visual mode)
---@return string[] Selected submodule paths
function StatusBuffer:_get_selected_submodule_paths()
  local mode = vim.fn.mode()
  if not mode:match("[vV]") then
    return {}
  end

  -- Exit visual mode to get marks
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  local paths = {}
  for line = start_line, end_line do
    local info = self.line_map[line]
    if info then
      -- Check dedicated Submodules section
      if info.type == "submodule" then
        table.insert(paths, info.submodule.path)
      -- Check file entries that are submodules (from unstaged/staged sections)
      elseif info.type == "file" and info.entry and info.entry.submodule then
        table.insert(paths, info.entry.path)
      end
    end
  end

  return paths
end

--- Get diff context for current cursor position
---@return DiffContext
function StatusBuffer:_get_diff_context()
  local file_path, section = self:_get_current_file()
  local commit = self:_get_current_commit()
  return { file_path = file_path, section = section, commit = commit }
end

--- Yank section value to clipboard (commit hash, file path, or stash name)
function StatusBuffer:_yank_section_value()
  -- Try commit first
  local commit = self:_get_current_commit()
  if commit then
    vim.fn.setreg("+", commit.hash)
    vim.fn.setreg('"', commit.hash)
    vim.notify("[gitlad] Yanked: " .. commit.hash, vim.log.levels.INFO)
    return
  end

  -- Try file path
  local file_path = self:_get_current_file()
  if file_path then
    vim.fn.setreg("+", file_path)
    vim.fn.setreg('"', file_path)
    vim.notify("[gitlad] Yanked: " .. file_path, vim.log.levels.INFO)
    return
  end

  -- Try stash
  local stash = self:_get_current_stash()
  if stash then
    vim.fn.setreg("+", stash.name)
    vim.fn.setreg('"', stash.name)
    vim.notify("[gitlad] Yanked: " .. stash.name, vim.log.levels.INFO)
    return
  end

  vim.notify("[gitlad] Nothing to yank at cursor", vim.log.levels.INFO)
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
    -- Check if this is a collapsible section (commit sections, stashes, submodules)
    local collapsible_sections = {
      unpulled_upstream = true,
      unpushed_upstream = true,
      unpulled_push = true,
      unpushed_push = true,
      recent = true,
      stashes = true,
      submodules = true,
    }
    if collapsible_sections[section_info.section] then
      -- Toggle the section collapsed state
      local section_key = section_info.section
      self.collapsed_sections[section_key] = not self.collapsed_sections[section_key]
      self:render()
      return
    end
  end

  -- Check if on a submodule entry
  local submodule = self:_get_current_submodule()
  if submodule then
    local key = "submodule:" .. submodule.path

    -- Toggle expanded state
    if self.expanded_files[key] then
      self.expanded_files[key] = false
      self.diff_cache[key] = nil
      self:render()
      return
    end

    -- For submodules, fetch the recorded SHA and show the diff
    local opts = { cwd = self.repo_state.repo_root }
    git.submodule_recorded_sha(submodule.path, false, opts, function(recorded_sha, err)
      if err then
        vim.notify("[gitlad] Submodule SHA error: " .. err, vim.log.levels.ERROR)
        return
      end

      vim.schedule(function()
        -- Create a simple diff showing old->new SHA
        local old_sha = recorded_sha or "0000000000000000000000000000000000000000"
        local new_sha = submodule.sha

        -- Store as a special "submodule diff" format
        self.diff_cache[key] = {
          is_submodule = true,
          old_sha = old_sha,
          new_sha = new_sha,
          hunks = {}, -- No hunks for submodule diffs
        }
        self.expanded_files[key] = true
        self:render()
      end)
    end)
    return
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
  -- Check if on a submodule - open its directory
  local submodule = self:_get_current_submodule()
  if submodule then
    local submodule_path = self.repo_state.repo_root .. submodule.path
    -- Close status and open submodule directory
    self:close()
    vim.cmd("edit " .. vim.fn.fnameescape(submodule_path))
    return
  end

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

--- Pop stash at point (apply and remove)
---@param stash StashEntry
function StatusBuffer:_stash_pop(stash)
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
---@param stash StashEntry
function StatusBuffer:_stash_apply(stash)
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
---@param stash StashEntry
function StatusBuffer:_stash_drop(stash)
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

  -- Sequencer state (cherry-pick/revert/rebase in progress)
  if status.cherry_pick_in_progress then
    local short_oid = status.sequencer_head_oid and status.sequencer_head_oid:sub(1, 7) or "unknown"
    local seq_line = "Cherry-picking: " .. short_oid
    if status.sequencer_head_subject then
      seq_line = seq_line .. " " .. status.sequencer_head_subject
    end
    table.insert(lines, seq_line)
  elseif status.revert_in_progress then
    local short_oid = status.sequencer_head_oid and status.sequencer_head_oid:sub(1, 7) or "unknown"
    local seq_line = "Reverting: " .. short_oid
    if status.sequencer_head_subject then
      seq_line = seq_line .. " " .. status.sequencer_head_subject
    end
    table.insert(lines, seq_line)
  elseif status.rebase_in_progress then
    table.insert(lines, "Rebasing: resolve conflicts and press 'r' to continue")
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

  -- === Stashes section (after file changes, before commit sections) ===
  if status.stashes and #status.stashes > 0 then
    local is_collapsed = self.collapsed_sections["stashes"]
    table.insert(lines, string.format("Stashes (%d)", #status.stashes))
    self.section_lines[#lines] = { name = "Stashes", section = "stashes" }
    self.sign_lines[#lines] = { expanded = not is_collapsed }

    if not is_collapsed then
      for _, stash in ipairs(status.stashes) do
        table.insert(lines, string.format("%s %s", stash.ref, stash.message))
        self.line_map[#lines] = {
          type = "stash",
          stash = stash,
          section = "stashes",
        }
      end
    end
    table.insert(lines, "")
  end

  -- === Submodules section (after stashes, before commit sections) ===
  -- Only show if enabled via config or runtime toggle (off by default, like magit)
  if self.show_submodules_section and status.submodules and #status.submodules > 0 then
    local is_collapsed = self.collapsed_sections["submodules"]
    table.insert(lines, string.format("Submodules (%d)", #status.submodules))
    self.section_lines[#lines] = { name = "Submodules", section = "submodules" }
    self.sign_lines[#lines] = { expanded = not is_collapsed }

    if not is_collapsed then
      for _, submodule in ipairs(status.submodules) do
        -- Format: status indicator, path, (describe or SHA)
        local status_char = ""
        if submodule.status == "modified" then
          status_char = "+"
        elseif submodule.status == "uninitialized" then
          status_char = "-"
        elseif submodule.status == "merge_conflict" then
          status_char = "U"
        end

        -- Show describe if available, otherwise abbreviated SHA
        local info = submodule.describe or submodule.sha:sub(1, 7)
        local line_text
        if status_char ~= "" then
          line_text = string.format("  %s %s (%s)", status_char, submodule.path, info)
        else
          line_text = string.format("    %s (%s)", submodule.path, info)
        end

        table.insert(lines, line_text)
        self.line_map[#lines] = {
          type = "submodule",
          submodule = submodule,
          section = "submodules",
        }

        -- Check if submodule is expanded and render SHA diff
        local cache_key = "submodule:" .. submodule.path
        if self.expanded_files[cache_key] then
          local diff_data = self.diff_cache[cache_key]
          if diff_data and diff_data.is_submodule then
            self.sign_lines[#lines] = { expanded = true }
            -- Render the SHA diff lines: -oldsha, +newsha
            table.insert(lines, "    -" .. diff_data.old_sha)
            table.insert(lines, "    +" .. diff_data.new_sha)
          end
        else
          self.sign_lines[#lines] = { expanded = false }
        end
      end
    end
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

  -- Always show "Recent commits" section for context
  if status.recent_commits and #status.recent_commits > 0 then
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
  signs_util.place_expand_signs(self.bufnr, self.sign_lines, ns_signs)
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
  utils.setup_view_window_options(self.winnr)

  -- Initial render
  self:render()

  -- Trigger refresh
  self.repo_state:refresh_status()
end

--- Toggle the dedicated Submodules section visibility
function StatusBuffer:toggle_submodules_section()
  self.show_submodules_section = not self.show_submodules_section
  self:render()
  local state = self.show_submodules_section and "shown" or "hidden"
  vim.notify("[gitlad] Submodules section " .. state, vim.log.levels.INFO)
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

--- Get the status buffer for a repo (if it exists)
---@param repo_state RepoState
---@return StatusBuffer|nil
function M.get_buffer(repo_state)
  local key = repo_state.repo_root
  local buf = status_buffers[key]
  if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
    return buf
  end
  return nil
end

return M
