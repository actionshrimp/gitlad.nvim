---@mod gitlad.git.git_stash Stash operations
---@brief [[
--- Stash-related git operations: push, pop, apply, drop, list.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")
local errors = require("gitlad.utils.errors")

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

return M
