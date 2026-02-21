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

-- =============================================================================
-- Lazy Output Viewer
-- =============================================================================

T["lazy output viewer"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset config for each test
      require("gitlad.config").reset()
    end,
  },
})

T["lazy output viewer"]["is_open returns false before any output"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  eq(viewer:is_open(), false)

  viewer:close()
end

T["lazy output viewer"]["opens on first append"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  eq(viewer:is_open(), false)

  viewer:append("Hello from hook", false)

  eq(viewer:is_open(), true)

  viewer:close()
end

T["lazy output viewer"]["does not open on complete(0) with no output"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  viewer:complete(0)

  eq(viewer:is_open(), false)
end

T["lazy output viewer"]["does not open on complete(1) with no output"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  viewer:complete(1)

  eq(viewer:is_open(), false)
end

T["lazy output viewer"]["delegates close to inner viewer"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  viewer:append("line", false)
  eq(viewer:is_open(), true)

  viewer:close()
  eq(viewer:is_open(), false)
end

T["lazy output viewer"]["close is safe when no inner viewer"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  -- Should not error
  viewer:close()
  viewer:close()
  eq(viewer:is_open(), false)
end

T["lazy output viewer"]["delegates complete to inner viewer after append"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  viewer:append("hook output", false)
  eq(viewer:is_open(), true)

  viewer:complete(0)
  -- Auto-close is delayed, so should still be open
  eq(viewer:is_open(), true)

  viewer:close()
end

-- =============================================================================
-- Factory (M.create)
-- =============================================================================

T["output factory"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      require("gitlad.config").reset()
    end,
  },
})

T["output factory"]["returns lazy viewer by default"] = function()
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  -- Lazy viewer: is_open is false before append
  eq(viewer:is_open(), false)

  viewer:close()
end

T["output factory"]["returns immediate viewer when config is always"] = function()
  local config = require("gitlad.config")
  config.setup({ output = { hook_output = "always" } })

  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  -- Always mode: viewer is open immediately
  eq(viewer:is_open(), true)

  viewer:close()
end

T["output factory"]["returns noop viewer when config is never"] = function()
  local config = require("gitlad.config")
  config.setup({ output = { hook_output = "never" } })

  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Test" })

  -- Noop viewer: always reports false
  eq(viewer:is_open(), false)

  -- Should not error
  viewer:append("test", false)
  viewer:complete(0)
  viewer:close()

  eq(viewer:is_open(), false)
end

return T
