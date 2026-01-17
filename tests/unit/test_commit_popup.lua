local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- Commit popup builder tests
T["commit popup"] = MiniTest.new_set()

T["commit popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as commit.lua
  local data = popup
    .builder()
    :name("Commit")
    :switch("a", "all", "Stage all modified and deleted files")
    :switch("e", "allow-empty", "Allow empty commit")
    :switch("v", "verbose", "Show diff of changes to be committed")
    :switch("n", "no-verify", "Disable hooks")
    :build()

  eq(data.name, "Commit")
  eq(#data.switches, 4)
  eq(data.switches[1].key, "a")
  eq(data.switches[1].cli, "all")
  eq(data.switches[2].key, "e")
  eq(data.switches[2].cli, "allow-empty")
  eq(data.switches[3].key, "v")
  eq(data.switches[3].cli, "verbose")
  eq(data.switches[4].key, "n")
  eq(data.switches[4].cli, "no-verify")
end

T["commit popup"]["creates popup with correct options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Commit")
    :option("A", "author", "", "Override the author")
    :option("S", "signoff", "", "Add Signed-off-by trailer", { cli_prefix = "--", separator = "" })
    :build()

  eq(#data.options, 2)
  eq(data.options[1].key, "A")
  eq(data.options[1].cli, "author")
  eq(data.options[2].key, "S")
  eq(data.options[2].cli, "signoff")
end

T["commit popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("a", "all", "All", { enabled = true })
    :switch("v", "verbose", "Verbose")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--all")
end

T["commit popup"]["get_arguments returns multiple enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("a", "all", "All", { enabled = true })
    :switch("v", "verbose", "Verbose", { enabled = true })
    :switch("n", "no-verify", "No verify", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 3)
  eq(args[1], "--all")
  eq(args[2], "--verbose")
  eq(args[3], "--no-verify")
end

T["commit popup"]["get_arguments includes option with value"] = function()
  local popup = require("gitlad.ui.popup")

  local data =
    popup.builder():option("A", "author", "John Doe <john@example.com>", "Author"):build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--author=John Doe <john@example.com>")
end

T["commit popup"]["get_arguments excludes option without value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("A", "author", "", "Author"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["commit popup"]["toggle_switch enables and disables"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():switch("a", "all", "All"):build()

  eq(data.switches[1].enabled, false)

  data:toggle_switch("a")
  eq(data.switches[1].enabled, true)

  data:toggle_switch("a")
  eq(data.switches[1].enabled, false)
end

T["commit popup"]["set_option updates value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("A", "author", "", "Author"):build()

  eq(data.options[1].value, "")

  data:set_option("A", "Jane Doe")
  eq(data.options[1].value, "Jane Doe")
end

T["commit popup"]["signoff option uses empty separator"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :option("S", "signoff", "true", "Signoff", { cli_prefix = "--", separator = "" })
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--signofftrue")
end

T["commit popup"]["creates actions correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local commit_called = false
  local extend_called = false
  local amend_called = false

  local data = popup
    .builder()
    :group_heading("Create")
    :action("c", "Commit", function()
      commit_called = true
    end)
    :group_heading("Edit HEAD")
    :action("e", "Extend", function()
      extend_called = true
    end)
    :action("a", "Amend", function()
      amend_called = true
    end)
    :build()

  -- 2 headings + 3 actions
  eq(#data.actions, 5)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Create")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "c")
  eq(data.actions[3].type, "heading")
  eq(data.actions[3].text, "Edit HEAD")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "e")
  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "a")

  -- Test callbacks
  data.actions[2].callback()
  eq(commit_called, true)

  data.actions[4].callback()
  eq(extend_called, true)

  data.actions[5].callback()
  eq(amend_called, true)
end

return T
