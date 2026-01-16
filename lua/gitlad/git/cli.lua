---@mod gitlad.git.cli Async git command execution
---@brief [[
--- Low-level git command execution with async support.
--- Uses vim.fn.jobstart for non-blocking operations.
---@brief ]]

local M = {}

---@class GitCommandResult
---@field stdout string[] Lines of stdout
---@field stderr string[] Lines of stderr
---@field code number Exit code

---@class GitCommandOptions
---@field cwd? string Working directory (defaults to current)
---@field env? table<string, string> Environment variables
---@field timeout? number Timeout in milliseconds (default: 30000)

-- Standard git flags for performance and consistency
local GIT_FLAGS = {
  "--no-pager",
  "--literal-pathspecs",
  "--no-optional-locks",
  "-c",
  "core.preloadindex=true",
  "-c",
  "color.ui=never",
}

--- Find the git directory for a given path
---@param path? string Path to check (defaults to cwd)
---@return string|nil git_dir Path to .git directory, or nil if not in a repo
function M.find_git_dir(path)
  path = path or vim.fn.getcwd()
  local git_dir = vim.fn.finddir(".git", path .. ";")
  if git_dir ~= "" then
    return vim.fn.fnamemodify(git_dir, ":p:h")
  end
  return nil
end

--- Find the repository root for a given path
---@param path? string Path to check (defaults to cwd)
---@return string|nil repo_root Path to repository root, or nil if not in a repo
function M.find_repo_root(path)
  local git_dir = M.find_git_dir(path)
  if git_dir then
    -- .git dir is inside repo root
    return vim.fn.fnamemodify(git_dir, ":h")
  end
  return nil
end

--- Build the full git command with standard flags
---@param args string[] Git command arguments
---@return string[] Full command array
local function build_command(args)
  local cmd = { "git" }
  vim.list_extend(cmd, GIT_FLAGS)
  vim.list_extend(cmd, args)
  return cmd
end

--- Run a git command asynchronously
---@param args string[] Git command arguments (without 'git' prefix)
---@param opts? GitCommandOptions Options
---@param callback fun(result: GitCommandResult) Callback with result
---@return number job_id Job ID for cancellation
function M.run_async(args, opts, callback)
  opts = opts or {}
  local cmd = build_command(args)

  local stdout_data = {}
  local stderr_data = {}
  local job_id

  local timeout_timer = nil
  local completed = false

  local function on_complete(code)
    if completed then
      return
    end
    completed = true

    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
    end

    -- Schedule callback to ensure we're in main loop
    vim.schedule(function()
      callback({
        stdout = stdout_data,
        stderr = stderr_data,
        code = code,
      })
    end)
  end

  job_id = vim.fn.jobstart(cmd, {
    cwd = opts.cwd or vim.fn.getcwd(),
    env = opts.env,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        -- Remove trailing empty string from buffered output
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
      on_complete(code)
    end,
  })

  -- Set up timeout
  local timeout = opts.timeout or 30000
  timeout_timer = vim.fn.timer_start(timeout, function()
    if not completed then
      vim.fn.jobstop(job_id)
      on_complete(-1) -- Timeout exit code
    end
  end)

  return job_id
end

--- Run a git command synchronously (blocking)
--- Use sparingly - prefer run_async for better UX
---@param args string[] Git command arguments
---@param opts? GitCommandOptions Options
---@return GitCommandResult
function M.run_sync(args, opts)
  opts = opts or {}
  local cmd = build_command(args)

  local result = vim.fn.systemlist(cmd)
  local code = vim.v.shell_error

  return {
    stdout = result,
    stderr = {}, -- systemlist doesn't separate stderr
    code = code,
  }
end

--- Cancel a running git command
---@param job_id number Job ID to cancel
function M.cancel(job_id)
  vim.fn.jobstop(job_id)
end

return M
