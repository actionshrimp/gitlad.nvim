local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["output viewer"] = MiniTest.new_set()

T["output viewer"]["opens floating window with title"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test Output" })

  -- Viewer should be open
  eq(viewer:is_open(), true)

  -- Clean up
  viewer:close()
end

T["output viewer"]["opens with command in header"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({
    title = "Commit",
    command = "git commit -m 'test'",
  })

  eq(viewer:is_open(), true)
  viewer:close()
end

T["output viewer"]["appends stdout lines"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  -- Append some lines
  viewer:append("Line 1", false)
  viewer:append("Line 2", false)

  -- Viewer should still be open
  eq(viewer:is_open(), true)

  viewer:close()
end

T["output viewer"]["appends stderr lines"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  -- Append stderr
  viewer:append("Error message", true)

  eq(viewer:is_open(), true)
  viewer:close()
end

T["output viewer"]["marks complete with exit code"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  -- Mark complete with success
  viewer:complete(0)

  -- Viewer should still be open (auto-close is delayed)
  eq(viewer:is_open(), true)

  viewer:close()
end

T["output viewer"]["close cleans up resources"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  viewer:close()
  eq(viewer:is_open(), false)
end

T["output viewer"]["close is idempotent"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  viewer:close()
  viewer:close() -- Should not error
  eq(viewer:is_open(), false)
end

T["output viewer"]["ignores append after complete"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  viewer:append("Before complete", false)
  viewer:complete(0)
  -- This should be ignored
  viewer:append("After complete", false)

  eq(viewer:is_open(), true)
  viewer:close()
end

T["output viewer"]["complete is idempotent"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({ title = "Test" })

  viewer:complete(0)
  viewer:complete(1) -- Should be ignored

  eq(viewer:is_open(), true)
  viewer:close()
end

T["output viewer"]["uses default title when not provided"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.open({})

  eq(viewer:is_open(), true)
  viewer:close()
end

return T
