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

  expect.equality(type(cfg.signs), "table")
  expect.equality(type(cfg.commit_editor), "table")
  expect.equality(type(cfg.worktree), "table")
  expect.equality(type(cfg.status), "table")
end

T["config"]["merges user options with defaults"] = function()
  local config = require("gitlad.config")
  config.setup({
    commit_editor = {
      split = "replace",
    },
  })

  local cfg = config.get()
  eq(cfg.commit_editor.split, "replace")
  eq(cfg.signs.staged, "●") -- Still default
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
  config.setup({ commit_editor = { split = "replace" } })

  config.reset()
  local cfg = config.get()
  eq(cfg.commit_editor.split, "above") -- Back to default
end

T["config"]["has worktree defaults"] = function()
  local config = require("gitlad.config")
  local cfg = config.get()

  expect.equality(type(cfg.worktree), "table")
  eq(cfg.worktree.directory_strategy, "sibling")
end

T["config"]["allows configuring worktree strategy"] = function()
  local config = require("gitlad.config")
  config.setup({
    worktree = {
      directory_strategy = "prompt",
    },
  })

  local cfg = config.get()
  eq(cfg.worktree.directory_strategy, "prompt")
end

return T
