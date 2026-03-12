---@mod gitlad.worktrunk Worktrunk CLI integration
---@brief [[
--- Integration with the worktrunk (wt) CLI for worktree workflow management.
--- Provides async wrappers around wt commands, following the same pattern as git/cli.lua.
---@brief ]]

local M = {}

local parse = require("gitlad.worktrunk.parse")

-- Allow injecting a custom executor for testing (same pattern as forge/http.lua)
local executor = nil

--- Set a custom executor function for testing
---@param fn function|nil Custom executor (nil to reset to default)
function M._set_executor(fn)
  executor = fn
end

--- Reset executor to default vim.fn.jobstart
function M._reset_executor()
  executor = nil
end

-- Internal executable checker, can be overridden in tests
---@param name string
---@return boolean
M._executable = function(name)
  return vim.fn.executable(name) == 1
end

--- Run a wt command asynchronously
---@param args string[] Arguments to pass to wt
---@param opts { cwd?: string }
---@param callback fun(stdout: string[], code: number)
local function run_async(args, opts, callback)
  local cmd = { "wt" }
  vim.list_extend(cmd, args)
  local cwd = opts.cwd or vim.fn.getcwd()
  local stdout_data = {}
  local stderr_data = {}

  local fn = executor or vim.fn.jobstart
  fn(cmd, {
    cwd = cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        if #data > 0 and data[#data] == "" then
          table.remove(data)
        end
        vim.list_extend(stdout_data, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        if #data > 0 and data[#data] == "" then
          table.remove(data)
        end
        vim.list_extend(stderr_data, data)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        -- On error, combine stderr into stdout for error messages
        if code ~= 0 and #stderr_data > 0 then
          callback(stderr_data, code)
        else
          callback(stdout_data, code)
        end
      end)
    end,
  })
end

--- Check if wt binary is in PATH
---@return boolean
function M.is_installed()
  return M._executable("wt")
end

--- Check if worktrunk should be used given current config
---@param worktree_cfg GitladWorktreeConfig
---@return boolean
function M.is_active(worktree_cfg)
  local mode = worktree_cfg and worktree_cfg.worktrunk or "auto"
  if mode == "never" then
    return false
  elseif mode == "always" then
    if not M.is_installed() then
      vim.notify("[gitlad] worktrunk = 'always' but wt is not in PATH", vim.log.levels.WARN)
    end
    return true
  else -- "auto"
    return M.is_installed()
  end
end

--- List worktrees via wt list --format=json (async)
---@param opts { cwd?: string }
---@param callback fun(infos: WorktreeInfo[]|nil, err: string|nil)
function M.list(opts, callback)
  run_async({ "list", "--format=json" }, opts, function(stdout, code)
    if code ~= 0 then
      callback(nil, "wt list failed (exit " .. code .. "): " .. table.concat(stdout, "\n"))
      return
    end
    local infos = parse.parse_list(stdout)
    callback(infos, nil)
  end)
end

--- Switch to a worktree by branch (creates if needed). Uses --no-cd.
---@param branch string
---@param opts { cwd?: string, create?: boolean, base?: string }
---@param callback fun(success: boolean, err: string|nil)
function M.switch(branch, opts, callback)
  local args = { "switch" }
  if opts.create then
    table.insert(args, "-c")
    if opts.base then
      table.insert(args, "--base")
      table.insert(args, opts.base)
    end
  end
  table.insert(args, "--no-cd")
  table.insert(args, branch)

  run_async(args, opts, function(stdout, code)
    if code ~= 0 then
      callback(false, "wt switch failed (exit " .. code .. "): " .. table.concat(stdout, "\n"))
      return
    end
    callback(true, nil)
  end)
end

--- Run wt merge pipeline
---@param target string|nil  Target branch (nil = default trunk)
---@param args string[]      Extra flags (--no-squash, --no-rebase, etc.)
---@param opts { cwd?: string }
---@param callback fun(success: boolean, err: string|nil)
function M.merge(target, args, opts, callback)
  local cmd_args = { "merge" }
  vim.list_extend(cmd_args, args)
  if target then
    table.insert(cmd_args, target)
  end

  run_async(cmd_args, opts, function(stdout, code)
    if code ~= 0 then
      callback(false, "wt merge failed (exit " .. code .. "): " .. table.concat(stdout, "\n"))
      return
    end
    callback(true, nil)
  end)
end

--- Remove a worktree by branch
---@param branch string
---@param opts { cwd?: string }
---@param callback fun(success: boolean, err: string|nil)
function M.remove(branch, opts, callback)
  run_async({ "remove", branch }, opts, function(stdout, code)
    if code ~= 0 then
      callback(false, "wt remove failed (exit " .. code .. "): " .. table.concat(stdout, "\n"))
      return
    end
    callback(true, nil)
  end)
end

--- Copy ignored files into the target worktree (wt step copy-ignored)
---@param opts { cwd?: string, from?: string }   cwd = target worktree path
---@param callback fun(success: boolean, err: string|nil)
function M.copy_ignored(opts, callback)
  local args = { "step", "copy-ignored" }
  if opts.from then
    table.insert(args, "--from")
    table.insert(args, opts.from)
  end

  run_async(args, opts, function(stdout, code)
    if code ~= 0 then
      callback(
        false,
        "wt step copy-ignored failed (exit " .. code .. "): " .. table.concat(stdout, "\n")
      )
      return
    end
    callback(true, nil)
  end)
end

return M
