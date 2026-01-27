---@mod gitlad.git.git_rebase Rebase operations
---@brief [[
--- Rebase-related git operations: interactive, continue, abort, skip, reset.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local errors = require("gitlad.utils.errors")

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

--- Run an instant rebase (non-interactive, autosquash)
--- Used for instant fixup/squash operations.
--- Sets GIT_SEQUENCE_EDITOR to ":" to auto-apply the todo without user interaction.
---@param commit string Base commit for rebase (parent of commits to squash)
---@param args string[] Extra arguments
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.rebase_instantly(commit, args, opts, callback)
  local rebase_args = { "rebase", "--interactive", "--autosquash", "--autostash", "--keep-empty" }
  vim.list_extend(rebase_args, args or {})
  table.insert(rebase_args, commit)

  -- Use ":" as sequence editor to auto-apply todo (no-op editor)
  local env = vim.tbl_extend("force", opts and opts.env or {}, {
    GIT_SEQUENCE_EDITOR = ":",
    GIT_EDITOR = ":",
  })

  local run_opts = vim.tbl_extend("force", opts or {}, { env = env })

  cli.run_async(rebase_args, run_opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
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

return M
