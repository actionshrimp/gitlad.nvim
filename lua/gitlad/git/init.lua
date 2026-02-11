---@mod gitlad.git Git operations interface
---@brief [[
--- High-level git operations built on the CLI wrapper.
--- This module re-exports operations from submodules:
--- - git_branches: branch operations (checkout, create, delete, rename)
--- - git_commits: commit operations (commit, amend, log, cherry-pick, revert)
--- - git_rebase: rebase operations (rebase, reset)
--- - git_stash: stash operations (push, pop, apply, drop)
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")
local errors = require("gitlad.utils.errors")

-- Re-export from submodules
local git_branches = require("gitlad.git.git_branches")
local git_commits = require("gitlad.git.git_commits")
local git_rebase = require("gitlad.git.git_rebase")
local git_stash = require("gitlad.git.git_stash")
local git_reflog = require("gitlad.git.git_reflog")
local git_remotes = require("gitlad.git.git_remotes")
local git_worktree = require("gitlad.git.git_worktree")
local git_patch = require("gitlad.git.git_patch")

-- Branch operations
M.branches = git_branches.branches
M.checkout = git_branches.checkout
M.checkout_new_branch = git_branches.checkout_new_branch
M.create_branch = git_branches.create_branch
M.delete_branch = git_branches.delete_branch
M.rename_branch = git_branches.rename_branch
M.remote_branches = git_branches.remote_branches
M.set_upstream = git_branches.set_upstream
M.get_upstream = git_branches.get_upstream
M.get_push_remote = git_branches.get_push_remote
M.get_default_remote = git_branches.get_default_remote
M.set_push_remote = git_branches.set_push_remote
M.delete_remote_branch = git_branches.delete_remote_branch

-- Commit operations
M.commit = git_commits.commit
M.commit_amend_no_edit = git_commits.commit_amend_no_edit
M.commit_fixup = git_commits.commit_fixup
M.commit_streaming = git_commits.commit_streaming
M.commit_amend_no_edit_streaming = git_commits.commit_amend_no_edit_streaming
M.get_commit_subject = git_commits.get_commit_subject
M.get_commits_between = git_commits.get_commits_between
M.log = git_commits.log
M.log_detailed = git_commits.log_detailed
M.show_commit = git_commits.show_commit
M.cherry_pick = git_commits.cherry_pick
M.cherry_pick_continue = git_commits.cherry_pick_continue
M.cherry_pick_abort = git_commits.cherry_pick_abort
M.cherry_pick_skip = git_commits.cherry_pick_skip
M.revert = git_commits.revert
M.revert_continue = git_commits.revert_continue
M.revert_abort = git_commits.revert_abort
M.revert_skip = git_commits.revert_skip
M.cherry = git_commits.cherry
M.rev_list_count = git_commits.rev_list_count

-- Rebase operations
M.rebase = git_rebase.rebase
M.rebase_continue = git_rebase.rebase_continue
M.rebase_abort = git_rebase.rebase_abort
M.rebase_skip = git_rebase.rebase_skip
M.rebase_in_progress = git_rebase.rebase_in_progress
M.rebase_instantly = git_rebase.rebase_instantly
M.reset = git_rebase.reset
M.reset_keep = git_rebase.reset_keep
M.reset_index = git_rebase.reset_index
M.reset_worktree = git_rebase.reset_worktree

-- Stash operations
M.stash_push = git_stash.stash_push
M.stash_pop = git_stash.stash_pop
M.stash_apply = git_stash.stash_apply
M.stash_drop = git_stash.stash_drop
M.stash_list = git_stash.stash_list

-- Worktree operations
M.worktree_list = git_worktree.worktree_list
M.worktree_add = git_worktree.worktree_add
M.worktree_add_new_branch = git_worktree.worktree_add_new_branch
M.worktree_remove = git_worktree.worktree_remove
M.worktree_move = git_worktree.worktree_move
M.worktree_lock = git_worktree.worktree_lock
M.worktree_unlock = git_worktree.worktree_unlock
M.worktree_prune = git_worktree.worktree_prune

-- Reflog operations
M.reflog = git_reflog.reflog

-- Patch operations
M.format_patch = git_patch.format_patch
M.apply_patch_file = git_patch.apply_patch_file
M.am = git_patch.am
M.am_continue = git_patch.am_continue
M.am_skip = git_patch.am_skip
M.am_abort = git_patch.am_abort
M.get_am_state = git_patch.get_am_state

-- Remote operations
M.remote_add = git_remotes.remote_add
M.remote_rename = git_remotes.remote_rename
M.remote_remove = git_remotes.remote_remove
M.remote_prune = git_remotes.remote_prune
M.remote_set_url = git_remotes.remote_set_url
M.remote_get_url = git_remotes.remote_get_url

-- =============================================================================
-- Core operations (kept in this file)
-- =============================================================================

--- Get repository status
---@param opts? GitCommandOptions
---@param callback fun(result: GitStatusResult|nil, err: string|nil)
function M.status(opts, callback)
  cli.run_async(
    { "status", "--porcelain=v2", "--branch", "--find-renames", "--untracked-files=normal" },
    opts,
    function(result)
      if result.code ~= 0 then
        callback(nil, table.concat(result.stderr, "\n"))
        return
      end
      callback(parse.parse_status(result.stdout), nil)
    end
  )
end

--- Get repository status synchronously
---@param opts? GitCommandOptions
---@return GitStatusResult|nil, string|nil
function M.status_sync(opts)
  local result = cli.run_sync(
    { "status", "--porcelain=v2", "--branch", "--find-renames", "--untracked-files=normal" },
    opts
  )
  if result.code ~= 0 then
    return nil, table.concat(result.stderr, "\n")
  end
  return parse.parse_status(result.stdout), nil
end

--- Stage a file
---@param path string File path to stage
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stage(path, opts, callback)
  cli.run_async({ "add", "--", path }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Stage multiple files in a single git command
---@param paths string[] File paths to stage
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stage_files(paths, opts, callback)
  if #paths == 0 then
    callback(true, nil)
    return
  end
  local args = { "add", "--" }
  vim.list_extend(args, paths)
  cli.run_async(args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Stage a file with intent-to-add (git add -N)
--- This marks the file as staged without including any content,
--- allowing subsequent partial staging of the file's content.
---@param path string File path to stage with intent
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stage_intent(path, opts, callback)
  cli.run_async({ "add", "-N", "--", path }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Unstage a file
---@param path string File path to unstage
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.unstage(path, opts, callback)
  cli.run_async({ "reset", "HEAD", "--", path }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Unstage multiple files in a single git command
---@param paths string[] File paths to unstage
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.unstage_files(paths, opts, callback)
  if #paths == 0 then
    callback(true, nil)
    return
  end
  local args = { "reset", "HEAD", "--" }
  vim.list_extend(args, paths)
  cli.run_async(args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get diff for a file
---@param path string File path
---@param staged boolean Whether to get staged diff
---@param opts? GitCommandOptions
---@param callback fun(lines: string[]|nil, err: string|nil)
---@param orig_path? string Original path (for renames, enables -M detection)
function M.diff(path, staged, opts, callback, orig_path)
  local args = { "diff" }
  if orig_path then
    table.insert(args, "-M")
  end
  if staged then
    table.insert(args, "--cached")
  end
  table.insert(args, "--")
  if orig_path then
    table.insert(args, orig_path)
  end
  table.insert(args, path)

  cli.run_async(args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(result.stdout, nil)
  end)
end

--- Get diff for an untracked file (shows full file as additions)
---@param path string File path (relative to repo root)
---@param opts? GitCommandOptions
---@param callback fun(lines: string[]|nil, err: string|nil)
function M.diff_untracked(path, opts, callback)
  -- Use --no-index to diff against /dev/null, producing proper diff output
  local args = { "diff", "--no-index", "--", "/dev/null", path }

  cli.run_async(args, opts, function(result)
    -- --no-index returns exit code 1 when files differ (which they always will)
    -- So we check for actual errors differently
    if result.code ~= 0 and result.code ~= 1 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(result.stdout, nil)
  end)
end

--- Stage all files
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stage_all(opts, callback)
  cli.run_async({ "add", "-A" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Unstage all files
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.unstage_all(opts, callback)
  cli.run_async({ "reset", "HEAD" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Discard changes to a file (checkout from HEAD)
---@param path string File path to discard
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.discard(path, opts, callback)
  cli.run_async({ "checkout", "HEAD", "--", path }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Delete an untracked file or directory
---@param path string File path to delete (trailing "/" indicates directory)
---@param opts? GitCommandOptions Options (cwd is the repository root)
---@param callback fun(success: boolean, err: string|nil)
function M.delete_untracked(path, opts, callback)
  local repo_root = opts and opts.cwd or vim.fn.getcwd()
  if path:sub(-1) == "/" then
    -- Directory: use vim.fn.delete with 'rf' for recursive removal
    local dir_path = repo_root .. "/" .. path:sub(1, -2)
    local ret = vim.fn.delete(dir_path, "rf")
    if ret == 0 then
      callback(true, nil)
    else
      callback(false, "Failed to delete directory: " .. path)
    end
  else
    local full_path = repo_root .. "/" .. path
    local ok, err = os.remove(full_path)
    if ok then
      callback(true, nil)
    else
      callback(false, err or "Failed to delete file")
    end
  end
end

--- Discard changes to multiple files in a single git command (checkout from HEAD)
---@param paths string[] File paths to discard
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.discard_files(paths, opts, callback)
  if #paths == 0 then
    callback(true, nil)
    return
  end
  local args = { "checkout", "HEAD", "--" }
  vim.list_extend(args, paths)
  cli.run_async(args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Delete multiple untracked files
---@param paths string[] File paths to delete
---@param opts? GitCommandOptions Options (cwd is the repository root)
---@param callback fun(success: boolean, err: string|nil)
function M.delete_untracked_files(paths, opts, callback)
  if #paths == 0 then
    callback(true, nil)
    return
  end

  local repo_root = opts and opts.cwd or vim.fn.getcwd()
  local failed = {}

  for _, path in ipairs(paths) do
    if path:sub(-1) == "/" then
      -- Directory: use vim.fn.delete with 'rf' for recursive removal
      local dir_path = repo_root .. "/" .. path:sub(1, -2)
      local ret = vim.fn.delete(dir_path, "rf")
      if ret ~= 0 then
        table.insert(failed, path .. ": Failed to delete directory")
      end
    else
      local full_path = repo_root .. "/" .. path
      local ok, err = os.remove(full_path)
      if not ok then
        table.insert(failed, path .. ": " .. (err or "unknown error"))
      end
    end
  end

  if #failed > 0 then
    callback(false, "Failed to delete: " .. table.concat(failed, ", "))
  else
    callback(true, nil)
  end
end

--- Apply a patch via stdin
---@param patch_lines string[] The patch content lines
---@param reverse boolean Whether to reverse the patch (for unstaging/discarding)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
---@param cached? boolean Whether to apply to index (default true) vs worktree (false)
function M.apply_patch(patch_lines, reverse, opts, callback, cached)
  local args = { "apply" }
  if cached == nil or cached then
    table.insert(args, "--cached")
  end
  if reverse then
    table.insert(args, "-R")
  end

  cli.run_async_with_stdin(args, patch_lines, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Check if path is inside a git repository
---@param path? string Path to check (defaults to cwd)
---@return boolean
function M.is_repo(path)
  return cli.find_git_dir(path) ~= nil
end

--- Get repository root
---@param path? string Path to check (defaults to cwd)
---@return string|nil
function M.repo_root(path)
  return cli.find_repo_root(path)
end

--- Get git directory (handles worktrees correctly)
--- For a regular repo, returns /path/to/repo/.git/
--- For a worktree, returns /path/to/main-repo/.git/worktrees/worktree-name/
---@param path? string Path to check (defaults to cwd)
---@return string|nil
function M.git_dir(path)
  return cli.find_git_dir(path)
end

--- Get list of remotes
---@param opts? GitCommandOptions
---@param callback fun(remotes: GitRemote[]|nil, err: string|nil)
function M.remotes(opts, callback)
  cli.run_async({ "remote", "-v" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_remotes(result.stdout), nil)
  end)
end

--- Push to a remote
---@param args string[] Push arguments (e.g., { "origin", "main" } or { "--force-with-lease" })
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.push(args, opts, callback)
  local push_args = { "push" }
  vim.list_extend(push_args, args)

  cli.run_async(push_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    -- Git push outputs progress to stderr even on success
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Fetch from a remote
---@param args string[] Fetch arguments (e.g., { "origin" } or { "--prune", "--tags" })
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.fetch(args, opts, callback)
  local fetch_args = { "fetch" }
  vim.list_extend(fetch_args, args)

  cli.run_async(fetch_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    -- Git fetch outputs progress to stderr even on success
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Pull from a remote
---@param args string[] Pull arguments (e.g., { "origin", "main" } or { "--rebase" })
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.pull(args, opts, callback)
  local pull_args = { "pull" }
  vim.list_extend(pull_args, args)

  cli.run_async(pull_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    -- Git pull outputs progress to stderr even on success
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Get list of remote names
---@param opts? GitCommandOptions
---@param callback fun(remotes: string[]|nil, err: string|nil)
function M.remote_names(opts, callback)
  cli.run_async({ "remote" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(result.stdout, nil)
  end)
end

--- Get list of remote names (synchronous)
---@param opts? GitCommandOptions
---@return string[] remotes List of remote names
function M.remote_names_sync(opts)
  local result = cli.run_sync({ "remote" }, opts)
  if result.code ~= 0 then
    return {}
  end
  -- Filter out empty strings
  local remotes = {}
  for _, name in ipairs(result.stdout) do
    if name and name ~= "" then
      table.insert(remotes, name)
    end
  end
  return remotes
end

---@class SequencerState
---@field cherry_pick_in_progress boolean
---@field revert_in_progress boolean
---@field rebase_in_progress boolean
---@field am_in_progress boolean
---@field am_current_patch string|nil Current patch number during git am
---@field am_last_patch string|nil Total patch count during git am
---@field sequencer_head_oid string|nil The commit being cherry-picked/reverted

--- Check if a cherry-pick, revert, rebase, or am is in progress
---@param opts? GitCommandOptions
---@param callback fun(state: SequencerState)
function M.get_sequencer_state(opts, callback)
  local git_dir = cli.find_git_dir(opts and opts.cwd or nil)
  if not git_dir then
    callback({
      cherry_pick_in_progress = false,
      revert_in_progress = false,
      rebase_in_progress = false,
      am_in_progress = false,
      am_current_patch = nil,
      am_last_patch = nil,
      sequencer_head_oid = nil,
    })
    return
  end

  local state = {
    cherry_pick_in_progress = false,
    revert_in_progress = false,
    rebase_in_progress = false,
    am_in_progress = false,
    am_current_patch = nil,
    am_last_patch = nil,
    sequencer_head_oid = nil,
  }

  -- Check for CHERRY_PICK_HEAD
  local cherry_pick_head = git_dir .. "/CHERRY_PICK_HEAD"
  if vim.fn.filereadable(cherry_pick_head) == 1 then
    state.cherry_pick_in_progress = true
    local content = vim.fn.readfile(cherry_pick_head)
    if content[1] then
      state.sequencer_head_oid = content[1]:match("^(%x+)")
    end
    callback(state)
    return
  end

  -- Check for REVERT_HEAD
  local revert_head = git_dir .. "/REVERT_HEAD"
  if vim.fn.filereadable(revert_head) == 1 then
    state.revert_in_progress = true
    local content = vim.fn.readfile(revert_head)
    if content[1] then
      state.sequencer_head_oid = content[1]:match("^(%x+)")
    end
    callback(state)
    return
  end

  -- Check for rebase-merge (interactive rebase)
  local rebase_merge = git_dir .. "/rebase-merge"
  if vim.fn.isdirectory(rebase_merge) == 1 then
    state.rebase_in_progress = true
    callback(state)
    return
  end

  -- Check for rebase-apply (rebase or am)
  -- Distinguish: rebase-apply/applying exists during git am,
  -- rebase-apply/rebasing exists during git rebase
  local rebase_apply = git_dir .. "/rebase-apply"
  if vim.fn.isdirectory(rebase_apply) == 1 then
    local applying = rebase_apply .. "/applying"
    if vim.fn.filereadable(applying) == 1 then
      -- git am in progress
      state.am_in_progress = true

      -- Read current patch number
      local next_file = rebase_apply .. "/next"
      if vim.fn.filereadable(next_file) == 1 then
        local content = vim.fn.readfile(next_file)
        if content[1] then
          state.am_current_patch = vim.trim(content[1])
        end
      end

      -- Read total patch count
      local last_file = rebase_apply .. "/last"
      if vim.fn.filereadable(last_file) == 1 then
        local content = vim.fn.readfile(last_file)
        if content[1] then
          state.am_last_patch = vim.trim(content[1])
        end
      end
    else
      -- rebase in progress (non-interactive)
      state.rebase_in_progress = true
    end
    callback(state)
    return
  end

  callback(state)
end

--- Get all refs (branches and tags) using git for-each-ref
---@param opts? GitCommandOptions
---@param callback fun(refs: RefInfo[]|nil, err: string|nil)
function M.refs(opts, callback)
  local format = parse.get_refs_format_string()
  cli.run_async(
    { "for-each-ref", "--format=" .. format, "refs/heads", "refs/remotes", "refs/tags" },
    opts,
    function(result)
      if result.code ~= 0 then
        callback(nil, table.concat(result.stderr, "\n"))
        return
      end
      callback(parse.parse_for_each_ref(result.stdout), nil)
    end
  )
end

--- Delete a tag (local)
---@param tag string Tag name
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.delete_tag(tag, opts, callback)
  cli.run_async({ "tag", "-d", tag }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Delete a remote tag
---@param remote string Remote name (e.g., "origin")
---@param tag string Tag name
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.delete_remote_tag(remote, tag, opts, callback)
  cli.run_async({ "push", remote, "--delete", "refs/tags/" .. tag }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

-- =============================================================================
-- Submodule Operations
-- =============================================================================

--- Get submodule status
---@param opts? GitCommandOptions
---@param callback fun(submodules: SubmoduleEntry[]|nil, err: string|nil)
function M.submodule_status(opts, callback)
  cli.run_async({ "submodule", "status" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_submodule_status(result.stdout), nil)
  end)
end

--- Get the recorded SHA for a submodule in the index
--- Returns the SHA that git expects the submodule to be at
---@param path string Submodule path
---@param staged boolean Whether to get staged (index) or committed (HEAD) SHA
---@param opts? GitCommandOptions
---@param callback fun(sha: string|nil, err: string|nil)
function M.submodule_recorded_sha(path, staged, opts, callback)
  local args
  if staged then
    -- Get SHA from index
    args = { "ls-tree", "-d", "HEAD", "--", path }
  else
    -- Get SHA from HEAD (committed)
    args = { "ls-tree", "-d", "HEAD", "--", path }
  end

  cli.run_async(args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    -- Format: "160000 commit <sha>\t<path>"
    local sha = result.stdout[1] and result.stdout[1]:match("^%d+%s+%w+%s+(%x+)")
    callback(sha, nil)
  end)
end

--- Get the current SHA for a submodule (what it's actually at)
---@param path string Submodule path
---@param opts? GitCommandOptions
---@param callback fun(sha: string|nil, err: string|nil)
function M.submodule_current_sha(path, opts, callback)
  local submodule_opts = vim.tbl_extend("force", opts or {}, {
    cwd = (opts and opts.cwd or vim.fn.getcwd()) .. "/" .. path,
  })

  cli.run_async({ "rev-parse", "HEAD" }, submodule_opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    local sha = result.stdout[1] and vim.trim(result.stdout[1])
    callback(sha, nil)
  end)
end

--- Update submodules
---@param paths string[]|nil Specific submodule paths (nil for all)
---@param args string[] Extra arguments (e.g., {"--init", "--recursive"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.submodule_update(paths, args, opts, callback)
  local update_args = { "submodule", "update" }
  vim.list_extend(update_args, args)
  if paths and #paths > 0 then
    table.insert(update_args, "--")
    vim.list_extend(update_args, paths)
  end

  cli.run_async(update_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Initialize submodules
---@param paths string[]|nil Specific submodule paths (nil for all)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.submodule_init(paths, opts, callback)
  local init_args = { "submodule", "init" }
  if paths and #paths > 0 then
    table.insert(init_args, "--")
    vim.list_extend(init_args, paths)
  end

  cli.run_async(init_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Synchronize submodule URLs
---@param paths string[]|nil Specific submodule paths (nil for all)
---@param args string[] Extra arguments (e.g., {"--recursive"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.submodule_sync(paths, args, opts, callback)
  local sync_args = { "submodule", "sync" }
  vim.list_extend(sync_args, args)
  if paths and #paths > 0 then
    table.insert(sync_args, "--")
    vim.list_extend(sync_args, paths)
  end

  cli.run_async(sync_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Deinitialize submodules (remove working tree)
---@param paths string[] Specific submodule paths
---@param args string[] Extra arguments (e.g., {"--force"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.submodule_deinit(paths, args, opts, callback)
  local deinit_args = { "submodule", "deinit" }
  vim.list_extend(deinit_args, args)
  if #paths > 0 then
    table.insert(deinit_args, "--")
    vim.list_extend(deinit_args, paths)
  end

  cli.run_async(deinit_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Add a new submodule
---@param url string Repository URL
---@param path string|nil Destination path (optional, git will derive from URL)
---@param args string[] Extra arguments (e.g., {"-b", "main"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.submodule_add(url, path, args, opts, callback)
  local add_args = { "submodule", "add" }
  vim.list_extend(add_args, args)
  table.insert(add_args, url)
  if path and path ~= "" then
    table.insert(add_args, path)
  end

  cli.run_async(add_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Absorb submodule git directories (register)
--- Moves .git directories from submodules into the superproject's .git/modules
---@param paths string[]|nil Specific submodule paths (nil for all)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.submodule_absorb(paths, opts, callback)
  local absorb_args = { "submodule", "absorbgitdirs" }
  if paths and #paths > 0 then
    table.insert(absorb_args, "--")
    vim.list_extend(absorb_args, paths)
  end

  cli.run_async(absorb_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Fetch in all submodules
---@param args string[] Extra arguments (e.g., {"--recurse-submodules"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.fetch_modules(args, opts, callback)
  local fetch_args = { "submodule", "foreach", "git", "fetch" }
  vim.list_extend(fetch_args, args)

  cli.run_async(fetch_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- List submodule paths from .gitmodules
---@param opts? GitCommandOptions
---@param callback fun(paths: string[]|nil, err: string|nil)
function M.submodule_list(opts, callback)
  -- Use config to list all submodule paths
  cli.run_async(
    { "config", "--file", ".gitmodules", "--get-regexp", "^submodule\\..+\\.path$" },
    opts,
    function(result)
      if result.code ~= 0 then
        -- No .gitmodules or no submodules configured
        callback({}, nil)
        return
      end

      local paths = {}
      for _, line in ipairs(result.stdout) do
        -- Format: "submodule.foo/bar.path foo/bar"
        local path = line:match("^submodule%..+%.path%s+(.+)$")
        if path then
          table.insert(paths, path)
        end
      end
      callback(paths, nil)
    end
  )
end

--- Get a git config value synchronously
---@param key string Config key (e.g., "user.name")
---@param opts? GitCommandOptions
---@return string|nil value The config value or nil if not set
function M.config_get(key, opts)
  local result = cli.run_sync({ "config", "--default", "", "--get", key }, opts)
  if result.code ~= 0 then
    return nil
  end
  local value = result.stdout[1]
  if value and value ~= "" then
    return value:match("^%s*(.-)%s*$") -- trim whitespace
  end
  return nil
end

--- Set a git config value
---@param key string Config key
---@param value string Config value
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.config_set(key, value, opts, callback)
  cli.run_async({ "config", key, value }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get a git config boolean value synchronously
--- Returns true if value is "true", false if "false" or unset
---@param key string Config key
---@param opts? GitCommandOptions
---@return boolean
function M.config_get_bool(key, opts)
  local value = M.config_get(key, opts)
  return value == "true"
end

--- Toggle a git config boolean value
---@param key string Config key
---@param opts? GitCommandOptions
---@param callback fun(new_value: boolean, err: string|nil)
function M.config_toggle(key, opts, callback)
  local current = M.config_get_bool(key, opts)
  local new_value = not current
  M.config_set(key, tostring(new_value), opts, function(success, err)
    if success then
      callback(new_value, nil)
    else
      callback(false, err)
    end
  end)
end

--- Unset a git config value
---@param key string Config key
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.config_unset(key, opts, callback)
  cli.run_async({ "config", "--unset", key }, opts, function(result)
    -- Exit code 5 means the key doesn't exist, which is fine for unset
    if result.code == 0 or result.code == 5 then
      callback(true, nil)
    else
      callback(errors.result_to_callback(result))
    end
  end)
end

-- =============================================================================
-- Merge Operations
-- =============================================================================

---@class MergeState
---@field merge_in_progress boolean Whether a merge is in progress
---@field merge_head_oid string|nil The commit OID being merged (from MERGE_HEAD)

--- Check if a merge is in progress
---@param opts? GitCommandOptions
---@param callback fun(state: MergeState)
function M.get_merge_state(opts, callback)
  local git_dir = cli.find_git_dir(opts and opts.cwd or nil)
  if not git_dir then
    callback({
      merge_in_progress = false,
      merge_head_oid = nil,
    })
    return
  end

  local state = {
    merge_in_progress = false,
    merge_head_oid = nil,
  }

  -- Check for MERGE_HEAD
  local merge_head = git_dir .. "/MERGE_HEAD"
  if vim.fn.filereadable(merge_head) == 1 then
    state.merge_in_progress = true
    local content = vim.fn.readfile(merge_head)
    if content[1] then
      state.merge_head_oid = content[1]:match("^(%x+)")
    end
  end

  callback(state)
end

--- Check if a merge is in progress (synchronous)
---@param opts? GitCommandOptions
---@return boolean
function M.merge_in_progress(opts)
  local git_dir = cli.find_git_dir(opts and opts.cwd or nil)
  if not git_dir then
    return false
  end

  local merge_head = git_dir .. "/MERGE_HEAD"
  return vim.fn.filereadable(merge_head) == 1
end

--- Merge a branch into the current branch
---@param branch string Branch name to merge
---@param args string[] Extra arguments (e.g., {"--ff-only", "--no-edit"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.merge(branch, args, opts, callback)
  local merge_args = { "merge" }
  vim.list_extend(merge_args, args)
  table.insert(merge_args, branch)

  cli.run_async(merge_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    -- On conflict, git outputs conflict info to stdout, so use that if stderr is empty
    local err_output = stderr ~= "" and stderr or stdout
    callback(result.code == 0, output, result.code ~= 0 and err_output or nil)
  end)
end

--- Continue/finish a merge by committing (used after conflict resolution)
--- This simply creates a commit to finalize the merge
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.merge_continue(opts, callback)
  -- git commit with no message flag - git uses the prepared merge message
  cli.run_async({ "commit", "--no-edit" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress merge
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.merge_abort(opts, callback)
  cli.run_async({ "merge", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

return M
