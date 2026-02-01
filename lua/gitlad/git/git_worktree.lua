---@mod gitlad.git.git_worktree Worktree operations
---@brief [[
--- Worktree-related git operations: add, list, remove, move, lock, unlock, prune.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")
local errors = require("gitlad.utils.errors")

--- List all worktrees
---@param opts? GitCommandOptions
---@param callback fun(worktrees: WorktreeEntry[]|nil, err: string|nil)
function M.worktree_list(opts, callback)
  cli.run_async({ "worktree", "list", "--porcelain" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_worktree_list(result.stdout), nil)
  end)
end

--- Add a new worktree for an existing branch/commit
---@param path string Path for the new worktree
---@param ref string Branch name or commit to checkout
---@param args string[] Extra arguments (from popup switches, e.g., {"--force", "--detach", "--lock"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.worktree_add(path, ref, args, opts, callback)
  local worktree_args = { "worktree", "add" }
  -- Add switches before path/ref (standard git convention)
  vim.list_extend(worktree_args, args)
  table.insert(worktree_args, path)
  if ref and ref ~= "" then
    table.insert(worktree_args, ref)
  end

  cli.run_async(worktree_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Add a new worktree with a new branch
---@param path string Path for the new worktree
---@param branch string New branch name to create
---@param start_point string|nil Starting point for the new branch (default: HEAD)
---@param args string[] Extra arguments (from popup switches, e.g., {"--force", "--lock"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.worktree_add_new_branch(path, branch, start_point, args, opts, callback)
  local worktree_args = { "worktree", "add" }
  -- Add switches before -b
  vim.list_extend(worktree_args, args)
  -- Add -b flag for creating new branch
  table.insert(worktree_args, "-b")
  table.insert(worktree_args, branch)
  table.insert(worktree_args, path)
  if start_point and start_point ~= "" then
    table.insert(worktree_args, start_point)
  end

  cli.run_async(worktree_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Remove a worktree
---@param worktree_path string Path to the worktree to remove
---@param force boolean Whether to force removal (for dirty worktrees)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.worktree_remove(worktree_path, force, opts, callback)
  local worktree_args = { "worktree", "remove" }
  if force then
    table.insert(worktree_args, "--force")
  end
  table.insert(worktree_args, worktree_path)

  cli.run_async(worktree_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Move a worktree to a new path
---@param worktree_path string Current path of the worktree
---@param new_path string New path for the worktree
---@param force boolean Whether to force move (for locked worktrees, needs --force --force)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.worktree_move(worktree_path, new_path, force, opts, callback)
  local worktree_args = { "worktree", "move" }
  if force then
    -- For locked worktrees, need --force --force
    table.insert(worktree_args, "--force")
    table.insert(worktree_args, "--force")
  end
  table.insert(worktree_args, worktree_path)
  table.insert(worktree_args, new_path)

  cli.run_async(worktree_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Lock a worktree
---@param worktree_path string Path to the worktree to lock
---@param reason string|nil Optional reason for locking
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.worktree_lock(worktree_path, reason, opts, callback)
  local worktree_args = { "worktree", "lock" }
  if reason and reason ~= "" then
    table.insert(worktree_args, "--reason")
    table.insert(worktree_args, reason)
  end
  table.insert(worktree_args, worktree_path)

  cli.run_async(worktree_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Unlock a worktree
---@param worktree_path string Path to the worktree to unlock
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.worktree_unlock(worktree_path, opts, callback)
  local worktree_args = { "worktree", "unlock", worktree_path }

  cli.run_async(worktree_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Prune stale worktree entries
---@param dry_run boolean If true, only show what would be pruned without actually pruning
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.worktree_prune(dry_run, opts, callback)
  local worktree_args = { "worktree", "prune" }
  if dry_run then
    table.insert(worktree_args, "--dry-run")
  end
  table.insert(worktree_args, "--verbose")

  cli.run_async(worktree_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

return M
