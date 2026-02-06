local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- AM popup builder tests
T["am popup"] = MiniTest.new_set()

T["am popup"]["creates normal mode popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Apply patches")
    :switch("3", "3way", "Fall back on 3-way merge")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("k", "keep", "Keep subject line intact")
    :switch("b", "keep-non-patch", "Limit email cruft removal")
    :switch("d", "committer-date-is-author-date", "Use author date as committer date")
    :switch("t", "ignore-date", "Use current time as author date")
    :build()

  eq(data.name, "Apply patches")
  eq(#data.switches, 6)
  eq(data.switches[1].key, "3")
  eq(data.switches[1].cli, "3way")
  eq(data.switches[2].key, "s")
  eq(data.switches[2].cli, "signoff")
  eq(data.switches[3].key, "k")
  eq(data.switches[3].cli, "keep")
  eq(data.switches[4].key, "b")
  eq(data.switches[4].cli, "keep-non-patch")
  eq(data.switches[5].key, "d")
  eq(data.switches[5].cli, "committer-date-is-author-date")
  eq(data.switches[6].key, "t")
  eq(data.switches[6].cli, "ignore-date")
end

T["am popup"]["creates normal mode popup with correct actions"] = function()
  local popup = require("gitlad.ui.popup")

  local apply_called = false
  local maildir_called = false

  local data = popup
    .builder()
    :name("Apply patches")
    :group_heading("Apply")
    :action("w", "Apply patch file(s)", function()
      apply_called = true
    end)
    :action("m", "Apply maildir", function()
      maildir_called = true
    end)
    :build()

  -- 1 heading + 2 actions = 3
  eq(#data.actions, 3)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Apply")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "w")
  eq(data.actions[2].description, "Apply patch file(s)")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "m")
  eq(data.actions[3].description, "Apply maildir")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(apply_called, true)

  data.actions[3].callback(data)
  eq(maildir_called, true)
end

T["am popup"]["creates in-progress popup with correct actions"] = function()
  local popup = require("gitlad.ui.popup")

  local continue_called = false
  local skip_called = false
  local abort_called = false

  local data = popup
    .builder()
    :name("Apply patches (in progress: 2/5)")
    :group_heading("Sequencer")
    :action("w", "Continue", function()
      continue_called = true
    end)
    :action("s", "Skip", function()
      skip_called = true
    end)
    :action("a", "Abort", function()
      abort_called = true
    end)
    :build()

  eq(data.name, "Apply patches (in progress: 2/5)")

  -- 1 heading + 3 actions = 4
  eq(#data.actions, 4)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Sequencer")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "w")
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

T["am popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("3", "3way", "Fall back on 3-way merge", { enabled = true })
    :switch("s", "signoff", "Add Signed-off-by line", { enabled = true })
    :switch("k", "keep", "Keep subject line intact")
    :build()

  local args = data:get_arguments()
  eq(#args, 2)
  eq(args[1], "--3way")
  eq(args[2], "--signoff")
end

T["am popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data =
    popup.builder():switch("3", "3way", "3-way merge"):switch("s", "signoff", "Sign"):build()

  -- Initially not enabled
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, false)

  -- Toggle first switch
  data:toggle_switch("3")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Toggle second switch
  data:toggle_switch("s")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, true)

  -- Toggle first switch off
  data:toggle_switch("3")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, true)
end

return T
