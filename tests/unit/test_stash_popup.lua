local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Stash popup builder tests
T["stash popup"] = MiniTest.new_set()

T["stash popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as stash.lua
  local data = popup
    .builder()
    :name("Stash")
    :switch("u", "include-untracked", "Include untracked files")
    :switch("a", "all", "Include all files (untracked + ignored)")
    :switch("k", "keep-index", "Keep staged changes in index")
    :build()

  eq(data.name, "Stash")
  eq(#data.switches, 3)
  eq(data.switches[1].key, "u")
  eq(data.switches[1].cli, "include-untracked")
  eq(data.switches[2].key, "a")
  eq(data.switches[2].cli, "all")
  eq(data.switches[3].key, "k")
  eq(data.switches[3].cli, "keep-index")
end

T["stash popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("u", "include-untracked", "Include untracked", { enabled = true })
    :switch("a", "all", "All")
    :switch("k", "keep-index", "Keep index", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 2)
  eq(args[1], "--include-untracked")
  eq(args[2], "--keep-index")
end

T["stash popup"]["get_arguments returns no args when no switches enabled"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("u", "include-untracked", "Include untracked")
    :switch("a", "all", "All")
    :switch("k", "keep-index", "Keep index")
    :build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["stash popup"]["creates actions with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local stash_called = false
  local stash_index_called = false
  local pop_called = false
  local apply_called = false
  local drop_called = false

  local data = popup
    .builder()
    :name("Stash")
    :group_heading("Stash")
    :action("z", "Stash", function()
      stash_called = true
    end)
    :action("i", "Stash index", function()
      stash_index_called = true
    end)
    :group_heading("Use")
    :action("p", "Pop", function()
      pop_called = true
    end)
    :action("a", "Apply", function()
      apply_called = true
    end)
    :action("d", "Drop", function()
      drop_called = true
    end)
    :build()

  -- 2 headings + 5 actions
  eq(#data.actions, 7)
  -- First heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Stash")
  -- Stash actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "z")
  eq(data.actions[2].description, "Stash")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "i")
  eq(data.actions[3].description, "Stash index")
  -- Second heading
  eq(data.actions[4].type, "heading")
  eq(data.actions[4].text, "Use")
  -- Use actions
  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "p")
  eq(data.actions[5].description, "Pop")
  eq(data.actions[6].type, "action")
  eq(data.actions[6].key, "a")
  eq(data.actions[6].description, "Apply")
  eq(data.actions[7].type, "action")
  eq(data.actions[7].key, "d")
  eq(data.actions[7].description, "Drop")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(stash_called, true)

  data.actions[3].callback(data)
  eq(stash_index_called, true)

  data.actions[5].callback(data)
  eq(pop_called, true)

  data.actions[6].callback(data)
  eq(apply_called, true)

  data.actions[7].callback(data)
  eq(drop_called, true)
end

T["stash popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("u", "include-untracked", "Include untracked")
    :switch("k", "keep-index", "Keep index")
    :build()

  -- Initially not enabled
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, false)

  -- Toggle first switch
  data:toggle_switch("u")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Toggle second switch
  data:toggle_switch("k")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, true)

  -- Toggle first switch off
  data:toggle_switch("u")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, true)
end

return T
