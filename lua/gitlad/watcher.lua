---@mod gitlad.watcher File system watcher for git state changes
---@brief [[
--- Watches the .git/ directory, its subdirectories, the working tree, and
--- Neovim autocmds for changes and notifies when the view may be stale.
---
--- Three detection layers:
--- 1. fs_event watchers on .git/ and key subdirectories (refs/heads, refs/remotes, etc.)
--- 2. fs_event watcher on repo root (working tree) with gitignore cache filtering
--- 3. Neovim autocmds (BufWritePost, FocusGained) for reliable cross-platform detection
---
--- All layers feed into the same debounce timers via _handle_event().
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
---@field running boolean Whether watcher is active
---@field _fs_events uv_fs_event_t[] Array of fs_event handles for .git/ directories
---@field _worktree_event uv_fs_event_t|nil fs_event handle for working tree root
---@field _stale_indicator_debounced DebouncedFunction|nil Debounced callback for stale indicator
---@field _cooldown_duration number Cooldown duration in ms (configurable)
---@field _stale_indicator boolean Whether to show stale indicator
---@field _auto_refresh boolean Whether to auto-refresh
---@field _on_refresh function|nil Callback for auto_refresh
---@field _auto_refresh_debounced DebouncedFunction|nil Debounced callback for auto_refresh
---@field _repo_root string Path to repo root
---@field _watch_worktree boolean Whether to watch working tree
---@field _gitignore_cache table<string, boolean> Cache of top-level entries: true = ignored
---@field _augroup number|nil Autocmd group ID
local Watcher = {}
Watcher.__index = Watcher

--- Create a new watcher instance
---@param repo_state table RepoState instance
---@param opts? { cooldown_ms?: number, stale_indicator?: boolean, auto_refresh?: boolean, auto_refresh_debounce_ms?: number, on_refresh?: function, watch_worktree?: boolean } Optional configuration
---@return Watcher
function M.new(repo_state, opts)
  opts = opts or {}
  local self = setmetatable({}, Watcher)
  self.git_dir = repo_state.git_dir
  self.repo_state = repo_state
  self._fs_events = {}
  self._worktree_event = nil
  self.running = false
  self._cooldown_duration = opts.cooldown_ms or DEFAULT_COOLDOWN_MS
  self._stale_indicator = opts.stale_indicator ~= false -- default true
  self._auto_refresh = opts.auto_refresh or false -- default false
  self._on_refresh = opts.on_refresh
  self._repo_root = repo_state.repo_root
  self._watch_worktree = opts.watch_worktree ~= false -- default true
  self._gitignore_cache = {}
  self._augroup = nil

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

--- Handle an event from any source (fs_event, autocmd)
--- Checks running state and cooldown, then calls debounced callbacks.
function Watcher:_handle_event()
  if not self.running then
    return
  end
  -- Check cooldown - ignore events during/shortly after gitlad's own operations
  if self:is_in_cooldown() then
    return
  end
  -- Call enabled features
  -- When auto_refresh is active, skip the stale indicator to avoid a brief
  -- flash before the refresh clears it (the refresh handles everything)
  if self._auto_refresh and self._auto_refresh_debounced then
    self._auto_refresh_debounced:call()
  elseif self._stale_indicator and self._stale_indicator_debounced then
    self._stale_indicator_debounced:call()
  end
end

--- Create an fs_event watcher for a directory
--- Handles missing directories gracefully by skipping them.
---@param path string Directory path to watch
---@param callback fun(err: string|nil, filename: string, events: table) fs_event callback
---@return boolean success Whether the watcher was created
function Watcher:_watch_directory(path, callback)
  -- Skip if directory doesn't exist
  if vim.fn.isdirectory(path) ~= 1 then
    return false
  end

  local fs_event = vim.uv.new_fs_event()
  if not fs_event then
    return false
  end

  local ok = pcall(function()
    fs_event:start(path, {}, callback)
  end)

  if ok then
    table.insert(self._fs_events, fs_event)
    return true
  else
    pcall(function()
      fs_event:close()
    end)
    return false
  end
end

--- Create the callback for .git/ directory fs_event watchers
---@return fun(err: string|nil, filename: string, events: table)
function Watcher:_make_git_dir_callback()
  return function(watch_err, filename, _events)
    if watch_err then
      return
    end

    -- Filter out ignored files
    if should_ignore(filename) then
      return
    end

    -- Schedule the event handler
    vim.schedule(function()
      self:_handle_event()
    end)
  end
end

--- Build gitignore cache for top-level entries in the working tree
--- Uses `git check-ignore --stdin` to determine which entries are ignored.
--- Runs synchronously with vim.fn.system to avoid --literal-pathspecs
--- (which git check-ignore doesn't support).
---@param callback? fun() Called when cache is built
function Watcher:_build_gitignore_cache(callback)
  local repo_root = self._repo_root
  if not repo_root then
    if callback then
      callback()
    end
    return
  end

  -- List top-level entries
  local entries = vim.fn.readdir(repo_root)
  if not entries or #entries == 0 then
    if callback then
      callback()
    end
    return
  end

  -- Filter out .git (always skip, not a gitignore concern)
  local check_entries = {}
  for _, entry in ipairs(entries) do
    if entry ~= ".git" then
      table.insert(check_entries, entry)
    end
  end

  if #check_entries == 0 then
    if callback then
      callback()
    end
    return
  end

  -- Run git check-ignore --stdin synchronously
  -- Note: cannot use cli.run_async_with_stdin because build_command adds
  -- --literal-pathspecs which git check-ignore doesn't support
  local stdin_content = table.concat(check_entries, "\n") .. "\n"
  local output = vim.fn.system(
    "git -C " .. vim.fn.shellescape(repo_root) .. " check-ignore --stdin",
    stdin_content
  )

  local new_cache = {}
  if vim.v.shell_error == 0 or vim.v.shell_error == 1 then
    -- code 0 = some paths ignored, code 1 = no paths ignored
    for _, ignored_path in ipairs(vim.split(output, "\n", { trimempty = true })) do
      local trimmed = vim.trim(ignored_path)
      if trimmed ~= "" then
        new_cache[trimmed] = true
      end
    end
  end
  self._gitignore_cache = new_cache

  if callback then
    callback()
  end
end

--- Start worktree fs_event watcher on the repo root
function Watcher:_start_worktree_watcher()
  if not self._watch_worktree then
    return
  end

  local repo_root = self._repo_root
  if not repo_root or vim.fn.isdirectory(repo_root) ~= 1 then
    return
  end

  local fs_event = vim.uv.new_fs_event()
  if not fs_event then
    return
  end

  local ok = pcall(function()
    fs_event:start(repo_root, {}, function(watch_err, filename, _events)
      if watch_err then
        return
      end
      if not filename then
        return
      end

      -- Always skip .git directory changes (handled by git dir watchers)
      if filename == ".git" then
        return
      end

      -- Rebuild gitignore cache when .gitignore changes
      if filename == ".gitignore" then
        self:_build_gitignore_cache()
        -- Also trigger event since .gitignore change may affect tracked status
        vim.schedule(function()
          self:_handle_event()
        end)
        return
      end

      -- Skip entries that are cached as ignored
      if self._gitignore_cache[filename] then
        return
      end

      vim.schedule(function()
        self:_handle_event()
      end)
    end)
  end)

  if ok then
    self._worktree_event = fs_event
  else
    pcall(function()
      fs_event:close()
    end)
  end
end

--- Set up Neovim autocmds for cross-platform event detection
function Watcher:_setup_autocmds()
  self._augroup = vim.api.nvim_create_augroup("gitlad_watcher", { clear = true })

  -- BufWritePost: detect file saves within the repo
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = self._augroup,
    callback = function(ev)
      local file_path = ev.file
      if not file_path or file_path == "" then
        return
      end

      -- Resolve to absolute path
      file_path = vim.fn.fnamemodify(file_path, ":p")

      -- Check that the file is within the repo root
      if not vim.startswith(file_path, self._repo_root) then
        return
      end

      -- Skip files inside .git/
      local rel_path = file_path:sub(#self._repo_root + 1)
      if vim.startswith(rel_path, ".git/") or rel_path == ".git" then
        return
      end

      self:_handle_event()
    end,
  })

  -- FocusGained: detect external changes when Neovim regains focus
  vim.api.nvim_create_autocmd("FocusGained", {
    group = self._augroup,
    callback = function()
      self:_handle_event()
    end,
  })
end

--- Clean up autocmds
function Watcher:_cleanup_autocmds()
  if self._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self._augroup)
    self._augroup = nil
  end
end

--- Start watching the .git directory, subdirectories, working tree, and autocmds
--- This is idempotent - calling multiple times has no effect
function Watcher:start()
  if self.running then
    return
  end

  -- Verify git_dir exists
  if vim.fn.isdirectory(self.git_dir) ~= 1 then
    return
  end

  self.running = true

  -- Layer 1: Watch .git/ directory and key subdirectories
  local git_callback = self:_make_git_dir_callback()

  -- Watch .git/ itself
  self:_watch_directory(self.git_dir, git_callback)

  -- Watch subdirectories for branch/ref changes
  -- Missing dirs are handled gracefully by _watch_directory
  local git_dir = self.git_dir:gsub("/$", "") -- strip trailing slash for path joining
  self:_watch_directory(git_dir .. "/refs", git_callback)
  self:_watch_directory(git_dir .. "/refs/heads", git_callback)
  self:_watch_directory(git_dir .. "/refs/remotes", git_callback)
  self:_watch_directory(git_dir .. "/refs/tags", git_callback)

  -- Layer 2: Watch working tree with gitignore filtering
  if self._watch_worktree then
    self:_build_gitignore_cache()
    self:_start_worktree_watcher()
  end

  -- Layer 3: Neovim autocmds
  self:_setup_autocmds()

  -- If no fs_event handles were created (all dirs missing), stop
  if #self._fs_events == 0 and not self._watch_worktree then
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

  -- Stop and close all .git/ fs_event handles
  for _, fs_event in ipairs(self._fs_events) do
    pcall(function()
      fs_event:stop()
      fs_event:close()
    end)
  end
  self._fs_events = {}

  -- Stop and close worktree fs_event handle
  if self._worktree_event then
    pcall(function()
      self._worktree_event:stop()
      self._worktree_event:close()
    end)
    self._worktree_event = nil
  end

  -- Clean up autocmds
  self:_cleanup_autocmds()
end

--- Check if the watcher is currently running
---@return boolean
function Watcher:is_running()
  return self.running
end

-- Export the should_ignore function for testing
M._should_ignore = should_ignore

return M
