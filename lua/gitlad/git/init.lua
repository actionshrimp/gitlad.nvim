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

--- Unstage a file
---@param path string File path to unstage
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.unstage(path, opts, callback)
  cli.run_async({ "reset", "HEAD", "--", path }, opts, function(result)
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

return M
