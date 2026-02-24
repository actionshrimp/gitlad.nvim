---@mod gitlad.state State management coordinator
---@brief [[
--- Central state management for gitlad.
--- Coordinates cache, async handlers, and loaders.
---@brief ]]

local M = {}

local cache = require("gitlad.state.cache")
local async = require("gitlad.state.async")
local cli = require("gitlad.git.cli")
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
---@field _pending_optimistic_cmds StatusCommand[] Commands applied since last refresh dispatch
---@field pr_info ForgePullRequest|nil Cached PR info for current branch
---@field _pr_info_branch string|nil Branch name the pr_info was fetched for
---@field _pr_info_fetching boolean Whether a PR info fetch is in progress
---@field _pr_info_fetched_at number Timestamp (ms) of last successful PR info fetch
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

  -- Track optimistic commands for replay on refresh completion
  state._pending_optimistic_cmds = {}

  -- PR info cache (lazy-loaded for status header)
  state.pr_info = nil
  state._pr_info_branch = nil
  state._pr_info_fetching = false
  state._pr_info_fetched_at = 0

  -- Create status handler that notifies listeners on update
  state.status_handler = async.new(function(result)
    -- Replay any optimistic commands that happened during the refresh.
    -- Commands are idempotent: if the refresh already reflects the change,
    -- the replay is a no-op (source entry won't exist in expected section).
    local cmds = state._pending_optimistic_cmds
    state._pending_optimistic_cmds = {}
    for _, cmd in ipairs(cmds) do
      result = reducer.apply(result, cmd)
    end

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

--- Lazily fetch PR info for the current branch
--- Non-blocking: returns cached data, triggers async fetch if stale/missing
--- Calls self:_notify("status") when new data arrives to trigger re-render
---@param force? boolean Bypass TTL (used for manual refresh via gr)
function RepoState:fetch_pr_info(force)
  local cfg = require("gitlad.config").get()
  if not cfg.forge or not cfg.forge.show_pr_in_status then
    return
  end

  local branch = self.status and self.status.branch
  if not branch or branch == "" then
    return
  end

  -- If branch changed, invalidate cache
  if self._pr_info_branch ~= branch then
    self.pr_info = nil
    self._pr_info_branch = branch
    self._pr_info_fetching = false
    self._pr_info_fetched_at = 0
  end

  -- If not forced, check TTL before re-fetching
  if not force then
    local ttl_ms = (cfg.forge.pr_info_ttl or 30) * 1000
    local now = vim.uv.now()
    if self._pr_info_fetched_at > 0 and (now - self._pr_info_fetched_at) < ttl_ms then
      return
    end
  end

  -- If already fetching, skip
  if self._pr_info_fetching then
    return
  end

  self._pr_info_fetching = true

  -- Try to detect provider and fetch
  local forge = require("gitlad.forge")
  forge.detect(self.repo_root, function(provider, err)
    if err or not provider then
      self._pr_info_fetching = false
      return
    end

    local repo_slug = provider.owner .. "/" .. provider.repo
    local query = "repo:" .. repo_slug .. " is:pr is:open head:" .. branch
    provider:search_prs(query, 1, function(prs, search_err)
      vim.schedule(function()
        self._pr_info_fetching = false
        self._pr_info_fetched_at = vim.uv.now()

        if search_err or not prs then
          return
        end

        if #prs > 0 then
          local pr = prs[1]
          local changed = self.pr_info == nil
            or self.pr_info.number ~= pr.number
            or self.pr_info.state ~= pr.state
            or self.pr_info.review_decision ~= pr.review_decision
          self.pr_info = pr
          self._pr_info_branch = branch
          if changed then
            self:_notify("status")
          end
        else
          -- No matching open PR found — clear stale data (PR was merged/closed)
          if self.pr_info then
            self.pr_info = nil
            self:_notify("status")
          end
          self._pr_info_branch = branch
        end
      end)
    end)
  end)
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
  -- Track for replay on refresh completion (prevents stale refresh overwriting)
  table.insert(self._pending_optimistic_cmds, cmd)
  self:_notify("status")
end

--- Fetch upstream info (commit message, unpulled/unpushed lists)
---@param result GitStatusResult
---@param opts GitCommandOptions
---@param start_op fun()
---@param complete_one fun()
local function _fetch_upstream_info(result, opts, start_op, complete_one)
  if not result.upstream then
    return
  end

  start_op()
  git.get_commit_subject(result.upstream, opts, function(subject, _err)
    result.merge_commit_msg = subject
    complete_one()
  end)

  start_op()
  git.get_commits_between("HEAD", result.upstream, opts, function(commits, _err)
    result.unpulled_upstream = commits or {}
    complete_one()
  end)

  start_op()
  git.get_commits_between(result.upstream, "HEAD", opts, function(commits, _err)
    result.unpushed_upstream = commits or {}
    complete_one()
  end)
end

--- Fetch additional rebase info (onto commit, done commits, branch name)
---@param result GitStatusResult
---@param seq_state table Sequencer state
---@param opts GitCommandOptions
---@param start_op fun()
---@param complete_one fun()
local function _fetch_rebase_details(result, seq_state, opts, start_op, complete_one)
  if not (seq_state.rebase_in_progress and seq_state.rebase_onto) then
    return
  end

  -- Fetch onto commit info (abbreviated hash + subject)
  start_op()
  cli.run_async(
    { "log", "-1", "--format=%h%n%s", seq_state.rebase_onto },
    opts,
    function(log_result)
      if log_result.code == 0 then
        result.rebase_onto_abbrev = log_result.stdout[1]
        result.rebase_onto_subject = log_result.stdout[2]
      end
      complete_one()
    end
  )

  -- Fetch done commits (new commits created during rebase: onto..HEAD)
  start_op()
  cli.run_async(
    { "log", "--format=%H%x1e%h%x1e%s", "--reverse", seq_state.rebase_onto .. "..HEAD" },
    opts,
    function(log_result)
      if log_result.code == 0 then
        result.rebase_done_commits = {}
        for _, line in ipairs(log_result.stdout) do
          if line ~= "" then
            local parts = vim.split(line, "\30")
            table.insert(result.rebase_done_commits, {
              hash = parts[1],
              abbrev = parts[2],
              subject = parts[3] or "",
            })
          end
        end
      end
      complete_one()
    end
  )

  -- Try to resolve onto to a meaningful branch name
  start_op()
  cli.run_async(
    { "name-rev", "--name-only", "--no-undefined", seq_state.rebase_onto },
    opts,
    function(nr_result)
      if nr_result.code == 0 and nr_result.stdout[1] then
        local name = vim.trim(nr_result.stdout[1])
        -- Clean up name-rev output (e.g., "main~2" -> "main")
        local clean_name = name:match("^([^~^]+)")
        if clean_name and clean_name ~= "" then
          result.rebase_onto_name = clean_name
        end
      end
      complete_one()
    end
  )
end

--- Fetch sequencer state (cherry-pick/revert/rebase in progress)
---@param result GitStatusResult
---@param opts GitCommandOptions
---@param start_op fun()
---@param complete_one fun()
local function _fetch_sequencer_info(result, opts, start_op, complete_one)
  start_op()
  git.get_sequencer_state(opts, function(seq_state)
    result.cherry_pick_in_progress = seq_state.cherry_pick_in_progress
    result.revert_in_progress = seq_state.revert_in_progress
    result.rebase_in_progress = seq_state.rebase_in_progress
    result.am_in_progress = seq_state.am_in_progress
    result.am_current_patch = seq_state.am_current_patch
    result.am_last_patch = seq_state.am_last_patch
    result.sequencer_head_oid = seq_state.sequencer_head_oid
    result.rebase_head_name = seq_state.rebase_head_name
    result.rebase_onto = seq_state.rebase_onto
    result.rebase_stopped_sha = seq_state.rebase_stopped_sha
    result.rebase_todo = seq_state.rebase_todo
    result.rebase_done = seq_state.rebase_done

    if seq_state.sequencer_head_oid then
      start_op()
      git.get_commit_subject(seq_state.sequencer_head_oid, opts, function(subject, _err)
        result.sequencer_head_subject = subject
        complete_one()
      end)
    end

    _fetch_rebase_details(result, seq_state, opts, start_op, complete_one)

    complete_one()
  end)
end

--- Fetch merge state (merge in progress)
---@param result GitStatusResult
---@param opts GitCommandOptions
---@param start_op fun()
---@param complete_one fun()
local function _fetch_merge_info(result, opts, start_op, complete_one)
  start_op()
  git.get_merge_state(opts, function(merge_state)
    result.merge_in_progress = merge_state.merge_in_progress
    result.merge_head_oid = merge_state.merge_head_oid

    if merge_state.merge_head_oid then
      start_op()
      git.get_commit_subject(merge_state.merge_head_oid, opts, function(subject, _err)
        result.merge_head_subject = subject
        complete_one()
      end)
    end

    complete_one()
  end)
end

--- Determine push destination and fetch push commit info
---@param result GitStatusResult
---@param opts GitCommandOptions
---@param start_op fun()
---@param complete_one fun()
local function _fetch_push_info(result, opts, start_op, complete_one)
  start_op()
  git.get_push_remote(result.branch, opts, function(explicit_push_remote, _err)
    local push_remote_name = explicit_push_remote

    if (not push_remote_name or push_remote_name == "") and result.upstream then
      push_remote_name = result.upstream:match("^([^/]+)/")
    end

    if not push_remote_name or push_remote_name == "" then
      complete_one()
      return
    end

    local push_ref = push_remote_name .. "/" .. result.branch

    if result.upstream and push_ref == result.upstream then
      complete_one()
      return
    end

    result.push_remote = push_ref

    start_op()
    git.get_commit_subject(push_ref, opts, function(subject, err)
      if not err and subject and subject ~= "" then
        result.push_commit_msg = subject

        start_op()
        git.get_commits_between("HEAD", push_ref, opts, function(commits, _err2)
          result.unpulled_push = commits or {}
          result.push_behind = #(commits or {})
          complete_one()
        end)

        start_op()
        git.get_commits_between(push_ref, "HEAD", opts, function(commits, _err2)
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

--- Fetch extended status data (commit messages, unpushed/unpulled lists)
---@param result GitStatusResult The base status result to extend
---@param callback fun(result: GitStatusResult) Callback with extended result
function RepoState:_fetch_extended_status(result, callback)
  local opts = { cwd = self.repo_root, internal = true }

  local pending = 0
  local function complete_one()
    pending = pending - 1
    if pending == 0 then
      callback(result)
    end
  end
  local function start_op()
    pending = pending + 1
  end

  -- 1. HEAD commit message
  start_op()
  git.get_commit_subject("HEAD", opts, function(subject, _err)
    result.head_commit_msg = subject
    complete_one()
  end)

  -- 2. Upstream info
  _fetch_upstream_info(result, opts, start_op, complete_one)

  -- 3. Recent commits
  start_op()
  git.log({ "-10" }, opts, function(commits, _err)
    result.recent_commits = commits or {}
    complete_one()
  end)

  -- 4. Sequencer state
  _fetch_sequencer_info(result, opts, start_op, complete_one)

  -- 5. Merge state
  _fetch_merge_info(result, opts, start_op, complete_one)

  -- 6. Stashes
  start_op()
  git.stash_list(opts, function(stashes, _err)
    result.stashes = stashes and vim.list_slice(stashes, 1, 10) or {}
    complete_one()
  end)

  -- 7. Submodule status
  start_op()
  git.submodule_status(opts, function(submodules, _err)
    result.submodules = submodules or {}
    complete_one()
  end)

  -- 8. Worktree list
  start_op()
  git.worktree_list(opts, function(worktrees, _err)
    result.worktrees = worktrees or {}
    complete_one()
  end)

  -- 9. Push destination
  _fetch_push_info(result, opts, start_op, complete_one)
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

  -- New refresh will capture current git state; clear accumulated commands
  self._pending_optimistic_cmds = {}

  -- Set refreshing flag and notify UI
  self.refreshing = true
  self:_notify("status")

  -- Dispatch async refresh
  self.status_handler:dispatch(function(done)
    git.status({ cwd = self.repo_root, internal = true }, function(result, err)
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

  local result, err = git.status_sync({ cwd = self.repo_root, internal = true })
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
    -- Check if this is an intent-to-add file (.A) - discard should move back to untracked
    local is_intent_to_add = false
    if self.status and self.status.unstaged then
      for _, entry in ipairs(self.status.unstaged) do
        if entry.path == path and entry.worktree_status == "A" and entry.index_status == "." then
          is_intent_to_add = true
          break
        end
      end
    end

    if is_intent_to_add then
      -- Intent-to-add file: unstage it (move back to untracked)
      git.unstage(path, { cwd = self.repo_root }, function(success, err)
        if not success then
          errors.notify("Discard (intent-to-add)", err)
        else
          local cmd = commands.unstage_intent(path)
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

  -- Separate files by section, with a third bucket for intent-to-add files
  local untracked_paths = {}
  local unstaged_paths = {}
  local intent_paths = {}
  local untracked_files = {}
  local unstaged_files = {}
  local intent_files = {}

  for _, file in ipairs(files) do
    if file.section == "untracked" then
      table.insert(untracked_paths, file.path)
      table.insert(untracked_files, file)
    elseif file.section == "unstaged" then
      -- Check if this is an intent-to-add (.A) file
      local is_intent = false
      if self.status and self.status.unstaged then
        for _, entry in ipairs(self.status.unstaged) do
          if
            entry.path == file.path
            and entry.worktree_status == "A"
            and entry.index_status == "."
          then
            is_intent = true
            break
          end
        end
      end
      if is_intent then
        table.insert(intent_paths, file.path)
        table.insert(intent_files, file)
      else
        table.insert(unstaged_paths, file.path)
        table.insert(unstaged_files, file)
      end
    end
  end

  -- Track completion of all operations
  local pending = 0
  local any_failed = false

  -- Helper to run intent-to-add unstage (serialized after index-modifying operations)
  local function run_intent_unstage()
    if #intent_paths == 0 then
      if pending == 0 and callback then
        callback(not any_failed)
      end
      return
    end

    pending = pending + 1
    git.unstage_files(intent_paths, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Discard intent-to-add files", err)
        any_failed = true
      else
        -- Optimistic update: apply unstage_intent for each file
        for _, file in ipairs(intent_files) do
          local cmd = commands.unstage_intent(file.path)
          self:apply_command(cmd)
        end
      end
      pending = pending - 1
      if pending == 0 and callback then
        callback(not any_failed)
      end
    end)
  end

  -- Count index-modifying git operations (discard uses checkout which modifies index)
  local index_ops_pending = 0
  if #unstaged_paths > 0 then
    index_ops_pending = index_ops_pending + 1
  end

  local function complete_index_op(success, files_to_update)
    if success then
      for _, file in ipairs(files_to_update) do
        local cmd = commands.remove_file(file.path, file.section)
        self:apply_command(cmd)
      end
    else
      any_failed = true
    end
    pending = pending - 1
    index_ops_pending = index_ops_pending - 1
    -- Once all index-modifying ops are done, run intent unstage
    if index_ops_pending == 0 then
      run_intent_unstage()
    elseif pending == 0 and callback then
      callback(not any_failed)
    end
  end

  -- Delete untracked files (does NOT modify index, can run in parallel)
  if #untracked_paths > 0 then
    pending = pending + 1
    git.delete_untracked_files(untracked_paths, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Delete files", err)
      end
      -- Untracked deletes don't modify index, handle separately
      if success then
        for _, file in ipairs(untracked_files) do
          local cmd = commands.remove_file(file.path, file.section)
          self:apply_command(cmd)
        end
      else
        any_failed = true
      end
      pending = pending - 1
      if pending == 0 and #intent_paths == 0 and callback then
        callback(not any_failed)
      end
    end)
  end

  -- Discard unstaged changes (modifies index, must complete before intent unstage)
  if #unstaged_paths > 0 then
    pending = pending + 1
    git.discard_files(unstaged_paths, { cwd = self.repo_root }, function(success, err)
      if not success then
        errors.notify("Discard files", err)
      end
      complete_index_op(success, unstaged_files)
    end)
  end

  -- If no index-modifying ops, run intent unstage immediately
  if index_ops_pending == 0 then
    run_intent_unstage()
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
