---@mod gitlad.ui.views.status Status buffer view
---@brief [[
--- Main status buffer showing staged, unstaged, and untracked files.
--- This module is the entry point and wires together the component modules:
--- - status_render.lua: Render functionality
--- - status_keymaps.lua: Keymap setup
--- - status_staging.lua: Staging/unstaging operations
--- - status_diffs.lua: Diff/hunk functionality
--- - status_navigation.lua: Navigation functions
---@brief ]]

local M = {}

local state = require("gitlad.state")
local utils = require("gitlad.utils")
local spinner_util = require("gitlad.ui.utils.spinner")
local expansion = require("gitlad.state.expansion")
local config = require("gitlad.config")
local watcher_mod = require("gitlad.watcher")

-- Import component modules
local status_render = require("gitlad.ui.views.status_render")
local status_keymaps = require("gitlad.ui.views.status_keymaps")
local status_staging = require("gitlad.ui.views.status_staging")
local status_diffs = require("gitlad.ui.views.status_diffs")
local status_navigation = require("gitlad.ui.views.status_navigation")

---@class LineInfo
---@field type "file" Discriminator for union type
---@field path string File path
---@field section "staged"|"unstaged"|"untracked"|"conflicted" Section type
---@field entry GitStatusEntry The full status entry (contains submodule field)
---@field hunk_index number|nil Index of hunk if this is a diff line
---@field is_hunk_header boolean|nil True if this line is a @@ hunk header

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

---@class CursorTarget
---@field path string File path to move cursor to
---@field section string Section the file should be in

---@class RememberedSectionState
---@field files table<string, boolean|table<number, boolean>> Map of "section:path" to expansion state

---@class StatusBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field prev_bufnr number|nil Buffer that was active before opening gitlad
---@field repo_state RepoState Repository state
---@field line_map table<number, LineInfo|CommitLineInfo|StashLineInfo|SubmoduleLineInfo> Map of line numbers to file, commit, stash, or submodule info
---@field section_lines table<number, SectionInfo> Map of line numbers to section headers
---@field expanded_files table<string, boolean|table<number, boolean>> Map of "section:path" to expansion state (false=collapsed, {}=headers, {[n]=true}=per-hunk, true=all)
---@field expanded_commits table<string, boolean> Map of commit hash to expanded state
---@field diff_cache table<string, DiffData> Map of "section:path" to parsed diff data
---@field sign_lines table<number, SignInfo> Map of line numbers to sign info
---@field spinner Spinner Animated spinner for refresh indicator
---@field status_line_num number|nil Line number of the status indicator line
---@field pending_cursor_target CursorTarget|nil Target for cursor positioning after render
---@field visibility_level number Current visibility level (1-4, default 2)
---@field remembered_file_states table<string, table<number, boolean>> Saved hunk states when files collapse (for restoring on re-expand)
---@field remembered_section_states table<string, RememberedSectionState> Saved file states when sections collapse (for restoring on re-expand)
---@field expansion ExpansionState Elm-style expansion state (source of truth)
---@field watcher Watcher|nil File system watcher instance (if enabled)
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

-- Attach methods from component modules
status_render.setup(StatusBuffer)
status_keymaps.setup(StatusBuffer)
status_staging.setup(StatusBuffer)
status_diffs.setup(StatusBuffer)
status_navigation.setup(StatusBuffer)

-- Active status buffers by repo root
local status_buffers = {}

--- Find any window currently displaying a buffer
---@param bufnr number
---@return number|nil winnr Window number if found
local function find_window_with_buffer(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

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
  self.visibility_level = 2 -- Current visibility level (1=headers, 2=items, 3=diffs, 4=all)
  self.remembered_file_states = {} -- Saved hunk states when files collapse
  self.remembered_section_states = {} -- Saved file states when sections collapse
  -- Initialize Elm-style expansion state
  self.expansion = expansion.reducer.new(2)
  self.status_line_num = nil -- Line number of the status indicator

  -- Create spinner for refresh indicator
  self.spinner = spinner_util.new()
  -- Track whether initial data load has completed (for loading animation)
  self.initial_load_complete = false

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options (include repo path for multi-project support)
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://status[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Listen for status updates
  repo_state:on("status", function()
    vim.schedule(function()
      -- Manage spinner based on refreshing state
      if repo_state.refreshing then
        self.spinner:start(function()
          self:_update_status_line()
        end)
      else
        self.spinner:stop()
        -- Clear stale flag since we just refreshed
        self.spinner:clear_stale()
        -- Mark initial load as complete once data arrives
        if not self.initial_load_complete then
          self.initial_load_complete = true
        end
      end

      -- Clear diff/expansion data when status changes to avoid stale data
      self.expanded_files = {}
      self.expanded_commits = {}
      self.diff_cache = {}
      self:render()

      -- Position cursor at first item after fresh open (only when data has arrived, not during refresh)
      if self._position_cursor_on_render and not repo_state.refreshing then
        self._position_cursor_on_render = false
        self:_goto_first_item()
      end
    end)
  end)

  -- Listen for stale updates (file watcher detected external git changes)
  repo_state:on("stale", function()
    vim.schedule(function()
      -- Only show stale indicator when not actively refreshing
      if not repo_state.refreshing then
        self.spinner:set_stale()
        self:_update_status_line()
      end
    end)
  end)

  -- Create file watcher if enabled in config
  local cfg = config.get()
  if cfg.watcher and cfg.watcher.enabled then
    self.watcher = watcher_mod.new(repo_state, {
      cooldown_ms = cfg.watcher.cooldown_ms,
      mode = cfg.watcher.mode,
      auto_refresh_debounce_ms = cfg.watcher.auto_refresh_debounce_ms,
      on_refresh = function()
        -- Auto-refresh callback: trigger a status refresh
        repo_state:refresh_status()
      end,
    })
    -- Register watcher with repo_state so operations can pause it
    repo_state:set_watcher(self.watcher)
  end

  -- Clean up spinner and watcher when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      self.spinner:destroy()
      if self.watcher then
        self.watcher:stop()
        self.watcher = nil
      end
      status_buffers[key] = nil
    end,
  })

  status_buffers[key] = self
  return self
end

--- Open the status buffer in a window
---@param force_refresh? boolean If true, always trigger a refresh (e.g., when user explicitly runs :Gitlad)
function StatusBuffer:open(force_refresh)
  -- Check if buffer is already visible in ANY window (not just self.winnr)
  local existing_win = find_window_with_buffer(self.bufnr)
  if existing_win then
    -- Status buffer is already displayed, just focus it
    vim.api.nvim_set_current_win(existing_win)
    self.winnr = existing_win
    -- If force_refresh requested (e.g., explicit :Gitlad command), trigger refresh
    if force_refresh then
      self.repo_state:refresh_status(true)
    end
    return
  end

  -- Remember the current buffer before switching (for restoring on close)
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= self.bufnr then
    self.prev_bufnr = current_buf
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window-local options for clean status display
  utils.setup_view_window_options(self.winnr)

  -- Mark that cursor should be positioned at first item after status data arrives
  self._position_cursor_on_render = true

  -- Start spinner before initial render so we show "Refreshing..." not "Idle"
  self.spinner:start(function()
    self:_update_status_line()
  end)

  -- Initial render (will show spinner with loading background)
  self:render()

  -- Start file watcher if enabled
  if self.watcher then
    self.watcher:start()
  end

  -- Trigger refresh
  self.repo_state:refresh_status()
end

--- Close the status buffer
function StatusBuffer:close()
  -- Use current window if it's showing this buffer, otherwise use stored winnr
  local current_win = vim.api.nvim_get_current_win()
  local win_to_close

  if vim.api.nvim_win_get_buf(current_win) == self.bufnr then
    win_to_close = current_win
  elseif self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    win_to_close = self.winnr
  else
    self.winnr = nil
    return
  end

  -- Always switch to another buffer instead of closing the window
  -- This preserves the user's split layout
  local target_buf = self:_find_fallback_buffer()
  vim.api.nvim_win_set_buf(win_to_close, target_buf)

  -- Clear winnr if we closed the tracked window
  if win_to_close == self.winnr then
    self.winnr = nil
  end
end

--- Find a buffer to switch to when closing gitlad
--- Prefers the buffer that was active before gitlad opened
---@return number buffer number
function StatusBuffer:_find_fallback_buffer()
  -- Try the buffer we came from first
  if self.prev_bufnr and vim.api.nvim_buf_is_valid(self.prev_bufnr) then
    return self.prev_bufnr
  end

  -- Try the alternate buffer
  local alt = vim.fn.bufnr("#")
  if alt > 0 and alt ~= self.bufnr and vim.api.nvim_buf_is_valid(alt) then
    return alt
  end

  -- Try to find any other listed buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= self.bufnr and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      return buf
    end
  end

  -- Last resort: create a normal empty buffer
  -- Use listed scratch buffer for bufhidden='hide' and swapfile=false,
  -- but clear buftype so pickers treat it as a normal buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.bo[buf].buftype = ""
  return buf
end

--- Apply an expansion command and sync state to legacy fields
--- This is the bridge between the new Elm-style state and the existing code
---@param cmd ExpansionCommand
function StatusBuffer:apply_expansion_cmd(cmd)
  self.expansion = expansion.reducer.apply(self.expansion, cmd)
  self:_sync_expansion_to_legacy()
end

--- Sync expansion state to legacy fields for backward compatibility
--- This allows gradual migration of rendering code
function StatusBuffer:_sync_expansion_to_legacy()
  -- Sync visibility level
  self.visibility_level = self.expansion.visibility_level

  -- Sync collapsed sections
  self.collapsed_sections = {}
  for section_key, section_state in pairs(self.expansion.sections) do
    if section_state.collapsed then
      self.collapsed_sections[section_key] = true
    end
  end

  -- Sync expanded files (convert from new format to old format)
  self.expanded_files = {}
  for file_key, file_state in pairs(self.expansion.files) do
    if file_state.expanded == true then
      self.expanded_files[file_key] = true
    elseif file_state.expanded == "headers" then
      -- Headers mode: empty table or table with per-hunk states
      if file_state.hunks and next(file_state.hunks) then
        self.expanded_files[file_key] = vim.deepcopy(file_state.hunks)
      else
        self.expanded_files[file_key] = {}
      end
    else
      self.expanded_files[file_key] = false
    end
  end

  -- Sync expanded commits
  self.expanded_commits = vim.deepcopy(self.expansion.commits)

  -- Sync remembered file states (from file.remembered)
  self.remembered_file_states = {}
  for file_key, file_state in pairs(self.expansion.files) do
    if file_state.remembered then
      self.remembered_file_states[file_key] = vim.deepcopy(file_state.remembered)
    end
  end

  -- Sync remembered section states
  self.remembered_section_states = {}
  for section_key, section_state in pairs(self.expansion.sections) do
    if section_state.remembered_files then
      -- Convert to old format
      local files = {}
      for file_key, file_exp in pairs(section_state.remembered_files) do
        if file_exp.expanded == true then
          files[file_key] = true
        elseif file_exp.expanded == "headers" then
          files[file_key] = file_exp.hunks and vim.deepcopy(file_exp.hunks) or {}
        else
          files[file_key] = false
        end
      end
      if next(files) then
        self.remembered_section_states[section_key] = { files = files }
      end
    end
  end
end

--- Sync legacy fields back to expansion state
--- Used when legacy code directly modifies fields (until fully migrated)
function StatusBuffer:_sync_legacy_to_expansion()
  -- This allows legacy code to still work by syncing its changes back
  self.expansion.visibility_level = self.visibility_level

  -- Sync sections
  self.expansion.sections = {}
  for section_key, is_collapsed in pairs(self.collapsed_sections) do
    if is_collapsed then
      local remembered = nil
      if self.remembered_section_states[section_key] then
        -- Convert old format to new format
        remembered = {}
        for file_key, state in pairs(self.remembered_section_states[section_key].files or {}) do
          if state == true then
            remembered[file_key] = { expanded = true }
          elseif type(state) == "table" then
            remembered[file_key] = { expanded = "headers", hunks = vim.deepcopy(state) }
          else
            remembered[file_key] = { expanded = false }
          end
        end
      end
      self.expansion.sections[section_key] = {
        collapsed = true,
        remembered_files = remembered,
      }
    end
  end

  -- Sync files
  self.expansion.files = {}
  for file_key, state in pairs(self.expanded_files) do
    local remembered = self.remembered_file_states[file_key]
    if state == true then
      self.expansion.files[file_key] = {
        expanded = true,
        remembered = remembered and vim.deepcopy(remembered) or nil,
      }
    elseif type(state) == "table" then
      self.expansion.files[file_key] = {
        expanded = "headers",
        hunks = vim.deepcopy(state),
        remembered = remembered and vim.deepcopy(remembered) or nil,
      }
    elseif state == false then
      self.expansion.files[file_key] = {
        expanded = false,
        remembered = remembered and vim.deepcopy(remembered) or nil,
      }
    end
  end

  -- Sync commits
  self.expansion.commits = vim.deepcopy(self.expanded_commits)
end

--- Open status view for current repository
---@param repo_state_override? RepoState Optional repo state to use instead of detecting from cwd
---@param opts? { force_refresh?: boolean } Options
function M.open(repo_state_override, opts)
  opts = opts or {}
  local repo_state = repo_state_override or state.get()
  if not repo_state then
    vim.notify("[gitlad] Not in a git repository", vim.log.levels.WARN)
    return
  end

  local buf = get_or_create_buffer(repo_state)
  buf:open(opts.force_refresh)
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
  if repo_state then
    local key = repo_state.repo_root
    local buf = status_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end

  -- If no repo_state provided, return the first valid buffer (for testing)
  for _, buf in pairs(status_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

-- Export for testing
M._has_conflict_markers = status_staging._has_conflict_markers

return M
