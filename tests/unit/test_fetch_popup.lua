local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Fetch popup builder tests
T["fetch popup"] = MiniTest.new_set()

T["fetch popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as fetch.lua
  local data = popup
    .builder()
    :name("Fetch")
    :switch("P", "prune", "Prune deleted branches")
    :switch("t", "tags", "Fetch all tags")
    :build()

  eq(data.name, "Fetch")
  eq(#data.switches, 2)
  eq(data.switches[1].key, "P")
  eq(data.switches[1].cli, "prune")
  eq(data.switches[2].key, "t")
  eq(data.switches[2].cli, "tags")
end

T["fetch popup"]["creates popup with correct options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():name("Fetch"):option("r", "remote", "origin", "Remote"):build()

  eq(#data.options, 1)
  eq(data.options[1].key, "r")
  eq(data.options[1].cli, "remote")
  eq(data.options[1].value, "origin")
end

T["fetch popup"]["get_arguments returns enabled prune"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("p", "prune", "Prune", { enabled = true })
    :switch("t", "tags", "Tags")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--prune")
end

T["fetch popup"]["get_arguments returns multiple enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("p", "prune", "Prune", { enabled = true })
    :switch("t", "tags", "Tags", { enabled = true })
    :switch("a", "all", "All", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 3)
  eq(args[1], "--prune")
  eq(args[2], "--tags")
  eq(args[3], "--all")
end

T["fetch popup"]["get_arguments includes remote option with value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("r", "remote", "upstream", "Remote"):build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--remote=upstream")
end

T["fetch popup"]["get_arguments excludes option without value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("r", "remote", "", "Remote"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["fetch popup"]["creates actions correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local fetch_pushremote_called = false
  local fetch_upstream_called = false
  local fetch_elsewhere_called = false
  local fetch_all_called = false

  local data = popup
    .builder()
    :group_heading("Fetch")
    :action("p", "Fetch from pushremote", function()
      fetch_pushremote_called = true
    end)
    :action("u", "Fetch from upstream", function()
      fetch_upstream_called = true
    end)
    :action("e", "Fetch elsewhere", function()
      fetch_elsewhere_called = true
    end)
    :action("a", "Fetch all remotes", function()
      fetch_all_called = true
    end)
    :build()

  -- 1 heading + 4 actions
  eq(#data.actions, 5)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Fetch")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "p")
  eq(data.actions[2].description, "Fetch from pushremote")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "u")
  eq(data.actions[3].description, "Fetch from upstream")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "e")
  eq(data.actions[4].description, "Fetch elsewhere")
  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "a")
  eq(data.actions[5].description, "Fetch all remotes")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(fetch_pushremote_called, true)

  data.actions[3].callback(data)
  eq(fetch_upstream_called, true)

  data.actions[4].callback(data)
  eq(fetch_elsewhere_called, true)

  data.actions[5].callback(data)
  eq(fetch_all_called, true)
end

return T
