---@mod gitlad.state.async AsyncHandler for request ordering
---@brief [[
--- Implements the AsyncHandler pattern from lazygit.
--- Ensures only the latest async result is applied, preventing stale data
--- from overwriting fresh data when requests complete out of order.
---@brief ]]

local M = {}

---@class AsyncHandler
---@field current_id number ID of the most recently dispatched request
---@field last_applied_id number ID of the most recently applied result
---@field callback fun(result: any) Callback to apply results
local AsyncHandler = {}
AsyncHandler.__index = AsyncHandler

--- Create a new AsyncHandler
---@param callback fun(result: any) Callback invoked with results
---@return AsyncHandler
function M.new(callback)
  local self = setmetatable({}, AsyncHandler)
  self.current_id = 0
  self.last_applied_id = 0
  self.callback = callback
  return self
end

--- Dispatch an async operation
--- The callback will only be invoked if this is still the latest request
---@param fn fun(done: fun(result: any)) Async function that calls done() with result
---@return number id The request ID
function AsyncHandler:dispatch(fn)
  self.current_id = self.current_id + 1
  local id = self.current_id

  fn(function(result)
    -- Only apply if this is still the latest request
    -- and hasn't been superseded by a newer completed request
    if id == self.current_id and id > self.last_applied_id then
      self.last_applied_id = id
      self.callback(result)
    end
  end)

  return id
end

--- Cancel all pending requests
--- Future results from already-dispatched requests will be ignored
function AsyncHandler:cancel()
  self.last_applied_id = self.current_id
end

--- Check if there are pending requests
---@return boolean
function AsyncHandler:is_pending()
  return self.last_applied_id < self.current_id
end

--- Get the current request ID
---@return number
function AsyncHandler:get_current_id()
  return self.current_id
end

------------------
-- Debounce utility
------------------

---@class DebouncedFunction
---@field timer any Timer handle
---@field delay number Delay in milliseconds
---@field fn function Function to debounce
local DebouncedFunction = {}
DebouncedFunction.__index = DebouncedFunction

--- Create a debounced function
---@param fn function Function to debounce
---@param delay number Delay in milliseconds
---@return DebouncedFunction
function M.debounce(fn, delay)
  local self = setmetatable({}, DebouncedFunction)
  self.timer = nil
  self.delay = delay
  self.fn = fn
  return self
end

--- Call the debounced function
--- Resets the timer on each call
function DebouncedFunction:call(...)
  local args = { ... }

  if self.timer then
    vim.fn.timer_stop(self.timer)
  end

  self.timer = vim.fn.timer_start(self.delay, function()
    self.timer = nil
    self.fn(unpack(args))
  end)
end

--- Cancel any pending call
function DebouncedFunction:cancel()
  if self.timer then
    vim.fn.timer_stop(self.timer)
    self.timer = nil
  end
end

------------------
-- Throttle utility
------------------

---@class ThrottledFunction
---@field last_call number Last call timestamp
---@field delay number Minimum delay between calls
---@field fn function Function to throttle
---@field pending_args any[] Arguments from last throttled call
---@field timer any Timer for trailing call
local ThrottledFunction = {}
ThrottledFunction.__index = ThrottledFunction

--- Create a throttled function
---@param fn function Function to throttle
---@param delay number Minimum delay between calls in milliseconds
---@param trailing? boolean Whether to call with latest args after delay (default: true)
---@return ThrottledFunction
function M.throttle(fn, delay, trailing)
  local self = setmetatable({}, ThrottledFunction)
  self.last_call = 0
  self.delay = delay
  self.fn = fn
  self.pending_args = nil
  self.timer = nil
  self.trailing = trailing ~= false -- default true
  return self
end

--- Call the throttled function
function ThrottledFunction:call(...)
  local now = vim.loop.now()
  local elapsed = now - self.last_call

  if elapsed >= self.delay then
    -- Enough time has passed, call immediately
    self.last_call = now
    self.pending_args = nil
    if self.timer then
      vim.fn.timer_stop(self.timer)
      self.timer = nil
    end
    self.fn(...)
  elseif self.trailing then
    -- Store args for trailing call
    self.pending_args = { ... }

    -- Set up trailing call if not already scheduled
    if not self.timer then
      local remaining = self.delay - elapsed
      self.timer = vim.fn.timer_start(remaining, function()
        self.timer = nil
        if self.pending_args then
          self.last_call = vim.loop.now()
          local args = self.pending_args
          self.pending_args = nil
          self.fn(unpack(args))
        end
      end)
    end
  end
end

--- Cancel any pending trailing call
function ThrottledFunction:cancel()
  self.pending_args = nil
  if self.timer then
    vim.fn.timer_stop(self.timer)
    self.timer = nil
  end
end

return M
