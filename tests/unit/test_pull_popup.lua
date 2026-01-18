local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Pull popup builder tests
T["pull popup"] = MiniTest.new_set()

T["pull popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as pull.lua
  local data = popup
    .builder()
    :name("Pull")
    :switch("r", "rebase", "Rebase instead of merge")
    :switch("f", "ff-only", "Fast-forward only")
    :switch("n", "no-ff", "Create merge commit")
    :switch("a", "autostash", "Autostash before pull")
    :build()

  eq(data.name, "Pull")
  eq(#data.switches, 4)
  eq(data.switches[1].key, "r")
  eq(data.switches[1].cli, "rebase")
  eq(data.switches[2].key, "f")
  eq(data.switches[2].cli, "ff-only")
  eq(data.switches[3].key, "n")
  eq(data.switches[3].cli, "no-ff")
  eq(data.switches[4].key, "a")
  eq(data.switches[4].cli, "autostash")
end

T["pull popup"]["creates popup with correct options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():name("Pull"):option("o", "remote", "origin", "Remote"):build()

  eq(#data.options, 1)
  eq(data.options[1].key, "o")
  eq(data.options[1].cli, "remote")
  eq(data.options[1].value, "origin")
end

T["pull popup"]["get_arguments returns enabled rebase"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("r", "rebase", "Rebase", { enabled = true })
    :switch("f", "ff-only", "FF only")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--rebase")
end

T["pull popup"]["get_arguments returns multiple enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("r", "rebase", "Rebase", { enabled = true })
    :switch("a", "autostash", "Autostash", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 2)
  eq(args[1], "--rebase")
  eq(args[2], "--autostash")
end

T["pull popup"]["get_arguments includes remote option with value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("o", "remote", "upstream", "Remote"):build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--remote=upstream")
end

T["pull popup"]["get_arguments excludes option without value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("o", "remote", "", "Remote"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["pull popup"]["creates actions correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local pull_pushremote_called = false
  local pull_upstream_called = false
  local pull_elsewhere_called = false

  local data = popup
    .builder()
    :group_heading("Pull")
    :action("p", "Pull from pushremote", function()
      pull_pushremote_called = true
    end)
    :action("u", "Pull from upstream", function()
      pull_upstream_called = true
    end)
    :action("e", "Pull elsewhere", function()
      pull_elsewhere_called = true
    end)
    :build()

  -- 1 heading + 3 actions
  eq(#data.actions, 4)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Pull")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "p")
  eq(data.actions[2].description, "Pull from pushremote")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "u")
  eq(data.actions[3].description, "Pull from upstream")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "e")
  eq(data.actions[4].description, "Pull elsewhere")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(pull_pushremote_called, true)

  data.actions[3].callback(data)
  eq(pull_upstream_called, true)

  data.actions[4].callback(data)
  eq(pull_elsewhere_called, true)
end

return T
