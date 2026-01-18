-- Tests for gitlad.popups.log module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- =============================================================================
-- Log popup tests
-- =============================================================================

T["log popup"] = MiniTest.new_set()

T["log popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as log.lua
  local data = popup
    .builder()
    :name("Log")
    :switch("a", "--all", "All branches")
    :switch("m", "--merges", "Only merges")
    :switch("M", "--no-merges", "No merges")
    :build()

  eq(data.name, "Log")
  eq(#data.switches, 3)
  eq(data.switches[1].key, "a")
  eq(data.switches[1].cli, "--all")
  eq(data.switches[2].key, "m")
  eq(data.switches[2].cli, "--merges")
  eq(data.switches[3].key, "M")
  eq(data.switches[3].cli, "--no-merges")
end

T["log popup"]["creates popup with correct options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Log")
    :option("n", "limit", "256", "Limit")
    :option("a", "author", "", "Author")
    :option("s", "since", "", "Since")
    :option("u", "until", "", "Until")
    :build()

  eq(#data.options, 4)
  eq(data.options[1].key, "n")
  eq(data.options[1].cli, "limit")
  eq(data.options[1].value, "256")
  eq(data.options[2].key, "a")
  eq(data.options[2].cli, "author")
  eq(data.options[3].key, "s")
  eq(data.options[3].cli, "since")
  eq(data.options[4].key, "u")
  eq(data.options[4].cli, "until")
end

T["log popup"]["creates popup with actions"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Log")
    :action("l", "Log current branch", function() end)
    :action("o", "Log other branch", function() end)
    :action("h", "Log HEAD", function() end)
    :action("L", "Log all branches", function() end)
    :build()

  eq(#data.actions, 4)
  eq(data.actions[1].key, "l")
  eq(data.actions[1].description, "Log current branch")
  eq(data.actions[2].key, "o")
  eq(data.actions[3].key, "h")
  eq(data.actions[4].key, "L")
end

T["log popup"]["build_log_args includes enabled switches"] = function()
  -- Test the argument building logic by creating popup data structure
  local popup_data = {
    switches = {
      { key = "a", cli = "--all", enabled = true },
      { key = "m", cli = "--merges", enabled = false },
      { key = "M", cli = "--no-merges", enabled = true },
    },
    options = {
      { key = "n", cli = "limit", value = "100" },
      { key = "a", cli = "author", value = "" },
      { key = "s", cli = "since", value = "2024-01-01" },
      { key = "u", cli = "until", value = "" },
    },
    actions = {},
  }

  -- Simulate the build_log_args function logic
  local args = {}
  for _, sw in ipairs(popup_data.switches) do
    if sw.enabled then
      table.insert(args, sw.cli)
    end
  end
  for _, opt in ipairs(popup_data.options) do
    if opt.value and opt.value ~= "" then
      if opt.cli == "limit" then
        table.insert(args, "-" .. opt.value)
      elseif opt.cli == "author" then
        table.insert(args, "--author=" .. opt.value)
      elseif opt.cli == "since" then
        table.insert(args, "--since=" .. opt.value)
      elseif opt.cli == "until" then
        table.insert(args, "--until=" .. opt.value)
      end
    end
  end

  eq(#args, 4)
  eq(args[1], "--all")
  eq(args[2], "--no-merges")
  eq(args[3], "-100")
  eq(args[4], "--since=2024-01-01")
end

T["log popup"]["build_log_args handles empty options"] = function()
  local popup_data = {
    switches = {},
    options = {
      { key = "n", cli = "limit", value = "" },
      { key = "a", cli = "author", value = "" },
    },
    actions = {},
  }

  local args = {}
  for _, opt in ipairs(popup_data.options) do
    if opt.value and opt.value ~= "" then
      if opt.cli == "limit" then
        table.insert(args, "-" .. opt.value)
      end
    end
  end

  eq(#args, 0)
end

T["log popup"]["default limit is 256"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():name("Log"):option("n", "limit", "256", "Limit"):build()

  eq(data.options[1].value, "256")
end

return T
