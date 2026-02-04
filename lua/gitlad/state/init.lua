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
---@field stale boolean Whether the view is stale (git state changed externally)
---@field status_handler AsyncHandler Handler for status requests
---@field cache Cache Cache instance
---@field listeners table<string, fun(state: RepoState)[]> Event listeners
---@field watcher Watcher|nil File system watcher instance (if enabled)
---@field last_operation_time number Timestamp (ms) of last gitlad operation (for watcher cooldown)
local RepoState = {}
RepoState.__index = RepoState

-- Active repo states by git_dir
local repo_states = {}

--- Get or create a RepoState for a directory
---@param path? string Path inside repository (defaults to cwd)
---@return RepoState|nil
function M.get(path)
  local repo_root = git.repo_root(path)
  if not repo_root then
    return nil
  end

  -- Normalize to absolute path
  repo_root = vim.fn.fnamemodify(repo_root, ":p")

  if repo_states[repo_root] then
    return repo_states[repo_root]
  end

  -- Get the actual git directory (handles worktrees correctly)
  local git_dir = git.git_dir(path)
  if not git_dir then
    return nil
  end

  -- Create new state
  local state = setmetatable({}, RepoState)
  state.repo_root = repo_root
  state.git_dir = git_dir
  state.status = nil
  state.refreshing = false
  state.stale = false
  state.cache = cache.new()
  state.listeners = {}
  state.watcher = nil
  state.last_operation_time = 0

  -- Pending callback for refresh_status with callback
  state._pending_refresh_callback = nil

  -- Create status handler that notifies listeners on update
  state.status_handler = async.new(function(result)
    state.status = result
    state.refreshing = false
    state:_notify("status")

    -- Call and clear pending refresh callback
    if state._pending_refresh_callback then
      local cb = state._pending_refresh_callback
      state._pending_refresh_callback = nil
      cb()
    end
  end)

  repo_states[repo_root] = state
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

--- Mark the state as stale (called by file watcher when git state changes externally)
function RepoState:mark_stale()
  if self.stale then
    return -- Already stale
  end
  self.stale = true
  self:_notify("stale")
end

--- Clear the stale flag (called when refresh starts)
function RepoState:clear_stale()
  self.stale = false
end

--- Set the file watcher for this repo state
--- Called by StatusBuffer when watcher is enabled
---@param watcher Watcher
function RepoState:set_watcher(watcher)
  self.watcher = watcher
end

--- Apply a command to update status (Elm Architecture pattern)
---@param cmd StatusCommand
function RepoState:apply_command(cmd)
  if not self.status then
    return
  end
  -- Record operation time for watcher cooldown
  self.last_operation_time = vim.loop.now()
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

  -- 3. Fetch recent commits (shown when no unpushed commits exist, like magit)
  -- Always fetch these so they're available as a fallback
  start_op()
  git.log({ "-10" }, opts, function(commits, _err)
    result.recent_commits = commits or {}
    complete_one()
  end)

  -- 4. Fetch sequencer state (cherry-pick/revert/rebase in progress)
  start_op()
  git.get_sequencer_state(opts, function(seq_state)
    result.cherry_pick_in_progress = seq_state.cherry_pick_in_progress
    result.revert_in_progress = seq_state.revert_in_progress
    result.rebase_in_progress = seq_state.rebase_in_progress
    result.sequencer_head_oid = seq_state.sequencer_head_oid

    -- If there's a sequencer operation in progress, fetch the commit subject
    if seq_state.sequencer_head_oid then
      start_op()
      git.get_commit_subject(seq_state.sequencer_head_oid, opts, function(subject, _err)
        result.sequencer_head_subject = subject
        complete_one()
      end)
    end

    complete_one()
  end)

  -- 5. Fetch merge state (merge in progress)
  start_op()
  git.get_merge_state(opts, function(merge_state)
    result.merge_in_progress = merge_state.merge_in_progress
    result.merge_head_oid = merge_state.merge_head_oid

    -- If a merge is in progress, fetch the commit subject
    if merge_state.merge_head_oid then
      start_op()
      git.get_commit_subject(merge_state.merge_head_oid, opts, function(subject, _err)
        result.merge_head_subject = subject
        complete_one()
      end)
    end

    complete_one()
  end)

  -- 6. Fetch recent stashes
  start_op()
  git.stash_list(opts, function(stashes, _err)
    -- Limit to 10 stashes to avoid cluttering the status view
    result.stashes = stashes and vim.list_slice(stashes, 1, 10) or {}
    complete_one()
  end)

  -- 7. Fetch submodule status
  start_op()
  git.submodule_status(opts, function(submodules, _err)
    result.submodules = submodules or {}
    complete_one()
  end)

  -- 8. Fetch worktree list
  start_op()
  git.worktree_list(opts, function(worktrees, _err)
    result.worktrees = worktrees or {}
    complete_one()
  end)

  -- 9. Determine push destination
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
---@param callback? fun() Optional callback called when refresh completes
function RepoState:refresh_status(force, callback)
  -- Check cache first
  if not force then
    local cached, valid = self.cache:get("status", self.git_dir)
    if valid and cached then
      self.status = cached
      self:_notify("status")
      if callback then
        callback()
      end
      return
    end
  end

  -- Store callback to call when status is ready
  if callback then
    self._pending_refresh_callback = callback
  end

  -- Clear stale flag since we're refreshing
  self:clear_stale()

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
--- For directories (paths ending with /), triggers a refresh instead of optimistic update
--- since git expands directories to individual files when staging.
---@param path string File path to stage
---@param section "unstaged"|"untracked" Which section the file is in
---@param callback? fun(success: boolean)
function RepoState:stage(path, section, callback)
  -- Check if this is a directory (path ends with /)
  local is_directory = path:sub(-1) == "/"

  git.stage(path, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Stage", err)
      if callback then
        callback(success)
      end
    elseif is_directory then
      -- For directories, git expands to individual files when staging
      -- so we need to refresh to get the actual file list
      self:refresh_status(true, function()
        if callback then
          callback(success)
        end
      end)
    else
      -- Optimistic update for regular files
      local cmd = commands.stage_file(path, section)
      self:apply_command(cmd)
      if callback then
        callback(success)
      end
    end
  end)
end

--- Stage a file with intent-to-add (git add -N) for partial staging
---@param path string File path to stage with intent
---@param callback? fun(success: boolean)
function RepoState:stage_intent(path, callback)
  -- Check if this is a directory (path ends with /)
  local is_directory = path:sub(-1) == "/"

  git.stage_intent(path, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Stage (intent-to-add)", err)
      if callback then
        callback(success)
      end
    elseif is_directory then
      -- For directories, git expands to individual files when running add -N
      -- so we need to refresh to get the actual file list
      self:refresh_status(true, function()
        if callback then
          callback(success)
        end
      end)
    else
      -- Optimistic update for regular files
      local cmd = commands.stage_intent(path)
      self:apply_command(cmd)
      if callback then
        callback(success)
      end
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

--- Undo intent-to-add on a file (git reset), moving it back to untracked
---@param path string File path to undo intent-to-add
---@param callback? fun(success: boolean)
function RepoState:unstage_intent(path, callback)
  -- Uses same git command as unstage (git reset HEAD -- path)
  git.unstage(path, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Undo intent-to-add", err)
    else
      -- Optimistic update: apply command to state
      local cmd = commands.unstage_intent(path)
      self:apply_command(cmd)
    end
    if callback then
      callback(success)
    end
  end)
end

--- Stage multiple files in a single git command (optimistic update)
---@param files table[] Array of {path: string, section: string}
---@param callback? fun(success: boolean)
function RepoState:stage_files(files, callback)
  if #files == 0 then
    if callback then
      callback(true)
    end
    return
  end

  local paths = {}
  for _, file in ipairs(files) do
    table.insert(paths, file.path)
  end

  git.stage_files(paths, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Stage files", err)
    else
      -- Optimistic update: apply command for each file
      for _, file in ipairs(files) do
        local cmd = commands.stage_file(file.path, file.section)
        self:apply_command(cmd)
      end
    end
    if callback then
      callback(success)
    end
  end)
end

--- Unstage multiple files in a single git command (optimistic update)
---@param paths string[] File paths to unstage
---@param callback? fun(success: boolean)
function RepoState:unstage_files(paths, callback)
  if #paths == 0 then
    if callback then
      callback(true)
    end
    return
  end

  git.unstage_files(paths, { cwd = self.repo_root }, function(success, err)
    if not success then
      errors.notify("Unstage files", err)
    else
      -- Optimistic update: apply command for each file
      for _, path in ipairs(paths) do
        local cmd = commands.unstage_file(path)
        self:apply_command(cmd)
      end
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

--- Discard changes to multiple files (optimistic update)
--- Handles both untracked (delete) and unstaged (checkout) files in a single operation
---@param files table[] Array of {path: string, section: string}
---@param callback? fun(success: boolean)
function RepoState:discard_files(files, callback)
  if #files == 0 then
    if callback then
      callback(true)
    end
    return
  end

  -- Separate files by section
  local untracked_paths = {}
  local unstaged_paths = {}
  local untracked_files = {}
  local unstaged_files = {}

  for _, file in ipairs(files) do
    if file.section == "untracked" then
      table.insert(untracked_paths, file.path)
      table.insert(untracked_files, file)
    elseif file.section == "unstaged" then
      table.insert(unstaged_paths, file.path)
      table.insert(unstaged_files, file)
    end
  end

  -- Track completion of both operations
  local pending = 0
  local any_failed = false

  local function complete_one(success, files_to_update)
    if success then
      -- Optimistic update: apply command for each file
      for _, file in ipairs(files_to_update) do
        local cmd = commands.remove_file(file.path, file.section)
        self:apply_command(cmd)
      end
    else
      any_failed = true
    end

    pending = pending - 1
    if pending == 0 and callback then
      callback(not any_failed)
    end
  end

  -- Delete untracked files
  if #untracked_paths > 0 then
    pending = pending + 1
    git.delete_untracked_files(untracked_paths, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Delete files", err)
      end
      complete_one(success, untracked_files)
    end)
  end

  -- Discard unstaged changes
  if #unstaged_paths > 0 then
    pending = pending + 1
    git.discard_files(unstaged_paths, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Discard files", err)
      end
      complete_one(success, unstaged_files)
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

--- Mark operation time for watcher cooldown
--- Call this before running git commands to prevent false stale indicators
---@param cwd? string Working directory (used to find the repo state)
function M.mark_operation_time(cwd)
  -- Normalize and find the repo state for this cwd
  cwd = cwd or vim.fn.getcwd()
  local normalized_cwd = vim.fn.fnamemodify(cwd, ":p")

  -- Check if we have a repo state for this cwd
  for git_dir, state in pairs(repo_states) do
    -- Check if the cwd is within this repo's root
    if vim.startswith(normalized_cwd, state.repo_root) or normalized_cwd == state.repo_root then
      state.last_operation_time = vim.loop.now()
      return
    end
  end
end

return M
