local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["worktrunk.detect"] = MiniTest.new_set()

-- Helper: override _executable and restore after
local function with_executable(installed, fn)
  local wt = require("gitlad.worktrunk")
  local orig = wt._executable
  wt._executable = function(name)
    if name == "wt" then
      return installed
    end
    return orig(name)
  end
  fn()
  wt._executable = orig
end

T["worktrunk.detect"]["is_installed returns true when wt is executable"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(true, function()
    eq(wt.is_installed(), true)
  end)
end

T["worktrunk.detect"]["is_installed returns false when wt not in PATH"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(false, function()
    eq(wt.is_installed(), false)
  end)
end

T["worktrunk.detect"]["is_active auto mode: true when wt installed"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(true, function()
    eq(wt.is_active({ worktrunk = "auto" }), true)
  end)
end

T["worktrunk.detect"]["is_active auto mode: false when wt not installed"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(false, function()
    eq(wt.is_active({ worktrunk = "auto" }), false)
  end)
end

T["worktrunk.detect"]["is_active always mode: true regardless of installation"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(false, function()
    -- Suppress the warning notification in tests
    local orig_notify = vim.notify
    vim.notify = function() end
    local result = wt.is_active({ worktrunk = "always" })
    vim.notify = orig_notify
    eq(result, true)
  end)
end

T["worktrunk.detect"]["is_active always mode with wt installed: true"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(true, function()
    eq(wt.is_active({ worktrunk = "always" }), true)
  end)
end

T["worktrunk.detect"]["is_active never mode: false regardless of installation"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(true, function()
    eq(wt.is_active({ worktrunk = "never" }), false)
  end)
end

T["worktrunk.detect"]["is_active never mode when not installed: false"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(false, function()
    eq(wt.is_active({ worktrunk = "never" }), false)
  end)
end

T["worktrunk.detect"]["is_active with nil config defaults to auto behavior"] = function()
  local wt = require("gitlad.worktrunk")
  -- nil config → defaults to "auto"
  with_executable(true, function()
    eq(wt.is_active(nil), true)
  end)
  with_executable(false, function()
    eq(wt.is_active(nil), false)
  end)
end

T["worktrunk.detect"]["is_active with empty config defaults to auto behavior"] = function()
  local wt = require("gitlad.worktrunk")
  with_executable(true, function()
    eq(wt.is_active({}), true)
  end)
end

return T
