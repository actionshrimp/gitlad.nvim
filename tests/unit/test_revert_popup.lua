local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Revert popup builder tests
T["revert popup"] = MiniTest.new_set()

T["revert popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as revert.lua (normal mode)
  local data = popup
    .builder()
    :name("Revert")
    :switch("e", "edit", "Edit commit message", { enabled = true })
    :switch("E", "no-edit", "Don't edit commit message")
    :switch("s", "signoff", "Add Signed-off-by line")
    :build()

  eq(data.name, "Revert")
  eq(#data.switches, 3)
  eq(data.switches[1].key, "e")
  eq(data.switches[1].cli, "edit")
  eq(data.switches[1].enabled, true) -- --edit enabled by default
  eq(data.switches[2].key, "E")
  eq(data.switches[2].cli, "no-edit")
  eq(data.switches[3].key, "s")
  eq(data.switches[3].cli, "signoff")
end

T["revert popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("e", "edit", "Edit", { enabled = true })
    :switch("E", "no-edit", "No edit")
    :switch("s", "signoff", "Sign", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 2)
  eq(args[1], "--edit")
  eq(args[2], "--signoff")
end

T["revert popup"]["get_arguments returns no args when no switches enabled"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():switch("e", "edit", "Edit"):switch("s", "signoff", "Sign"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["revert popup"]["creates actions for normal mode with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local revert_called = false
  local revert_no_commit_called = false

  local data = popup
    .builder()
    :name("Revert")
    :group_heading("Revert")
    :action("V", "Revert", function()
      revert_called = true
    end)
    :action("v", "Revert changes (no commit)", function()
      revert_no_commit_called = true
    end)
    :build()

  -- 1 heading + 2 actions
  eq(#data.actions, 3)
  -- Heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Revert")
  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "V")
  eq(data.actions[2].description, "Revert")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "v")
  eq(data.actions[3].description, "Revert changes (no commit)")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(revert_called, true)

  data.actions[3].callback(data)
  eq(revert_no_commit_called, true)
end

T["revert popup"]["creates actions for in-progress mode with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local continue_called = false
  local skip_called = false
  local abort_called = false

  local data = popup
    .builder()
    :name("Revert (in progress: abc1234)")
    :group_heading("Sequencer")
    :action("V", "Continue", function()
      continue_called = true
    end)
    :action("s", "Skip", function()
      skip_called = true
    end)
    :action("a", "Abort", function()
      abort_called = true
    end)
    :build()

  -- 1 heading + 3 actions
  eq(#data.actions, 4)
  -- Heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Sequencer")
  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "V")
  eq(data.actions[2].description, "Continue")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "s")
  eq(data.actions[3].description, "Skip")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "a")
  eq(data.actions[4].description, "Abort")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(continue_called, true)

  data.actions[3].callback(data)
  eq(skip_called, true)

  data.actions[4].callback(data)
  eq(abort_called, true)
end

T["revert popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("e", "edit", "Edit", { enabled = true })
    :switch("E", "no-edit", "No edit")
    :build()

  -- Initially edit enabled, no-edit disabled
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Toggle edit off
  data:toggle_switch("e")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, false)

  -- Toggle no-edit on
  data:toggle_switch("E")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, true)
end

T["revert popup"]["mainline option works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :option("m", "mainline", "", "Mainline parent number (for merge commits)")
    :build()

  eq(#data.options, 1)
  eq(data.options[1].key, "m")
  eq(data.options[1].cli, "mainline")
  eq(data.options[1].value, "")

  -- Set option value
  data:set_option("m", "1")
  eq(data.options[1].value, "1")

  -- Get arguments should include mainline
  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--mainline=1")
end

return T
