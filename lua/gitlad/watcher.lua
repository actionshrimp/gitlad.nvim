---@mod gitlad.watcher File system watcher for git state changes
---@brief [[
--- Watches the .git/ directory for changes and notifies when the view may be stale.
--- This is an optional feature that must be explicitly enabled via config.
---
--- Uses a cooldown mechanism to avoid false positives from gitlad's own operations:
--- when gitlad performs a git operation, it pauses the watcher briefly so the
--- resulting file changes don't trigger a stale indicator.
---@brief ]]

local M = {}

local async = require("gitlad.state.async")

-- Debounce delay in milliseconds for indicator mode (200ms to coalesce rapid events)
local INDICATOR_DEBOUNCE_MS = 200

-- Default debounce for auto_refresh mode (500ms to avoid too many refreshes)
local DEFAULT_AUTO_REFRESH_DEBOUNCE_MS = 500

-- Default cooldown duration in milliseconds (time to ignore events after gitlad operation)
local DEFAULT_COOLDOWN_MS = 1000

-- Files to ignore (truly transient files that never indicate meaningful state changes)
local IGNORED_FILES = {
  ORIG_HEAD = true, -- Backup reference
  FETCH_HEAD = true, -- Transient fetch result
  COMMIT_EDITMSG = true, -- Commit message buffer
}

--- Check if a filename should be ignored
---@param filename string
---@return boolean
local function should_ignore(filename)
  if not filename then
    return true
  end

  -- Check exact match in ignored set
  if IGNORED_FILES[filename] then
    return true
  end

  -- Ignore lock files
  if filename:match("%.lock$") then
    return true
  end

  -- Ignore backup files
  if filename:match("~$") then
    return true
  end

  -- Ignore temp files (4-digit pattern used by git internals)
  if filename:match("^%d%d%d%d$") then
    return true
  end

  return false
end

---@class Watcher
---@field git_dir string Path to .git directory
---@field repo_state table Reference to RepoState
---@field fs_event uv_fs_event_t|nil File system event handle
---@field running boolean Whether watcher is active
---@field _stale_indicator_debounced DebouncedFunction|nil Debounced callback for stale indicator
---@field _cooldown_duration number Cooldown duration in ms (configurable)
---@field _stale_indicator boolean Whether to show stale indicator
---@field _auto_refresh boolean Whether to auto-refresh
---@field _on_refresh function|nil Callback for auto_refresh
---@field _auto_refresh_debounced DebouncedFunction|nil Debounced callback for auto_refresh
local Watcher = {}
Watcher.__index = Watcher

--- Create a new watcher instance
---@param repo_state table RepoState instance
---@param opts? { cooldown_ms?: number, stale_indicator?: boolean, auto_refresh?: boolean, auto_refresh_debounce_ms?: number, on_refresh?: function } Optional configuration
---@return Watcher
function M.new(repo_state, opts)
  opts = opts or {}
  local self = setmetatable({}, Watcher)
  self.git_dir = repo_state.git_dir
  self.repo_state = repo_state
  self.fs_event = nil
  self.running = false
  self._cooldown_duration = opts.cooldown_ms or DEFAULT_COOLDOWN_MS
  self._stale_indicator = opts.stale_indicator ~= false -- default true
  self._auto_refresh = opts.auto_refresh or false -- default false
  self._on_refresh = opts.on_refresh

  -- Create debounced callback for stale indicator (marks state as stale)
  if self._stale_indicator then
    self._stale_indicator_debounced = async.debounce(function()
      if self.repo_state and self.repo_state.mark_stale then
        self.repo_state:mark_stale()
      end
    end, INDICATOR_DEBOUNCE_MS)
  end

  -- Create debounced callback for auto_refresh
  if self._auto_refresh and self._on_refresh then
    local debounce_ms = opts.auto_refresh_debounce_ms or DEFAULT_AUTO_REFRESH_DEBOUNCE_MS
    self._auto_refresh_debounced = async.debounce(function()
      if self._on_refresh then
        self._on_refresh()
      end
    end, debounce_ms)
  end

  return self
end

--- Check if we're within the cooldown period after a gitlad operation
--- Uses repo_state.last_operation_time to determine if events should be ignored
---@return boolean
function Watcher:is_in_cooldown()
  if not self.repo_state then
    return false
  end
  local last_op = self.repo_state.last_operation_time or 0
  local now = vim.loop.now()
  return (now - last_op) < self._cooldown_duration
end

--- Start watching the .git directory
--- This is idempotent - calling multiple times has no effect
function Watcher:start()
  if self.running then
    return
  end

  -- Verify git_dir exists
  if vim.fn.isdirectory(self.git_dir) ~= 1 then
    return
  end

  local fs_event = vim.uv.new_fs_event()
  if not fs_event then
    return
  end

  self.fs_event = fs_event
  self.running = true

  -- Start watching the .git directory
  local ok, err = pcall(function()
    fs_event:start(self.git_dir, {}, function(watch_err, filename, _events)
      if watch_err then
        return
      end

      -- Filter out ignored files
      if should_ignore(filename) then
        return
      end

      -- Schedule the debounced callback
      vim.schedule(function()
        if self.running then
          -- Check cooldown - ignore events during/shortly after gitlad's own operations
          if self:is_in_cooldown() then
            return
          end
          -- Call enabled features (both can be active simultaneously)
          if self._stale_indicator and self._stale_indicator_debounced then
            self._stale_indicator_debounced:call()
          end
          if self._auto_refresh and self._auto_refresh_debounced then
            self._auto_refresh_debounced:call()
          end
        end
      end)
    end)
  end)

  if not ok then
    self:stop()
  end
end

--- Stop watching
--- This is idempotent - calling multiple times has no effect
function Watcher:stop()
  if not self.running then
    return
  end

  self.running = false

  -- Cancel any pending debounced calls
  if self._stale_indicator_debounced then
    self._stale_indicator_debounced:cancel()
  end
  if self._auto_refresh_debounced then
    self._auto_refresh_debounced:cancel()
  end

  -- Stop and close the fs_event handle
  if self.fs_event then
    pcall(function()
      self.fs_event:stop()
      self.fs_event:close()
    end)
    self.fs_event = nil
  end
end

--- Check if the watcher is currently running
---@return boolean
function Watcher:is_running()
  return self.running
end

-- Export the should_ignore function for testing
M._should_ignore = should_ignore

return M
