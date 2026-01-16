-- Tests for gitlad.config module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset config before each test
      require("gitlad.config").reset()
    end,
  },
})

T["config"] = MiniTest.new_set()

T["config"]["returns defaults when setup not called"] = function()
  local config = require("gitlad.config")
  local cfg = config.get()

  eq(cfg.refresh_on_focus, true)
  eq(cfg.watch_gitdir, true)
  expect.equality(type(cfg.signs), "table")
end

T["config"]["merges user options with defaults"] = function()
  local config = require("gitlad.config")
  config.setup({
    refresh_on_focus = false,
  })

  local cfg = config.get()
  eq(cfg.refresh_on_focus, false)
  eq(cfg.watch_gitdir, true) -- Still default
end

T["config"]["deep merges nested options"] = function()
  local config = require("gitlad.config")
  config.setup({
    signs = {
      staged = "S",
    },
  })

  local cfg = config.get()
  eq(cfg.signs.staged, "S")
  eq(cfg.signs.unstaged, "○") -- Still default
end

T["config"]["reset clears configuration"] = function()
  local config = require("gitlad.config")
  config.setup({ refresh_on_focus = false })

  config.reset()
  local cfg = config.get()
  eq(cfg.refresh_on_focus, true) -- Back to default
end

return T
