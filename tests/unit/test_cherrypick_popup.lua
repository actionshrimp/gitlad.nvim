local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Cherry-pick popup builder tests
T["cherrypick popup"] = MiniTest.new_set()

T["cherrypick popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as cherrypick.lua (normal mode)
  local data = popup
    .builder()
    :name("Cherry-pick")
    :switch("x", "x", "Add 'cherry picked from' reference")
    :switch("e", "edit", "Edit commit message")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("f", "ff", "Attempt fast-forward if possible")
    :build()

  eq(data.name, "Cherry-pick")
  eq(#data.switches, 4)
  eq(data.switches[1].key, "x")
  eq(data.switches[1].cli, "x")
  eq(data.switches[2].key, "e")
  eq(data.switches[2].cli, "edit")
  eq(data.switches[3].key, "s")
  eq(data.switches[3].cli, "signoff")
  eq(data.switches[4].key, "f")
  eq(data.switches[4].cli, "ff")
end

T["cherrypick popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("x", "x", "Add reference", { enabled = true, cli_prefix = "-" })
    :switch("e", "edit", "Edit")
    :switch("s", "signoff", "Sign", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 2)
  eq(args[1], "-x")
  eq(args[2], "--signoff")
end

T["cherrypick popup"]["get_arguments returns no args when no switches enabled"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():switch("x", "x", "Add reference"):switch("e", "edit", "Edit"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["cherrypick popup"]["creates actions for normal mode with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local pick_called = false
  local apply_called = false

  local data = popup
    .builder()
    :name("Cherry-pick")
    :group_heading("Cherry-pick")
    :action("A", "Pick", function()
      pick_called = true
    end)
    :action("a", "Apply (no commit)", function()
      apply_called = true
    end)
    :build()

  -- 1 heading + 2 actions
  eq(#data.actions, 3)
  -- Heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Cherry-pick")
  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "A")
  eq(data.actions[2].description, "Pick")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "a")
  eq(data.actions[3].description, "Apply (no commit)")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(pick_called, true)

  data.actions[3].callback(data)
  eq(apply_called, true)
end

T["cherrypick popup"]["creates actions for in-progress mode with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local continue_called = false
  local skip_called = false
  local abort_called = false

  local data = popup
    .builder()
    :name("Cherry-pick (in progress: abc1234)")
    :group_heading("Sequencer")
    :action("A", "Continue", function()
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
  eq(data.actions[2].key, "A")
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

T["cherrypick popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data =
    popup.builder():switch("x", "x", "Add reference"):switch("s", "signoff", "Sign"):build()

  -- Initially not enabled
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, false)

  -- Toggle first switch
  data:toggle_switch("x")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Toggle second switch
  data:toggle_switch("s")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, true)

  -- Toggle first switch off
  data:toggle_switch("x")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, true)
end

T["cherrypick popup"]["mainline option works correctly"] = function()
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
