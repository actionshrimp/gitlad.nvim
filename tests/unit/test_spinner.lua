local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["spinner"] = MiniTest.new_set()

T["spinner"]["creates new spinner instance"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  expect.no_error(function()
    return s
  end)
  eq(s:is_spinning(), false)
end

T["spinner"]["shows placeholder when not spinning"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  eq(s:get_char(), "·")
  eq(s:get_display(), "· Idle")
end

T["spinner"]["is_spinning returns false initially"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  eq(s:is_spinning(), false)
end

T["spinner"]["start sets spinning to true"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  eq(s:is_spinning(), true)

  -- Clean up
  s:stop()
end

T["spinner"]["stop sets spinning to false"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  eq(s:is_spinning(), true)

  s:stop()
  eq(s:is_spinning(), false)
end

T["spinner"]["get_display shows refreshing when spinning"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  local display = s:get_display()

  -- Should contain "Refreshing"
  eq(display:match("Refreshing") ~= nil, true)

  -- Clean up
  s:stop()
end

T["spinner"]["get_char returns spinner frame when spinning"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  local char = s:get_char()

  -- Should be one of the braille spinner characters
  eq(char:match("[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]") ~= nil, true)

  -- Clean up
  s:stop()
end

T["spinner"]["start is idempotent"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  local callback_count = 0
  local callback = function()
    callback_count = callback_count + 1
  end

  -- Start twice
  s:start(callback)
  s:start(callback)

  eq(s:is_spinning(), true)

  -- Clean up
  s:stop()
end

T["spinner"]["stop is idempotent"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  s:stop()
  s:stop() -- Should not error

  eq(s:is_spinning(), false)
end

T["spinner"]["destroy stops spinner and cleans up"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  eq(s:is_spinning(), true)

  s:destroy()
  eq(s:is_spinning(), false)
end

T["spinner"]["returns placeholder after stop"] = function()
  local spinner = require("gitlad.ui.utils.spinner")
  local s = spinner.new()

  s:start(function() end)
  s:stop()

  eq(s:get_char(), "·")
  eq(s:get_display(), "· Idle")
end

return T
