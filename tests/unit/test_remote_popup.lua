local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Remote popup builder tests
T["remote popup"] = MiniTest.new_set()

T["remote popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as remote.lua
  local data = popup.builder():name("Remotes"):switch("f", "fetch", "Fetch after add"):build()

  eq(data.name, "Remotes")
  eq(#data.switches, 1)
  eq(data.switches[1].key, "f")
  eq(data.switches[1].cli, "fetch")
  eq(data.switches[1].description, "Fetch after add")
end

T["remote popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():switch("f", "fetch", "Fetch after add", { enabled = true }):build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--fetch")
end

T["remote popup"]["get_arguments returns no args when no switches enabled"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():switch("f", "fetch", "Fetch after add"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["remote popup"]["creates actions with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local add_called = false
  local rename_called = false
  local remove_called = false
  local prune_called = false
  local fetch_prune_called = false

  local data = popup
    .builder()
    :name("Remotes")
    :group_heading("Actions")
    :columns(3)
    :action("a", "Add", function()
      add_called = true
    end)
    :action("r", "Rename", function()
      rename_called = true
    end)
    :action("x", "Remove", function()
      remove_called = true
    end)
    :group_heading("Prune")
    :action("p", "Prune stale branches", function()
      prune_called = true
    end)
    :action("P", "Prune stale refspecs", function()
      fetch_prune_called = true
    end)
    :build()

  -- 2 headings + 5 actions
  eq(#data.actions, 7)

  -- First heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Actions")

  -- Actions in first group
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "a")
  eq(data.actions[2].description, "Add")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "r")
  eq(data.actions[3].description, "Rename")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "x")
  eq(data.actions[4].description, "Remove")

  -- Second heading
  eq(data.actions[5].type, "heading")
  eq(data.actions[5].text, "Prune")

  -- Prune actions
  eq(data.actions[6].type, "action")
  eq(data.actions[6].key, "p")
  eq(data.actions[6].description, "Prune stale branches")
  eq(data.actions[7].type, "action")
  eq(data.actions[7].key, "P")
  eq(data.actions[7].description, "Prune stale refspecs")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(add_called, true)

  data.actions[3].callback(data)
  eq(rename_called, true)

  data.actions[4].callback(data)
  eq(remove_called, true)

  data.actions[6].callback(data)
  eq(prune_called, true)

  data.actions[7].callback(data)
  eq(fetch_prune_called, true)
end

T["remote popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():switch("f", "fetch", "Fetch after add"):build()

  -- Initially not enabled
  eq(data.switches[1].enabled, false)

  -- Toggle switch
  data:toggle_switch("f")
  eq(data.switches[1].enabled, true)

  -- Toggle switch off
  data:toggle_switch("f")
  eq(data.switches[1].enabled, false)
end

return T
