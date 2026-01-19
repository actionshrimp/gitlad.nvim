---@mod gitlad.ui.utils.spinner Animated spinner for status indicators
---@brief [[
--- Provides an animated unicode spinner for indicating loading/refreshing states.
--- Uses braille dot patterns for a smooth TUI-style animation.
---@brief ]]

local M = {}

-- Braille dot spinner frames (smooth rotation effect)
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Placeholder shown when not spinning (subtle dot to indicate the line's purpose)
local PLACEHOLDER = "·"

-- Animation interval in milliseconds
local FRAME_INTERVAL_MS = 80

---@class Spinner
---@field private _frame number Current frame index
---@field private _timer uv_timer_t|nil Active timer
---@field private _callback fun()|nil Callback to invoke on each frame
---@field private _spinning boolean Whether currently spinning
local Spinner = {}
Spinner.__index = Spinner

--- Create a new spinner instance
---@return Spinner
function M.new()
  local self = setmetatable({}, Spinner)
  self._frame = 1
  self._timer = nil
  self._callback = nil
  self._spinning = false
  return self
end

--- Get the current display character
---@return string
function Spinner:get_char()
  if self._spinning then
    return SPINNER_FRAMES[self._frame]
  else
    return PLACEHOLDER
  end
end

--- Get the current display text with label
---@return string
function Spinner:get_display()
  if self._spinning then
    return SPINNER_FRAMES[self._frame] .. " Refreshing..."
  else
    return PLACEHOLDER
  end
end

--- Check if the spinner is currently active
---@return boolean
function Spinner:is_spinning()
  return self._spinning
end

--- Start the spinner animation
---@param callback fun() Function to call on each frame (typically to trigger re-render)
function Spinner:start(callback)
  if self._spinning then
    return -- Already spinning
  end

  self._spinning = true
  self._frame = 1
  self._callback = callback

  -- Create timer for animation
  local timer = vim.uv.new_timer()
  self._timer = timer

  timer:start(
    0,
    FRAME_INTERVAL_MS,
    vim.schedule_wrap(function()
      if not self._spinning then
        return
      end

      -- Advance to next frame
      self._frame = (self._frame % #SPINNER_FRAMES) + 1

      -- Invoke callback to trigger re-render
      if self._callback then
        self._callback()
      end
    end)
  )
end

--- Stop the spinner animation
function Spinner:stop()
  if not self._spinning then
    return -- Already stopped
  end

  self._spinning = false

  if self._timer then
    self._timer:stop()
    self._timer:close()
    self._timer = nil
  end

  self._callback = nil
  self._frame = 1
end

--- Clean up resources (call when done with spinner)
function Spinner:destroy()
  self:stop()
end

return M
