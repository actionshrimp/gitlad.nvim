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

-- Stale indicator (warning symbol to prompt manual refresh)
local STALE_ICON = "⚠"

-- Animation interval in milliseconds
local FRAME_INTERVAL_MS = 80

---@class Spinner
---@field private _frame number Current frame index
---@field private _timer uv_timer_t|nil Active timer
---@field private _callback fun()|nil Callback to invoke on each frame
---@field private _spinning boolean Whether currently spinning
---@field private _stale boolean Whether the view is stale (git state changed externally)
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
  self._stale = false
  return self
end

--- Get the current display character
--- Priority: spinning > stale > idle
---@return string
function Spinner:get_char()
  if self._spinning then
    return SPINNER_FRAMES[self._frame]
  elseif self._stale then
    return STALE_ICON
  else
    return PLACEHOLDER
  end
end

--- Get the current display text with label
--- Priority: spinning > stale > idle
---@return string
function Spinner:get_display()
  if self._spinning then
    return SPINNER_FRAMES[self._frame] .. " Refreshing..."
  elseif self._stale then
    return STALE_ICON .. " Stale (gr to refresh)"
  else
    return PLACEHOLDER .. " Idle"
  end
end

--- Check if the spinner is currently active
---@return boolean
function Spinner:is_spinning()
  return self._spinning
end

--- Check if the view is stale
---@return boolean
function Spinner:is_stale()
  return self._stale
end

--- Mark the view as stale (git state changed externally)
function Spinner:set_stale()
  self._stale = true
end

--- Clear the stale flag (typically after manual refresh)
function Spinner:clear_stale()
  self._stale = false
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
