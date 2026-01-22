local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Merge popup builder tests
T["merge popup"] = MiniTest.new_set()

T["merge popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as merge.lua (normal mode)
  local data = popup
    .builder()
    :name("Merge")
    :switch("f", "ff-only", "Fast-forward only")
    :switch("n", "no-ff", "Create merge commit even if fast-forward possible")
    :build()

  eq(data.name, "Merge")
  eq(#data.switches, 2)
  eq(data.switches[1].key, "f")
  eq(data.switches[1].cli, "ff-only")
  eq(data.switches[2].key, "n")
  eq(data.switches[2].cli, "no-ff")
end

T["merge popup"]["get_arguments returns enabled switches with double dash"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only", { enabled = true })
    :switch("n", "no-ff", "Create merge commit")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--ff-only")
end

T["merge popup"]["get_arguments returns no args when no switches enabled"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only")
    :switch("n", "no-ff", "Create merge commit")
    :build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["merge popup"]["creates actions for normal mode with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local merge_called = false
  local edit_called = false
  local no_commit_called = false
  local squash_called = false

  local data = popup
    .builder()
    :name("Merge")
    :group_heading("Merge")
    :action("m", "Merge", function()
      merge_called = true
    end)
    :action("e", "Merge, edit message", function()
      edit_called = true
    end)
    :action("n", "Merge, don't commit", function()
      no_commit_called = true
    end)
    :action("s", "Squash merge", function()
      squash_called = true
    end)
    :build()

  -- 1 heading + 4 actions
  eq(#data.actions, 5)
  -- Heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Merge")
  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "m")
  eq(data.actions[2].description, "Merge")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "e")
  eq(data.actions[3].description, "Merge, edit message")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "n")
  eq(data.actions[4].description, "Merge, don't commit")
  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "s")
  eq(data.actions[5].description, "Squash merge")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(merge_called, true)

  data.actions[3].callback(data)
  eq(edit_called, true)

  data.actions[4].callback(data)
  eq(no_commit_called, true)

  data.actions[5].callback(data)
  eq(squash_called, true)
end

T["merge popup"]["creates actions for in-progress mode with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local commit_called = false
  local abort_called = false

  local data = popup
    .builder()
    :name("Merge (in progress: abc1234)")
    :group_heading("Actions")
    :action("m", "Commit merge", function()
      commit_called = true
    end)
    :action("a", "Abort merge", function()
      abort_called = true
    end)
    :build()

  -- 1 heading + 2 actions
  eq(#data.actions, 3)
  -- Heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Actions")
  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "m")
  eq(data.actions[2].description, "Commit merge")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "a")
  eq(data.actions[3].description, "Abort merge")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(commit_called, true)

  data.actions[3].callback(data)
  eq(abort_called, true)
end

T["merge popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only")
    :switch("n", "no-ff", "No fast-forward")
    :build()

  -- Initially not enabled
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, false)

  -- Toggle first switch
  data:toggle_switch("f")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Toggle second switch
  data:toggle_switch("n")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, true)

  -- Toggle first switch off
  data:toggle_switch("f")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, true)
end

T["merge popup"]["ff-only and no-ff switches produce correct args"] = function()
  local popup = require("gitlad.ui.popup")

  -- Test ff-only
  local data1 = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only", { enabled = true })
    :switch("n", "no-ff", "No fast-forward")
    :build()

  local args1 = data1:get_arguments()
  eq(#args1, 1)
  eq(args1[1], "--ff-only")

  -- Test no-ff
  local data2 = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only")
    :switch("n", "no-ff", "No fast-forward", { enabled = true })
    :build()

  local args2 = data2:get_arguments()
  eq(#args2, 1)
  eq(args2[1], "--no-ff")
end

return T
