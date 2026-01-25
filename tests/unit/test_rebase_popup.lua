local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Rebase popup builder tests
T["rebase popup"] = MiniTest.new_set()

T["rebase popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as rebase.lua (normal mode)
  local data = popup
    .builder()
    :name("Rebase")
    :switch("A", "autostash", "Autostash", { enabled = true })
    :switch("k", "keep-empty", "Keep empty commits")
    :switch("a", "autosquash", "Autosquash")
    :switch("i", "interactive", "Interactive")
    :build()

  eq(data.name, "Rebase")
  eq(#data.switches, 4)
  eq(data.switches[1].key, "A")
  eq(data.switches[1].cli, "autostash")
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].key, "k")
  eq(data.switches[2].cli, "keep-empty")
  eq(data.switches[2].enabled, false)
  eq(data.switches[3].key, "a")
  eq(data.switches[3].cli, "autosquash")
  eq(data.switches[4].key, "i")
  eq(data.switches[4].cli, "interactive")
end

T["rebase popup"]["get_arguments returns autostash by default"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("A", "autostash", "Autostash", { enabled = true })
    :switch("k", "keep-empty", "Keep empty commits")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--autostash")
end

T["rebase popup"]["get_arguments returns multiple enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("A", "autostash", "Autostash", { enabled = true })
    :switch("k", "keep-empty", "Keep empty", { enabled = true })
    :switch("a", "autosquash", "Autosquash", { enabled = true })
    :switch("i", "interactive", "Interactive")
    :build()

  local args = data:get_arguments()
  eq(#args, 3)
  eq(args[1], "--autostash")
  eq(args[2], "--keep-empty")
  eq(args[3], "--autosquash")
end

T["rebase popup"]["creates normal mode actions correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local rebase_pushremote_called = false
  local rebase_upstream_called = false
  local rebase_elsewhere_called = false

  local data = popup
    .builder()
    :group_heading("Rebase main onto")
    :action("p", "pushremote", function()
      rebase_pushremote_called = true
    end)
    :action("u", "upstream", function()
      rebase_upstream_called = true
    end)
    :action("e", "elsewhere", function()
      rebase_elsewhere_called = true
    end)
    :build()

  -- 1 heading + 3 actions
  eq(#data.actions, 4)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Rebase main onto")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "p")
  eq(data.actions[2].description, "pushremote")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "u")
  eq(data.actions[3].description, "upstream")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "e")
  eq(data.actions[4].description, "elsewhere")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(rebase_pushremote_called, true)

  data.actions[3].callback(data)
  eq(rebase_upstream_called, true)

  data.actions[4].callback(data)
  eq(rebase_elsewhere_called, true)
end

T["rebase popup"]["creates in-progress mode actions correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local continue_called = false
  local skip_called = false
  local abort_called = false

  local data = popup
    .builder()
    :group_heading("Actions")
    :action("r", "Continue", function()
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
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Actions")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "r")
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

T["rebase popup"]["_include_commit_in_rebase appends ^ to include selected commit"] = function()
  local rebase = require("gitlad.popups.rebase")

  -- Git rebase -i <commit> rebases commits AFTER the specified commit.
  -- To include the commit itself, we need to use <commit>^ (parent).
  -- This matches magit's magit-rebase-interactive-include-selected behavior.
  eq(rebase._include_commit_in_rebase("abc123"), "abc123^")
  eq(rebase._include_commit_in_rebase("HEAD~3"), "HEAD~3^")
  eq(rebase._include_commit_in_rebase("feature-branch"), "feature-branch^")
end

T["rebase popup"]["toggle_switch works correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("A", "autostash", "Autostash", { enabled = true })
    :switch("i", "interactive", "Interactive")
    :build()

  -- Initially autostash is enabled, interactive is disabled
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Toggle autostash off
  data:toggle_switch("A")
  eq(data.switches[1].enabled, false)

  -- Toggle interactive on
  data:toggle_switch("i")
  eq(data.switches[2].enabled, true)

  -- Verify get_arguments reflects the changes
  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--interactive")
end

return T
