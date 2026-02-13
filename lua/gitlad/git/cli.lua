---@mod gitlad.git.cli Async git command execution
---@brief [[
--- Low-level git command execution with async support.
--- Uses vim.fn.jobstart for non-blocking operations.
---@brief ]]

local M = {}

local history = require("gitlad.git.history")

---@class GitCommandResult
---@field stdout string[] Lines of stdout
---@field stderr string[] Lines of stderr
---@field code number Exit code

---@class GitCommandOptions
---@field cwd? string Working directory (defaults to current)
---@field env? table<string, string> Environment variables
---@field timeout? number Timeout in milliseconds (default: 30000)
---@field on_output_line? fun(line: string, is_stderr: boolean) Callback for each output line (streaming)
---@field internal? boolean If true, bypass cooldown marking and command history (for internal operations like git check-ignore)

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
--- Uses git rev-parse to handle worktrees correctly
---@param path? string Path to check (defaults to cwd)
---@return string|nil git_dir Path to .git directory, or nil if not in a repo
function M.find_git_dir(path)
  path = path or vim.fn.getcwd()
  local result = vim.fn.systemlist({ "git", "-C", path, "rev-parse", "--git-dir" })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  local git_dir = result[1]
  -- Make absolute if relative
  if not vim.startswith(git_dir, "/") then
    git_dir = path .. "/" .. git_dir
  end
  return vim.fn.fnamemodify(git_dir, ":p")
end

--- Find the repository root for a given path
--- Uses git rev-parse to handle worktrees correctly
---@param path? string Path to check (defaults to cwd)
---@return string|nil repo_root Path to repository root, or nil if not in a repo
function M.find_repo_root(path)
  path = path or vim.fn.getcwd()
  local result = vim.fn.systemlist({ "git", "-C", path, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.fn.fnamemodify(result[1], ":p")
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
  local cwd = opts.cwd or vim.fn.getcwd()
  local start_time = vim.loop.hrtime()
  local internal = opts.internal or false

  -- Mark operation time for watcher cooldown (lazy require to avoid circular deps)
  if not internal then
    local state = require("gitlad.state")
    state.mark_operation_time(cwd)
  end

  local stdout_data = {}
  local stderr_data = {}
  local job_id

  local timeout_timer = nil
  local completed = false

  -- Use unbuffered mode when streaming is requested for real-time output
  local streaming = opts.on_output_line ~= nil
  local stdout_partial = ""
  local stderr_partial = ""

  local function on_complete(code)
    if completed then
      return
    end
    completed = true

    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
    end

    -- Emit any remaining partial lines when streaming
    if streaming then
      if stdout_partial ~= "" then
        table.insert(stdout_data, stdout_partial)
        vim.schedule(function()
          opts.on_output_line(stdout_partial, false)
        end)
      end
      if stderr_partial ~= "" then
        table.insert(stderr_data, stderr_partial)
        vim.schedule(function()
          opts.on_output_line(stderr_partial, true)
        end)
      end
    end

    -- Calculate duration
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1e6

    -- Log to history (skip for internal operations)
    if not internal then
      history.add({
        cmd = args[1] or "git",
        args = args,
        cwd = cwd,
        exit_code = code,
        stdout = stdout_data,
        stderr = stderr_data,
        timestamp = os.time(),
        duration_ms = duration_ms,
      })
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
    stdout_buffered = not streaming,
    stderr_buffered = not streaming,
    on_stdout = function(_, data)
      if data then
        if streaming then
          -- Manual line buffering for real-time streaming
          for i, chunk in ipairs(data) do
            if i == 1 then
              -- First chunk continues the previous partial line
              stdout_partial = stdout_partial .. chunk
            else
              -- Previous partial is now complete
              if stdout_partial ~= "" then
                table.insert(stdout_data, stdout_partial)
                local line = stdout_partial
                vim.schedule(function()
                  opts.on_output_line(line, false)
                end)
              end
              stdout_partial = chunk
            end
          end
        else
          -- Buffered mode - data arrives as complete lines
          if #data > 0 and data[#data] == "" then
            table.remove(data)
          end
          vim.list_extend(stdout_data, data)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        if streaming then
          -- Manual line buffering for real-time streaming
          for i, chunk in ipairs(data) do
            if i == 1 then
              stderr_partial = stderr_partial .. chunk
            else
              if stderr_partial ~= "" then
                table.insert(stderr_data, stderr_partial)
                local line = stderr_partial
                vim.schedule(function()
                  opts.on_output_line(line, true)
                end)
              end
              stderr_partial = chunk
            end
          end
        else
          -- Buffered mode
          if #data > 0 and data[#data] == "" then
            table.remove(data)
          end
          vim.list_extend(stderr_data, data)
        end
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
  local cwd = opts.cwd or vim.fn.getcwd()
  local start_time = vim.loop.hrtime()
  local internal = opts.internal or false

  -- Mark operation time for watcher cooldown (lazy require to avoid circular deps)
  if not internal then
    local state = require("gitlad.state")
    state.mark_operation_time(cwd)
  end

  local result = vim.fn.systemlist(cmd)
  local code = vim.v.shell_error

  -- Calculate duration
  local end_time = vim.loop.hrtime()
  local duration_ms = (end_time - start_time) / 1e6

  -- Log to history (skip for internal operations)
  if not internal then
    history.add({
      cmd = args[1] or "git",
      args = args,
      cwd = cwd,
      exit_code = code,
      stdout = result,
      stderr = {}, -- systemlist doesn't separate stderr
      timestamp = os.time(),
      duration_ms = duration_ms,
    })
  end

  return {
    stdout = result,
    stderr = {},
    code = code,
  }
end

--- Cancel a running git command
---@param job_id number Job ID to cancel
function M.cancel(job_id)
  vim.fn.jobstop(job_id)
end

--- Run a git command asynchronously with stdin input
---@param args string[] Git command arguments (without 'git' prefix)
---@param stdin_lines string[] Lines to send to stdin
---@param opts? GitCommandOptions Options
---@param callback fun(result: GitCommandResult) Callback with result
---@return number job_id Job ID for cancellation
function M.run_async_with_stdin(args, stdin_lines, opts, callback)
  opts = opts or {}
  local cmd = build_command(args)
  local cwd = opts.cwd or vim.fn.getcwd()
  local start_time = vim.loop.hrtime()
  local internal = opts.internal or false

  -- Mark operation time for watcher cooldown (lazy require to avoid circular deps)
  if not internal then
    local state = require("gitlad.state")
    state.mark_operation_time(cwd)
  end

  local stdout_data = {}
  local stderr_data = {}
  local job_id

  local timeout_timer = nil
  local completed = false

  -- Use unbuffered mode when streaming is requested for real-time output
  local streaming = opts.on_output_line ~= nil
  local stdout_partial = ""
  local stderr_partial = ""

  local function on_complete(code)
    if completed then
      return
    end
    completed = true

    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
    end

    -- Emit any remaining partial lines when streaming
    if streaming then
      if stdout_partial ~= "" then
        table.insert(stdout_data, stdout_partial)
        vim.schedule(function()
          opts.on_output_line(stdout_partial, false)
        end)
      end
      if stderr_partial ~= "" then
        table.insert(stderr_data, stderr_partial)
        vim.schedule(function()
          opts.on_output_line(stderr_partial, true)
        end)
      end
    end

    -- Calculate duration
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1e6

    -- Log to history (skip for internal operations)
    if not internal then
      history.add({
        cmd = args[1] or "git",
        args = args,
        cwd = cwd,
        exit_code = code,
        stdout = stdout_data,
        stderr = stderr_data,
        timestamp = os.time(),
        duration_ms = duration_ms,
      })
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
    stdout_buffered = not streaming,
    stderr_buffered = not streaming,
    on_stdout = function(_, data)
      if data then
        if streaming then
          -- Manual line buffering for real-time streaming
          for i, chunk in ipairs(data) do
            if i == 1 then
              -- First chunk continues the previous partial line
              stdout_partial = stdout_partial .. chunk
            else
              -- Previous partial is now complete
              if stdout_partial ~= "" then
                table.insert(stdout_data, stdout_partial)
                local line = stdout_partial
                vim.schedule(function()
                  opts.on_output_line(line, false)
                end)
              end
              stdout_partial = chunk
            end
          end
        else
          -- Buffered mode - data arrives as complete lines
          if #data > 0 and data[#data] == "" then
            table.remove(data)
          end
          vim.list_extend(stdout_data, data)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        if streaming then
          -- Manual line buffering for real-time streaming
          for i, chunk in ipairs(data) do
            if i == 1 then
              stderr_partial = stderr_partial .. chunk
            else
              if stderr_partial ~= "" then
                table.insert(stderr_data, stderr_partial)
                local line = stderr_partial
                vim.schedule(function()
                  opts.on_output_line(line, true)
                end)
              end
              stderr_partial = chunk
            end
          end
        else
          -- Buffered mode
          if #data > 0 and data[#data] == "" then
            table.remove(data)
          end
          vim.list_extend(stderr_data, data)
        end
      end
    end,
    on_exit = function(_, code)
      on_complete(code)
    end,
  })

  -- Send stdin data and close
  if job_id > 0 then
    local stdin_content = table.concat(stdin_lines, "\n") .. "\n"
    vim.fn.chansend(job_id, stdin_content)
    vim.fn.chanclose(job_id, "stdin")
  end

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

return M
