---@mod gitlad.git Git operations interface
---@brief [[
--- High-level git operations built on the CLI wrapper.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")

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
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
  end)
end

--- Unstage a file
---@param path string File path to unstage
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.unstage(path, opts, callback)
  cli.run_async({ "reset", "HEAD", "--", path }, opts, function(result)
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
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
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
  end)
end

--- Unstage all files
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.unstage_all(opts, callback)
  cli.run_async({ "reset", "HEAD" }, opts, function(result)
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
  end)
end

--- Discard changes to a file (checkout from HEAD)
---@param path string File path to discard
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.discard(path, opts, callback)
  cli.run_async({ "checkout", "HEAD", "--", path }, opts, function(result)
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
  end)
end

--- Delete an untracked file
---@param path string File path to delete
---@param repo_root string Repository root path
---@param callback fun(success: boolean, err: string|nil)
function M.delete_untracked(path, repo_root, callback)
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
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
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
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
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
    callback(result.code == 0, result.code ~= 0 and table.concat(result.stderr, "\n") or nil)
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

return M
