---@mod gitlad.git.git_remotes Remote operations
---@brief [[
--- Remote-related git operations: add, rename, remove, prune, set-url.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local errors = require("gitlad.utils.errors")

--- Add a new remote
---@param name string Remote name
---@param url string Remote URL
---@param args string[] Extra arguments (e.g., {"-f"} for fetch after add)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.remote_add(name, url, args, opts, callback)
  local remote_args = { "remote", "add" }
  vim.list_extend(remote_args, args)
  table.insert(remote_args, name)
  table.insert(remote_args, url)

  cli.run_async(remote_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Rename a remote
---@param old_name string Current remote name
---@param new_name string New remote name
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.remote_rename(old_name, new_name, opts, callback)
  cli.run_async({ "remote", "rename", old_name, new_name }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Remove a remote
---@param name string Remote name to remove
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.remote_remove(name, opts, callback)
  cli.run_async({ "remote", "remove", name }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Prune stale remote-tracking branches
---@param name string Remote name to prune
---@param dry_run boolean Whether to do a dry run (show what would be pruned)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.remote_prune(name, dry_run, opts, callback)
  local prune_args = { "remote", "prune" }
  if dry_run then
    table.insert(prune_args, "--dry-run")
  end
  table.insert(prune_args, name)

  cli.run_async(prune_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Set URL for a remote
---@param name string Remote name
---@param url string New URL
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.remote_set_url(name, url, opts, callback)
  cli.run_async({ "remote", "set-url", name, url }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get URL for a remote
---@param name string Remote name
---@param opts? GitCommandOptions
---@param callback fun(url: string|nil, err: string|nil)
function M.remote_get_url(name, opts, callback)
  cli.run_async({ "remote", "get-url", name }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    local url = result.stdout[1]
    callback(url and vim.trim(url) or nil, nil)
  end)
end

return M
