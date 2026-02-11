---@mod gitlad.git.git_branches Branch operations
---@brief [[
--- Branch-related git operations: checkout, create, delete, rename, list.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")
local errors = require("gitlad.utils.errors")

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

--- Get the default remote (sensible fallback when no explicit config exists)
--- Resolution order:
---   1. If only one remote exists → use it
---   2. If "origin" remote exists → use it (common convention)
---   3. Otherwise → nil (caller should prompt user)
---@param opts? GitCommandOptions
---@param callback fun(remote: string|nil)
function M.get_default_remote(opts, callback)
  cli.run_async({ "remote" }, opts, function(result)
    if result.code ~= 0 then
      callback(nil)
      return
    end

    -- Filter out empty lines
    local remotes = vim.tbl_filter(function(line)
      return line and line ~= ""
    end, result.stdout)

    if #remotes == 0 then
      callback(nil)
    elseif #remotes == 1 then
      -- Single remote - use it as default
      callback(remotes[1])
    elseif vim.tbl_contains(remotes, "origin") then
      -- Multiple remotes but "origin" exists - use it as convention
      callback("origin")
    else
      -- Multiple remotes, no origin - caller should prompt
      callback(nil)
    end
  end)
end

--- Get push remote for a branch
--- Resolution order (matching magit/neogit):
---   1. branch.<branch>.pushRemote - explicit per-branch config
---   2. remote.pushDefault - global default push remote
---   3. Single remote or "origin" - sensible default
---@param branch string Branch name
---@param opts? GitCommandOptions
---@param callback fun(remote: string|nil, err: string|nil)
function M.get_push_remote(branch, opts, callback)
  -- First try branch.<branch>.pushRemote
  cli.run_async({ "config", "--default", "", "--get", "branch." .. branch .. ".pushRemote" }, opts, function(result)
    if result.code == 0 and result.stdout[1] and result.stdout[1] ~= "" then
      callback(result.stdout[1], nil)
      return
    end

    -- Fallback to remote.pushDefault
    cli.run_async({ "config", "--default", "", "--get", "remote.pushDefault" }, opts, function(fallback_result)
      if
        fallback_result.code == 0
        and fallback_result.stdout[1]
        and fallback_result.stdout[1] ~= ""
      then
        callback(fallback_result.stdout[1], nil)
      else
        -- Final fallback: get default remote (single remote or "origin")
        M.get_default_remote(opts, function(default_remote)
          callback(default_remote, nil)
        end)
      end
    end)
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

return M
