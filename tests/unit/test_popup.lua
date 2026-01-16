local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- PopupBuilder tests
T["PopupBuilder"] = MiniTest.new_set()

T["PopupBuilder"]["builder() returns a builder instance"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder()
  expect.no_equality(builder, nil)
end

T["PopupBuilder"]["name() sets popup name"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():name("TestPopup")
  eq(builder._name, "TestPopup")
end

T["PopupBuilder"]["switch() adds a switch"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():switch("a", "all", "Stage all files")
  eq(#builder._switches, 1)
  eq(builder._switches[1].key, "a")
  eq(builder._switches[1].cli, "all")
  eq(builder._switches[1].description, "Stage all files")
  eq(builder._switches[1].enabled, false)
end

T["PopupBuilder"]["switch() with enabled option"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():switch("v", "verbose", "Verbose output", { enabled = true })
  eq(builder._switches[1].enabled, true)
end

T["PopupBuilder"]["option() adds an option"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():option("A", "author", "", "Override author")
  eq(#builder._options, 1)
  eq(builder._options[1].key, "A")
  eq(builder._options[1].cli, "author")
  eq(builder._options[1].value, "")
  eq(builder._options[1].description, "Override author")
end

T["PopupBuilder"]["option() with default value"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():option("n", "max-count", "100", "Limit commits")
  eq(builder._options[1].value, "100")
end

T["PopupBuilder"]["group_heading() adds a heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():group_heading("Create")
  eq(#builder._actions, 1)
  eq(builder._actions[1].type, "heading")
  eq(builder._actions[1].text, "Create")
end

T["PopupBuilder"]["action() adds an action"] = function()
  local popup = require("gitlad.ui.popup")
  local called = false
  local callback = function()
    called = true
  end
  local builder = popup.builder():action("c", "Commit", callback)
  eq(#builder._actions, 1)
  eq(builder._actions[1].type, "action")
  eq(builder._actions[1].key, "c")
  eq(builder._actions[1].description, "Commit")
  builder._actions[1].callback()
  eq(called, true)
end

T["PopupBuilder"]["method chaining works"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :name("TestPopup")
    :switch("a", "all", "All")
    :switch("v", "verbose", "Verbose")
    :option("A", "author", "", "Author")
    :group_heading("Actions")
    :action("c", "Commit", function() end)

  eq(builder._name, "TestPopup")
  eq(#builder._switches, 2)
  eq(#builder._options, 1)
  eq(#builder._actions, 2) -- heading + action
end

T["PopupBuilder"]["build() returns PopupData"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :name("TestPopup")
    :switch("a", "all", "All")
    :option("A", "author", "", "Author")
    :group_heading("Create")
    :action("c", "Commit", function() end)
    :build()

  expect.no_equality(data, nil)
  eq(data.name, "TestPopup")
  eq(#data.switches, 1)
  eq(#data.options, 1)
  eq(#data.actions, 2)
end

-- PopupData tests
T["PopupData"] = MiniTest.new_set()

T["PopupData"]["get_arguments() returns empty for no enabled switches"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():switch("a", "all", "All"):build()
  local args = data:get_arguments()
  eq(#args, 0)
end

T["PopupData"]["get_arguments() includes enabled switches"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():switch("a", "all", "All", { enabled = true }):build()
  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--all")
end

T["PopupData"]["get_arguments() includes options with values"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():option("A", "author", "John", "Author"):build()
  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--author=John")
end

T["PopupData"]["get_arguments() excludes options with empty values"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():option("A", "author", "", "Author"):build()
  local args = data:get_arguments()
  eq(#args, 0)
end

T["PopupData"]["to_cli() joins arguments"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :switch("a", "all", "All", { enabled = true })
    :switch("v", "verbose", "Verbose", { enabled = true })
    :option("A", "author", "John", "Author")
    :build()
  local cli = data:to_cli()
  eq(cli, "--all --verbose --author=John")
end

T["PopupData"]["toggle_switch() toggles switch state"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():switch("a", "all", "All"):build()
  eq(data.switches[1].enabled, false)
  data:toggle_switch("a")
  eq(data.switches[1].enabled, true)
  data:toggle_switch("a")
  eq(data.switches[1].enabled, false)
end

T["PopupData"]["set_option() sets option value"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():option("A", "author", "", "Author"):build()
  eq(data.options[1].value, "")
  data:set_option("A", "Jane")
  eq(data.options[1].value, "Jane")
end

T["PopupData"]["render_lines() produces expected output"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :name("TestPopup")
    :switch("a", "all", "All", { enabled = true })
    :switch("v", "verbose", "Verbose")
    :option("A", "author", "John", "Author")
    :group_heading("Create")
    :action("c", "Commit", function() end)
    :build()

  local lines = data:render_lines()

  -- Check that lines contain expected content
  local found_args = false
  local found_switch_a = false
  local found_switch_v = false
  local found_option = false
  local found_heading = false
  local found_action = false

  for _, line in ipairs(lines) do
    if line:match("Arguments") then
      found_args = true
    end
    if line:match("%-a.*All.*%(%-%-all%)") then
      found_switch_a = true
    end
    if line:match("%-v.*Verbose") then
      found_switch_v = true
    end
    if line:match("=A.*Author.*%(%-%-author=John%)") then
      found_option = true
    end
    if line:match("Create") then
      found_heading = true
    end
    if line:match("c.*Commit") then
      found_action = true
    end
  end

  eq(found_args, true)
  eq(found_switch_a, true)
  eq(found_switch_v, true)
  eq(found_option, true)
  eq(found_heading, true)
  eq(found_action, true)
end

return T
