---@mod gitlad.ui.views.status_diffs Status buffer diff module
---@brief [[
--- Extracted diff functionality for the status buffer.
--- Provides diff toggling, hunk patch building, and visibility controls.
---@brief ]]

local M = {}

local git = require("gitlad.git")

-- Import shared constants
local status_render = require("gitlad.ui.views.status_render")
local COLLAPSIBLE_SECTIONS = status_render.COLLAPSIBLE_SECTIONS
local diff_cache_key = status_render.diff_cache_key

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

--- Build a patch for a single hunk
---@param self StatusBuffer
---@param diff_data DiffData
---@param hunk_index number
---@return string[]|nil patch_lines
local function build_hunk_patch(self, diff_data, hunk_index)
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

--- Build a partial patch from selected lines within a hunk
--- For staging (reverse=false): selected +/- lines are kept, unselected + omitted, unselected - become context
--- For unstaging (reverse=true): selected +/- lines are kept, unselected + become context, unselected - omitted
---@param self StatusBuffer
---@param diff_data DiffData
---@param hunk_index number
---@param selected_display_indices table<number, boolean> Map of display line indices (1-based within display_lines) that are selected
---@param reverse boolean Whether this patch will be applied with --reverse (for unstaging)
---@return string[]|nil patch_lines
local function build_partial_hunk_patch(
  self,
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

--- Toggle diff view for current file, hunk, or section
--- Expansion states for files:
---   nil/false = collapsed (no diff shown)
---   {} = headers mode (show @@ lines only)
---   { [n] = true } = headers mode with specific hunks expanded
---   true = fully expanded (all hunks)
---@param self StatusBuffer
local function toggle_diff(self)
  -- First check if we're on a section header (for commit sections)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local section_info = self.section_lines[line]

  if section_info then
    -- Check if this is a collapsible section (commit sections, stashes, submodules)
    if COLLAPSIBLE_SECTIONS[section_info.section] then
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

    -- Toggle expanded state (submodules don't have hunk-level expansion)
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

  -- Get line info to check if we're on a hunk header
  local line_info = self.line_map[line]
  if line_info and line_info.type == "file" and line_info.is_hunk_header then
    -- We're on a hunk header - toggle this specific hunk
    local key = diff_cache_key(line_info.path, line_info.section)
    local expansion_state = self.expanded_files[key]

    -- Only toggle individual hunks when in headers mode (table)
    if type(expansion_state) == "table" then
      local hunk_index = line_info.hunk_index
      expansion_state[hunk_index] = not expansion_state[hunk_index]
      self:render()
      return
    end
    -- If fully expanded (true), don't toggle individual hunks - fall through to file toggle
  end

  local path, section = self:_get_current_file()
  if not path then
    return
  end

  local key = diff_cache_key(path, section)
  local current_state = self.expanded_files[key]

  -- Cycle through states: collapsed -> headers -> expanded -> collapsed
  if current_state == true then
    -- Fully expanded -> collapse
    self.expanded_files[key] = false
    self.diff_cache[key] = nil
    self:render()
    return
  elseif type(current_state) == "table" then
    -- Headers mode -> fully expand
    self.expanded_files[key] = true
    self:render()
    return
  end

  -- Collapsed -> fetch diff and show headers
  local function on_diff_result(diff_lines, err)
    if err then
      vim.notify("[gitlad] Diff error: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      self.diff_cache[key] = parse_diff(diff_lines or {})
      self.expanded_files[key] = {} -- Headers mode (empty table = no hunks expanded)
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
  git.diff(path, staged, { cwd = self.repo_state.repo_root }, on_diff_result)
end

--- Expand all file diffs (batch fetch)
--- Fetches diffs for all files and calls callback when complete
---@param self StatusBuffer
---@param callback fun(keys: string[]) Called with list of cache keys when all diffs fetched
local function expand_all_files(self, callback)
  local status = self.repo_state.status
  if not status then
    callback({})
    return
  end

  local all_files = {}

  -- Collect all files with their section info
  for _, entry in ipairs(status.staged or {}) do
    table.insert(all_files, { entry = entry, section = "staged", staged = true })
  end
  for _, entry in ipairs(status.unstaged or {}) do
    table.insert(all_files, { entry = entry, section = "unstaged", staged = false })
  end
  for _, entry in ipairs(status.untracked or {}) do
    table.insert(all_files, { entry = entry, section = "untracked", untracked = true })
  end
  for _, entry in ipairs(status.conflicted or {}) do
    table.insert(all_files, { entry = entry, section = "conflicted", staged = false })
  end

  if #all_files == 0 then
    callback({})
    return
  end

  local pending = 0
  local keys_to_expand = {}
  local opts = { cwd = self.repo_state.repo_root }

  for _, file_info in ipairs(all_files) do
    local key = diff_cache_key(file_info.entry.path, file_info.section)
    table.insert(keys_to_expand, key)

    if not self.diff_cache[key] then
      pending = pending + 1

      local function on_result(diff_lines, err)
        if not err then
          vim.schedule(function()
            self.diff_cache[key] = parse_diff(diff_lines or {})
          end)
        end
        pending = pending - 1
        if pending == 0 then
          vim.schedule(function()
            callback(keys_to_expand)
          end)
        end
      end

      if file_info.untracked then
        git.diff_untracked(file_info.entry.path, opts, on_result)
      else
        git.diff(file_info.entry.path, file_info.staged, opts, on_result)
      end
    end
  end

  if pending == 0 then
    callback(keys_to_expand)
  end
end

--- Apply a specific visibility level
--- Level 1: Section headers only (all collapsed)
--- Level 2: Sections + items (sections expanded, no diffs)
--- Level 3: Items + file diffs (all file diffs expanded)
--- Level 4: Everything (file diffs + commit details)
---@param self StatusBuffer
---@param level number Visibility level (1-4)
local function apply_visibility_level(self, level)
  level = math.max(1, math.min(4, level)) -- Clamp to 1-4
  self.visibility_level = level

  local status = self.repo_state.status
  if not status then
    return
  end

  if level == 1 then
    -- Collapse all collapsible sections, clear all expansions
    for section_name, _ in pairs(COLLAPSIBLE_SECTIONS) do
      self.collapsed_sections[section_name] = true
    end
    self.expanded_files = {}
    self.expanded_commits = {}
    self:render()
  elseif level == 2 then
    -- Expand all sections, clear all diffs and commit details
    self.collapsed_sections = {}
    self.expanded_files = {}
    self.expanded_commits = {}
    self:render()
  elseif level == 3 then
    -- Expand all sections and show file diff headers (hunks collapsed)
    self.collapsed_sections = {}
    self.expanded_commits = {}
    expand_all_files(self, function(keys)
      for _, key in ipairs(keys) do
        self.expanded_files[key] = {} -- Headers mode (empty table = no hunks expanded)
      end
      self:render()
    end)
  elseif level == 4 then
    -- Expand everything: sections, file diffs, and commit details
    self.collapsed_sections = {}

    -- Expand all commits
    local commits_to_expand = {}
    for _, commits in pairs({
      status.unpushed_upstream or {},
      status.unpulled_upstream or {},
      status.unpushed_push or {},
      status.unpulled_push or {},
      status.recent or {},
    }) do
      for _, commit in ipairs(commits) do
        commits_to_expand[commit.hash] = true
      end
    end
    self.expanded_commits = commits_to_expand

    expand_all_files(self, function(keys)
      for _, key in ipairs(keys) do
        self.expanded_files[key] = true
      end
      self:render()
    end)
  end
end

--- Cycle through visibility levels (1 -> 2 -> 3 -> 4 -> 1)
---@param self StatusBuffer
local function cycle_visibility_level(self)
  local next_level = (self.visibility_level % 4) + 1
  apply_visibility_level(self, next_level)
end

--- Attach diff methods to StatusBuffer class
---@param StatusBuffer table The StatusBuffer class
function M.setup(StatusBuffer)
  StatusBuffer._build_hunk_patch = build_hunk_patch
  StatusBuffer._build_partial_hunk_patch = build_partial_hunk_patch
  StatusBuffer._toggle_diff = toggle_diff
  StatusBuffer._expand_all_files = expand_all_files
  StatusBuffer._apply_visibility_level = apply_visibility_level
  StatusBuffer._cycle_visibility_level = cycle_visibility_level
end

return M
