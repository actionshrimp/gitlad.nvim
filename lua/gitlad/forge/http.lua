---@mod gitlad.forge.http Async HTTP client for forge APIs
---@brief [[
--- Low-level HTTP request execution with async support.
--- Uses curl + vim.fn.jobstart, mirroring the pattern from git/cli.lua.
---@brief ]]

local M = {}

---@class HttpRequest
---@field url string Full URL to request
---@field method? string HTTP method (default: "GET")
---@field headers? table<string, string> Request headers
---@field body? string Request body (JSON string)
---@field timeout? number Timeout in seconds (default: 30)

---@class HttpResponse
---@field status number HTTP status code
---@field body string Raw response body
---@field json? table Parsed JSON response (nil if parse fails)

-- Allow injecting a custom executor for testing
local executor = nil

--- Set a custom executor function for testing
--- The executor should have the same signature as vim.fn.jobstart
---@param fn function|nil Custom executor (nil to reset to default)
function M._set_executor(fn)
  executor = fn
end

--- Build curl command from request options
---@param request HttpRequest
---@return string[] cmd Command array
function M._build_command(request)
  local cmd = {
    "curl",
    "-s", -- silent (no progress bar)
    "-S", -- show errors
    "-w",
    "\n%{http_code}", -- append HTTP status code on last line
    "-X",
    request.method or "GET",
    "--max-time",
    tostring(request.timeout or 30),
  }

  -- Add headers
  if request.headers then
    for key, value in pairs(request.headers) do
      table.insert(cmd, "-H")
      table.insert(cmd, key .. ": " .. value)
    end
  end

  -- Add body
  if request.body then
    table.insert(cmd, "-d")
    table.insert(cmd, request.body)
  end

  -- URL must be last
  table.insert(cmd, request.url)

  return cmd
end

--- Parse curl output into HttpResponse
--- The last line of stdout contains the HTTP status code (from -w flag)
---@param stdout string[] Lines of stdout
---@return HttpResponse|nil response
---@return string|nil err Error message if parsing fails
function M._parse_response(stdout)
  if not stdout or #stdout == 0 then
    return nil, "Empty response"
  end

  -- Last line is HTTP status code (from -w "\n%{http_code}")
  local status_line = stdout[#stdout]
  local status = tonumber(status_line)
  if not status then
    return nil, "Failed to parse HTTP status code: " .. (status_line or "nil")
  end

  -- Everything before the last line is the response body
  local body_lines = {}
  for i = 1, #stdout - 1 do
    table.insert(body_lines, stdout[i])
  end
  local body = table.concat(body_lines, "\n")

  -- Try to parse JSON
  local json = nil
  if body ~= "" then
    local ok, parsed = pcall(vim.json.decode, body)
    if ok then
      json = parsed
    end
  end

  return {
    status = status,
    body = body,
    json = json,
  }, nil
end

--- Execute an HTTP request asynchronously
---@param request HttpRequest Request options
---@param callback fun(response: HttpResponse|nil, err: string|nil) Callback with result
---@return number job_id Job ID for cancellation
function M.request(request, callback)
  local cmd = M._build_command(request)

  local stdout_data = {}
  local stderr_data = {}
  local completed = false

  local function on_complete(code)
    if completed then
      return
    end
    completed = true

    vim.schedule(function()
      if code ~= 0 then
        local stderr_msg = table.concat(stderr_data, "\n")
        if code == -1 then
          callback(nil, "Request timed out")
        else
          callback(nil, "curl failed (exit " .. code .. "): " .. stderr_msg)
        end
        return
      end

      local response, err = M._parse_response(stdout_data)
      if err then
        callback(nil, err)
        return
      end

      callback(response, nil)
    end)
  end

  local jobstart = executor or vim.fn.jobstart
  local job_id = jobstart(cmd, {
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

  return job_id
end

--- Cancel a running HTTP request
---@param job_id number Job ID to cancel
function M.cancel(job_id)
  pcall(vim.fn.jobstop, job_id)
end

return M
