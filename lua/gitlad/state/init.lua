---@mod gitlad.state State management coordinator
---@brief [[
--- Central state management for gitlad.
--- Coordinates cache, async handlers, and loaders.
---@brief ]]

local M = {}

local cache = require("gitlad.state.cache")
local async = require("gitlad.state.async")
local git = require("gitlad.git")
local commands = require("gitlad.state.commands")
local reducer = require("gitlad.state.reducer")
local errors = require("gitlad.utils.errors")

---@class RepoState
---@field git_dir string Path to .git directory
---@field repo_root string Path to repository root
---@field status GitStatusResult|nil Current status
---@field refreshing boolean Whether a refresh is in progress
---@field status_handler AsyncHandler Handler for status requests
---@field cache Cache Cache instance
---@field listeners table<string, fun(state: RepoState)[]> Event listeners
local RepoState = {}
RepoState.__index = RepoState

-- Active repo states by git_dir
local repo_states = {}

--- Get or create a RepoState for a directory
---@param path? string Path inside repository (defaults to cwd)
---@return RepoState|nil
function M.get(path)
  local git_dir = git.repo_root(path)
  if not git_dir then
    return nil
  end

  -- Normalize to absolute path
  git_dir = vim.fn.fnamemodify(git_dir, ":p")

  if repo_states[git_dir] then
    return repo_states[git_dir]
  end

  -- Create new state
  local state = setmetatable({}, RepoState)
  state.repo_root = git_dir
  state.git_dir = git_dir .. ".git"
  state.status = nil
  state.refreshing = false
  state.cache = cache.new()
  state.listeners = {}

  -- Create status handler that notifies listeners on update
  state.status_handler = async.new(function(result)
    state.status = result
    state.refreshing = false
    state:_notify("status")
  end)

  repo_states[git_dir] = state
  return state
end

--- Register a listener for state changes
---@param event string Event name ("status", "branches", etc.)
---@param callback fun(state: RepoState)
function RepoState:on(event, callback)
  if not self.listeners[event] then
    self.listeners[event] = {}
  end
  table.insert(self.listeners[event], callback)
end

--- Remove a listener
---@param event string Event name
---@param callback fun(state: RepoState)
function RepoState:off(event, callback)
  local listeners = self.listeners[event]
  if not listeners then
    return
  end

  for i, cb in ipairs(listeners) do
    if cb == callback then
      table.remove(listeners, i)
      return
    end
  end
end

--- Notify listeners of an event
---@param event string Event name
function RepoState:_notify(event)
  local listeners = self.listeners[event]
  if not listeners then
    return
  end

  for _, callback in ipairs(listeners) do
    -- Wrap in pcall to prevent one listener from breaking others
    local ok, err = pcall(callback, self)
    if not ok then
      vim.notify(
        string.format("[gitlad] Listener error for '%s': %s", event, err),
        vim.log.levels.ERROR
      )
    end
  end
end

--- Apply a command to update status (Elm Architecture pattern)
---@param cmd StatusCommand
function RepoState:apply_command(cmd)
  if not self.status then
    return
  end
  self.status = reducer.apply(self.status, cmd)
  self.cache:invalidate("status")
  self:_notify("status")
end

--- Fetch extended status data (commit messages, unpushed/unpulled lists)
---@param result GitStatusResult The base status result to extend
---@param callback fun(result: GitStatusResult) Callback with extended result
function RepoState:_fetch_extended_status(result, callback)
  local opts = { cwd = self.repo_root }

  -- Counter to track parallel operations
  local pending = 0
  local function complete_one()
    pending = pending - 1
    if pending == 0 then
      callback(result)
    end
  end

  -- Helper to start a parallel operation
  local function start_op()
    pending = pending + 1
  end

  -- 1. Fetch HEAD commit message
  start_op()
  git.get_commit_subject("HEAD", opts, function(subject, _err)
    result.head_commit_msg = subject
    complete_one()
  end)

  -- 2. If upstream exists, fetch upstream commit message and commit lists
  if result.upstream then
    -- Fetch upstream commit message
    start_op()
    git.get_commit_subject(result.upstream, opts, function(subject, _err)
      result.merge_commit_msg = subject
      complete_one()
    end)

    -- Fetch unpulled commits (commits in upstream but not in HEAD)
    start_op()
    git.get_commits_between("HEAD", result.upstream, opts, function(commits, _err)
      result.unpulled_upstream = commits or {}
      complete_one()
    end)

    -- Fetch unpushed commits (commits in HEAD but not in upstream)
    start_op()
    git.get_commits_between(result.upstream, "HEAD", opts, function(commits, _err)
      result.unpushed_upstream = commits or {}
      complete_one()
    end)
  end

  -- 3. Determine push destination
  -- Push goes to <push-remote>/<branch-name> where push-remote is:
  --   1. branch.<name>.pushRemote (explicit config)
  --   2. remote.pushDefault (global default)
  --   3. branch.<name>.remote (derived from upstream, e.g., "origin/main" -> "origin")
  start_op()
  git.get_push_remote(result.branch, opts, function(explicit_push_remote, _err)
    local push_remote_name = explicit_push_remote

    -- If no explicit push remote, derive from upstream remote
    if (not push_remote_name or push_remote_name == "") and result.upstream then
      -- Extract remote name from upstream (e.g., "origin/main" -> "origin")
      push_remote_name = result.upstream:match("^([^/]+)/")
    end

    if not push_remote_name or push_remote_name == "" then
      -- No way to determine push remote
      complete_one()
      return
    end

    -- Construct push ref (e.g., "origin/feature-branch")
    local push_ref = push_remote_name .. "/" .. result.branch

    -- Only show Push line if it differs from upstream
    if result.upstream and push_ref == result.upstream then
      -- Same as upstream, no need to show separately
      complete_one()
      return
    end

    result.push_remote = push_ref

    -- Check if the push ref exists on remote (branch might not be pushed yet)
    start_op()
    git.get_commit_subject(push_ref, opts, function(subject, err)
      if not err and subject and subject ~= "" then
        result.push_commit_msg = subject

        -- Only fetch ahead/behind if the remote branch exists
        start_op()
        git.get_commits_between("HEAD", push_ref, opts, function(commits, _err)
          result.unpulled_push = commits or {}
          result.push_behind = #(commits or {})
          complete_one()
        end)

        start_op()
        git.get_commits_between(push_ref, "HEAD", opts, function(commits, _err)
          result.unpushed_push = commits or {}
          result.push_ahead = #(commits or {})
          complete_one()
        end)
      end
      complete_one()
    end)

    complete_one()
  end)
end

--- Refresh status (async with request ordering)
---@param force? boolean Force refresh even if cache valid
function RepoState:refresh_status(force)
  -- Check cache first
  if not force then
    local cached, valid = self.cache:get("status", self.git_dir)
    if valid and cached then
      self.status = cached
      self:_notify("status")
      return
    end
  end

  -- Set refreshing flag and notify UI
  self.refreshing = true
  self:_notify("status")

  -- Dispatch async refresh
  self.status_handler:dispatch(function(done)
    git.status({ cwd = self.repo_root }, function(result, err)
      if err then
        errors.notify("Status", err)
        done(nil)
        return
      end

      if not result then
        done(nil)
        return
      end

      -- Fetch extended status data (commit messages, unpushed/unpulled)
      self:_fetch_extended_status(result, function(extended_result)
        -- Cache the extended result
        self.cache:set("status", self.git_dir, extended_result)
        done(extended_result)
      end)
    end)
  end)
end

--- Get status synchronously (uses cache if valid)
---@param force? boolean Force refresh
---@return GitStatusResult|nil
function RepoState:get_status_sync(force)
  if not force then
    local cached, valid = self.cache:get("status", self.git_dir)
    if valid and cached then
      return cached
    end
  end

  local result, err = git.status_sync({ cwd = self.repo_root })
  if err then
    errors.notify("Status", err)
    return nil
  end

  if result then
    self.cache:set("status", self.git_dir, result)
    self.status = result
  end

  return result
end

--- Stage a file (optimistic update)
---@param path string File path to stage
---@param section "unstaged"|"untracked" Which section the file is in
---@param callback? fun(success: boolean)
function RepoState:stage(path, section, callback)
  git.stage(path, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Stage", err)
    else
      -- Optimistic update: apply command to state
      local cmd = commands.stage_file(path, section)
      self:apply_command(cmd)
    end
    if callback then
      callback(success)
    end
  end)
end

--- Unstage a file (optimistic update)
---@param path string File path to unstage
---@param callback? fun(success: boolean)
function RepoState:unstage(path, callback)
  git.unstage(path, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Unstage", err)
    else
      -- Optimistic update: apply command to state
      local cmd = commands.unstage_file(path)
      self:apply_command(cmd)
    end
    if callback then
      callback(success)
    end
  end)
end

--- Stage all files (optimistic update)
---@param callback? fun(success: boolean)
function RepoState:stage_all(callback)
  git.stage_all({ cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Stage all", err)
    else
      -- Optimistic update: apply command to state
      local cmd = commands.stage_all()
      self:apply_command(cmd)
    end
    if callback then
      callback(success)
    end
  end)
end

--- Unstage all files (optimistic update)
---@param callback? fun(success: boolean)
function RepoState:unstage_all(callback)
  git.unstage_all({ cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Unstage all", err)
    else
      -- Optimistic update: apply command to state
      local cmd = commands.unstage_all()
      self:apply_command(cmd)
    end
    if callback then
      callback(success)
    end
  end)
end

--- Discard changes to a file (optimistic update)
---@param path string File path to discard
---@param section "unstaged"|"untracked" Which section the file is in
---@param callback? fun(success: boolean)
function RepoState:discard(path, section, callback)
  if section == "untracked" then
    -- Delete the untracked file
    git.delete_untracked(path, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Delete", err)
      else
        -- Optimistic update: remove from state
        local cmd = commands.remove_file(path, section)
        self:apply_command(cmd)
      end
      if callback then
        callback(success)
      end
    end)
  else
    -- Discard changes with git checkout
    git.discard(path, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Discard", err)
      else
        -- Optimistic update: remove from state
        local cmd = commands.remove_file(path, section)
        self:apply_command(cmd)
      end
      if callback then
        callback(success)
      end
    end)
  end
end

--- Invalidate all caches and refresh
function RepoState:invalidate_and_refresh()
  self.cache:invalidate_all()
  self:refresh_status(true)
end

--- Clear all repo states (useful for testing)
function M.clear_all()
  repo_states = {}
end

return M
