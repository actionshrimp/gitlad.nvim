---@mod gitlad.git Git operations interface
---@brief [[
--- High-level git operations built on the CLI wrapper.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")
local errors = require("gitlad.utils.errors")

--- Get repository status
---@param opts? GitCommandOptions
---@param callback fun(result: GitStatusResult|nil, err: string|nil)
function M.status(opts, callback)
  cli.run_async(
    { "status", "--porcelain=v2", "--branch", "--untracked-files=normal" },
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
  local result =
    cli.run_sync({ "status", "--porcelain=v2", "--branch", "--untracked-files=normal" }, opts)
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
function M.diff(path, staged, opts, callback)
  local args = { "diff" }
  if staged then
    table.insert(args, "--cached")
  end
  table.insert(args, "--")
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

--- Get list of branches
---@param opts? GitCommandOptions
---@param callback fun(branches: table[]|nil, err: string|nil)
function M.branches(opts, callback)
  cli.run_async({ "branch" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_branches(result.stdout), nil)
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

--- Delete an untracked file
---@param path string File path to delete
---@param opts? GitCommandOptions Options (cwd is the repository root)
---@param callback fun(success: boolean, err: string|nil)
function M.delete_untracked(path, opts, callback)
  local repo_root = opts and opts.cwd or vim.fn.getcwd()
  local full_path = repo_root .. "/" .. path
  local ok, err = os.remove(full_path)
  if ok then
    callback(true, nil)
  else
    callback(false, err or "Failed to delete file")
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
    local full_path = repo_root .. "/" .. path
    local ok, err = os.remove(full_path)
    if not ok then
      table.insert(failed, path .. ": " .. (err or "unknown error"))
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
---@param reverse boolean Whether to reverse the patch (for unstaging)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.apply_patch(patch_lines, reverse, opts, callback)
  local args = { "apply", "--cached" }
  if reverse then
    table.insert(args, "-R")
  end

  cli.run_async_with_stdin(args, patch_lines, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Create a commit with a message
---@param message_lines string[] Commit message lines
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit(message_lines, args, opts, callback)
  -- Build commit args: commit -F - <extra_args>
  -- Using -F - to read message from stdin avoids shell escaping issues
  local commit_args = { "commit", "-F", "-" }
  vim.list_extend(commit_args, args)

  cli.run_async_with_stdin(commit_args, message_lines, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Amend the current commit without editing the message
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_amend_no_edit(args, opts, callback)
  local commit_args = { "commit", "--amend", "--no-edit" }
  vim.list_extend(commit_args, args)

  cli.run_async(commit_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Create a commit with streaming output viewer
--- Shows a floating window with real-time hook output
---@param message_lines string[] Commit message lines
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_streaming(message_lines, args, opts, callback)
  local output_viewer = require("gitlad.ui.views.output")

  -- Build display command for the viewer
  local display_cmd = "git commit " .. table.concat(args, " ")

  local viewer = output_viewer.open({
    title = "Commit",
    command = display_cmd,
  })

  -- Build commit args: commit -F - <extra_args>
  local commit_args = { "commit", "-F", "-" }
  vim.list_extend(commit_args, args)

  cli.run_async_with_stdin(commit_args, message_lines, {
    cwd = opts and opts.cwd,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(result)
    viewer:complete(result.code)
    callback(errors.result_to_callback(result))
  end)
end

--- Amend the current commit without editing the message, with streaming output viewer
--- Shows a floating window with real-time hook output
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_amend_no_edit_streaming(args, opts, callback)
  local output_viewer = require("gitlad.ui.views.output")

  -- Build display command for the viewer
  local display_cmd = "git commit --amend --no-edit " .. table.concat(args, " ")

  local viewer = output_viewer.open({
    title = "Amend",
    command = display_cmd,
  })

  local commit_args = { "commit", "--amend", "--no-edit" }
  vim.list_extend(commit_args, args)

  cli.run_async(commit_args, {
    cwd = opts and opts.cwd,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(result)
    viewer:complete(result.code)
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

--- Checkout a branch
---@param branch string Branch name to checkout
---@param args string[] Extra arguments (from popup switches)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.checkout(branch, args, opts, callback)
  local checkout_args = { "checkout" }
  vim.list_extend(checkout_args, args)
  table.insert(checkout_args, branch)

  cli.run_async(checkout_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Create and checkout a new branch
---@param name string New branch name
---@param base string|nil Base ref (defaults to HEAD if nil)
---@param args string[] Extra arguments (e.g., --track)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.checkout_new_branch(name, base, args, opts, callback)
  local checkout_args = { "checkout", "-b", name }
  vim.list_extend(checkout_args, args)
  if base and base ~= "" then
    table.insert(checkout_args, base)
  end

  cli.run_async(checkout_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Create a branch (without checking it out)
---@param name string New branch name
---@param base string|nil Base ref (defaults to HEAD if nil)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.create_branch(name, base, opts, callback)
  local branch_args = { "branch", name }
  if base and base ~= "" then
    table.insert(branch_args, base)
  end

  cli.run_async(branch_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Delete a branch
---@param name string Branch name to delete
---@param force boolean Whether to force delete (git branch -D vs -d)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.delete_branch(name, force, opts, callback)
  local flag = force and "-D" or "-d"
  local branch_args = { "branch", flag, name }

  cli.run_async(branch_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Rename a branch
---@param old_name string Current branch name
---@param new_name string New branch name
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.rename_branch(old_name, new_name, opts, callback)
  local branch_args = { "branch", "-m", old_name, new_name }

  cli.run_async(branch_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get the commit subject for a ref
---@param ref string Git ref (branch, tag, commit hash)
---@param opts? GitCommandOptions
---@param callback fun(subject: string|nil, err: string|nil)
function M.get_commit_subject(ref, opts, callback)
  cli.run_async({ "log", "-1", "--format=%s", ref }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(result.stdout[1] or "", nil)
  end)
end

--- Get commits between two refs
---@param base string Base ref (the older end)
---@param target string Target ref (the newer end)
---@param opts? GitCommandOptions
---@param callback fun(commits: GitCommitInfo[]|nil, err: string|nil)
function M.get_commits_between(base, target, opts, callback)
  -- git log base..target shows commits reachable from target but not from base
  -- Use --decorate to get refs (branches, tags) on commits
  cli.run_async({ "log", "--oneline", "--decorate", base .. ".." .. target }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_log_oneline(result.stdout), nil)
  end)
end

--- Get push remote for a branch
---@param branch string Branch name
---@param opts? GitCommandOptions
---@param callback fun(remote: string|nil, err: string|nil)
function M.get_push_remote(branch, opts, callback)
  -- First try branch.<branch>.pushRemote
  cli.run_async({ "config", "--get", "branch." .. branch .. ".pushRemote" }, opts, function(result)
    if result.code == 0 and result.stdout[1] and result.stdout[1] ~= "" then
      callback(result.stdout[1], nil)
      return
    end

    -- Fallback to remote.pushDefault
    cli.run_async({ "config", "--get", "remote.pushDefault" }, opts, function(fallback_result)
      if
        fallback_result.code == 0
        and fallback_result.stdout[1]
        and fallback_result.stdout[1] ~= ""
      then
        callback(fallback_result.stdout[1], nil)
      else
        -- No push remote configured
        callback(nil, nil)
      end
    end)
  end)
end

--- Set upstream (tracking branch) for a branch
---@param branch string Branch name
---@param upstream_ref string Upstream ref (e.g., "origin/main")
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.set_upstream(branch, upstream_ref, opts, callback)
  cli.run_async({ "branch", "--set-upstream-to=" .. upstream_ref, branch }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Set push remote for a branch
---@param branch string Branch name
---@param remote string Remote name (e.g., "origin")
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.set_push_remote(branch, remote, opts, callback)
  cli.run_async({ "config", "branch." .. branch .. ".pushRemote", remote }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get list of remote branches
---@param opts? GitCommandOptions
---@param callback fun(branches: string[]|nil, err: string|nil)
function M.remote_branches(opts, callback)
  cli.run_async({ "branch", "-r" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_remote_branches(result.stdout), nil)
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

--- Get commit log (basic oneline format)
---@param args string[] Additional log arguments (e.g., { "-20" }, { "main..HEAD" })
---@param opts? GitCommandOptions
---@param callback fun(commits: GitCommitInfo[]|nil, err: string|nil)
function M.log(args, opts, callback)
  -- Use --decorate to get refs (branches, tags) on commits
  local log_args = { "log", "--oneline", "--decorate" }
  vim.list_extend(log_args, args)

  cli.run_async(log_args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_log_oneline(result.stdout), nil)
  end)
end

--- Get commit log with detailed info (author, date)
---@param args string[] Additional log arguments (e.g., { "-20" }, { "main..HEAD" })
---@param opts? GitCommandOptions
---@param callback fun(commits: GitCommitInfo[]|nil, err: string|nil)
function M.log_detailed(args, opts, callback)
  local format = parse.get_log_format_string()
  local log_args = { "log", "--format=" .. format }
  vim.list_extend(log_args, args)

  cli.run_async(log_args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_log_format(table.concat(result.stdout, "\n")), nil)
  end)
end

--- Get commit message body
---@param hash string Commit hash
---@param opts? GitCommandOptions
---@param callback fun(body: string|nil, err: string|nil)
function M.show_commit(hash, opts, callback)
  -- Get just the commit body (message after subject)
  local args = { "log", "-1", "--format=%b", hash }

  cli.run_async(args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    local body = table.concat(result.stdout, "\n")
    -- Trim trailing whitespace
    body = body:gsub("%s+$", "")
    callback(body ~= "" and body or nil, nil)
  end)
end

--- Create a new stash
---@param message string|nil Optional stash message
---@param args string[] Extra arguments (from popup switches, e.g., {"--include-untracked"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stash_push(message, args, opts, callback)
  local stash_args = { "stash", "push" }
  -- Add switches before message (standard git convention)
  vim.list_extend(stash_args, args)
  if message and message ~= "" then
    table.insert(stash_args, "-m")
    table.insert(stash_args, message)
  end

  cli.run_async(stash_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Pop a stash (apply and remove)
---@param stash_ref string|nil Stash ref (e.g., "stash@{0}"), nil for most recent
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stash_pop(stash_ref, opts, callback)
  local stash_args = { "stash", "pop" }
  if stash_ref and stash_ref ~= "" then
    table.insert(stash_args, stash_ref)
  end

  cli.run_async(stash_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Apply a stash (without removing it)
---@param stash_ref string|nil Stash ref (e.g., "stash@{0}"), nil for most recent
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stash_apply(stash_ref, opts, callback)
  local stash_args = { "stash", "apply" }
  if stash_ref and stash_ref ~= "" then
    table.insert(stash_args, stash_ref)
  end

  cli.run_async(stash_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Drop a stash (remove without applying)
---@param stash_ref string Stash ref (e.g., "stash@{0}")
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.stash_drop(stash_ref, opts, callback)
  local stash_args = { "stash", "drop", stash_ref }

  cli.run_async(stash_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- List all stashes
---@param opts? GitCommandOptions
---@param callback fun(stashes: StashEntry[]|nil, err: string|nil)
function M.stash_list(opts, callback)
  cli.run_async({ "stash", "list" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_stash_list(result.stdout), nil)
  end)
end

--- Reset current branch to a ref
---@param ref string The ref to reset to (e.g., "origin/main", "HEAD~1")
---@param mode string Reset mode: "soft", "mixed", or "hard"
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.reset(ref, mode, opts, callback)
  local reset_args = { "reset", "--" .. mode, ref }

  cli.run_async(reset_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Reset current branch to a ref with --keep (preserves uncommitted changes)
---@param ref string The ref to reset to (e.g., "origin/main", "HEAD~1")
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.reset_keep(ref, opts, callback)
  local reset_args = { "reset", "--keep", ref }

  cli.run_async(reset_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Reset index only (unstage all files, equivalent to git reset HEAD .)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.reset_index(opts, callback)
  cli.run_async({ "reset", "HEAD", "." }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Reset worktree only to a ref (checkout all files without changing HEAD or index)
---@param ref string The ref to reset worktree to
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.reset_worktree(ref, opts, callback)
  -- Use git checkout to restore worktree from the specified ref
  -- --force overwrites local changes
  cli.run_async({ "checkout", "--force", ref, "--", "." }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get the upstream ref for a branch
---@param branch string Branch name
---@param opts? GitCommandOptions
---@param callback fun(upstream: string|nil, err: string|nil)
function M.get_upstream(branch, opts, callback)
  cli.run_async({ "rev-parse", "--abbrev-ref", branch .. "@{upstream}" }, opts, function(result)
    if result.code ~= 0 then
      -- No upstream configured
      callback(nil, nil)
      return
    end
    callback(result.stdout[1], nil)
  end)
end

--- Cherry-pick one or more commits
---@param commits string[] Commit hashes to cherry-pick
---@param args string[] Extra arguments (from popup switches, e.g., {"-x", "--signoff"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.cherry_pick(commits, args, opts, callback)
  local cherry_pick_args = { "cherry-pick" }
  vim.list_extend(cherry_pick_args, args)
  vim.list_extend(cherry_pick_args, commits)

  cli.run_async(cherry_pick_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Continue an in-progress cherry-pick
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.cherry_pick_continue(opts, callback)
  cli.run_async({ "cherry-pick", "--continue" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress cherry-pick
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.cherry_pick_abort(opts, callback)
  cli.run_async({ "cherry-pick", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Skip the current commit during cherry-pick
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.cherry_pick_skip(opts, callback)
  cli.run_async({ "cherry-pick", "--skip" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Revert one or more commits
---@param commits string[] Commit hashes to revert
---@param args string[] Extra arguments (from popup switches, e.g., {"--no-edit", "--signoff"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.revert(commits, args, opts, callback)
  local revert_args = { "revert" }
  vim.list_extend(revert_args, args)
  vim.list_extend(revert_args, commits)

  cli.run_async(revert_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Continue an in-progress revert
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.revert_continue(opts, callback)
  cli.run_async({ "revert", "--continue" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress revert
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.revert_abort(opts, callback)
  cli.run_async({ "revert", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Skip the current commit during revert
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.revert_skip(opts, callback)
  cli.run_async({ "revert", "--skip" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

---@class SequencerState
---@field cherry_pick_in_progress boolean
---@field revert_in_progress boolean
---@field rebase_in_progress boolean
---@field sequencer_head_oid string|nil The commit being cherry-picked/reverted

--- Check if a cherry-pick, revert, or rebase is in progress
---@param opts? GitCommandOptions
---@param callback fun(state: SequencerState)
function M.get_sequencer_state(opts, callback)
  local git_dir = cli.find_git_dir(opts and opts.cwd or nil)
  if not git_dir then
    callback({
      cherry_pick_in_progress = false,
      revert_in_progress = false,
      rebase_in_progress = false,
      sequencer_head_oid = nil,
    })
    return
  end

  local state = {
    cherry_pick_in_progress = false,
    revert_in_progress = false,
    rebase_in_progress = false,
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

  -- Check for rebase in progress (rebase-merge or rebase-apply directories)
  local rebase_merge = git_dir .. "/rebase-merge"
  local rebase_apply = git_dir .. "/rebase-apply"
  if vim.fn.isdirectory(rebase_merge) == 1 or vim.fn.isdirectory(rebase_apply) == 1 then
    state.rebase_in_progress = true
    callback(state)
    return
  end

  callback(state)
end

--- Rebase current branch onto a target
---@param target string Target ref to rebase onto (e.g., "origin/main")
---@param args string[] Extra arguments (from popup switches, e.g., {"--autostash"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.rebase(target, args, opts, callback)
  local rebase_args = { "rebase" }
  vim.list_extend(rebase_args, args)
  table.insert(rebase_args, target)

  cli.run_async(rebase_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Continue an in-progress rebase
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.rebase_continue(opts, callback)
  cli.run_async({ "rebase", "--continue" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress rebase
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.rebase_abort(opts, callback)
  cli.run_async({ "rebase", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Skip the current commit during rebase
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.rebase_skip(opts, callback)
  cli.run_async({ "rebase", "--skip" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Check if a rebase is in progress (synchronous)
---@param opts? GitCommandOptions
---@return boolean
function M.rebase_in_progress(opts)
  local git_dir = cli.find_git_dir(opts and opts.cwd or nil)
  if not git_dir then
    return false
  end

  local rebase_merge = git_dir .. "/rebase-merge"
  local rebase_apply = git_dir .. "/rebase-apply"
  return vim.fn.isdirectory(rebase_merge) == 1 or vim.fn.isdirectory(rebase_apply) == 1
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

--- Get cherry commits between ref and upstream (commits unique to ref)
--- Shows commits in ref that are not in upstream, with equivalence markers
---@param ref string The ref to check (e.g., "feature-branch")
---@param upstream string The upstream to compare against (e.g., "main")
---@param opts? GitCommandOptions
---@param callback fun(commits: CherryCommit[]|nil, err: string|nil)
function M.cherry(ref, upstream, opts, callback)
  -- git cherry -v <upstream> <ref> shows commits in ref not in upstream
  -- + means unique to ref, - means equivalent (cherry-picked) commit exists in upstream
  cli.run_async({ "cherry", "-v", upstream, ref }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_cherry(result.stdout), nil)
  end)
end

--- Get ahead/behind count between ref and another ref
---@param ref string The ref to check
---@param compare_to string The ref to compare against
---@param opts? GitCommandOptions
---@param callback fun(ahead: number, behind: number, err: string|nil)
function M.rev_list_count(ref, compare_to, opts, callback)
  -- git rev-list --left-right --count ref...compare_to
  -- Output: "ahead\tbehind"
  cli.run_async(
    { "rev-list", "--left-right", "--count", ref .. "..." .. compare_to },
    opts,
    function(result)
      if result.code ~= 0 then
        callback(0, 0, table.concat(result.stderr, "\n"))
        return
      end
      local ahead, behind = parse.parse_rev_list_count(result.stdout)
      callback(ahead, behind, nil)
    end
  )
end

--- Delete a remote branch
---@param remote string Remote name (e.g., "origin")
---@param branch string Branch name (without remote/ prefix)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.delete_remote_branch(remote, branch, opts, callback)
  cli.run_async({ "push", remote, "--delete", branch }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
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

return M
