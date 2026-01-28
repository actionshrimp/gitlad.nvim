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

-- Two-column layout tests
T["popup two column layout"] = MiniTest.new_set()

T["popup two column layout"]["columns method sets column count"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():columns(2):build()

  eq(data.columns, 2)
end

T["popup two column layout"]["defaults to single column"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():build()

  eq(data.columns, 1)
end

T["popup two column layout"]["renders groups in two columns"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :columns(2)
    :group_heading("Left Section")
    :action("a", "Action A", function() end)
    :action("b", "Action B", function() end)
    :group_heading("Right Section")
    :action("c", "Action C", function() end)
    :action("d", "Action D", function() end)
    :build()

  local lines = data:render_lines()

  -- Should have both sections on same lines (side by side)
  -- Find a line that contains content from both columns
  local has_two_columns = false
  for _, line in ipairs(lines) do
    if
      (line:match("Left Section") and line:match("Right Section"))
      or (line:match("Action A") and line:match("Action C"))
      or (line:match("Action B") and line:match("Action D"))
    then
      has_two_columns = true
      break
    end
  end

  eq(has_two_columns, true)
end

T["popup two column layout"]["tracks action positions for highlighting"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :columns(2)
    :group_heading("Left")
    :action("a", "Action A", function() end)
    :group_heading("Right")
    :action("b", "Action B", function() end)
    :build()

  local _ = data:render_lines()

  -- Should have action positions tracked
  local found_positions = false
  for _, pos_table in pairs(data.action_positions) do
    for key, pos in pairs(pos_table) do
      if key == "a" or key == "b" then
        -- Position should have col and len
        expect.no_equality(pos.col, nil)
        expect.no_equality(pos.len, nil)
        found_positions = true
      end
    end
  end

  eq(found_positions, true)
end

T["popup two column layout"]["balances groups between columns"] = function()
  local popup = require("gitlad.ui.popup")

  -- Create an unbalanced popup - first group much larger than second
  local data = popup
    .builder()
    :columns(2)
    :group_heading("Large Group")
    :action("a", "Action A", function() end)
    :action("b", "Action B", function() end)
    :action("c", "Action C", function() end)
    :action("d", "Action D", function() end)
    :action("e", "Action E", function() end)
    :action("f", "Action F", function() end)
    :group_heading("Small Group")
    :action("g", "Action G", function() end)
    :build()

  local lines = data:render_lines()

  -- Should split into columns, not have everything in one column
  -- The large group (7 lines including heading) should be in one column
  -- The small group (2 lines including heading) should be in the other
  -- This should result in fewer lines than single column (9 lines)
  eq(#lines < 9, true)
end

-- Mutually exclusive switches tests
T["exclusive_with"] = MiniTest.new_set()

T["exclusive_with"]["switch() accepts exclusive_with option"] = function()
  local popup = require("gitlad.ui.popup")
  local builder =
    popup.builder():switch("f", "ff-only", "Fast-forward only", { exclusive_with = { "no-ff" } })
  eq(builder._switches[1].exclusive_with[1], "no-ff")
end

T["exclusive_with"]["toggle_switch() disables exclusive switches when enabling"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only", { exclusive_with = { "no-ff" } })
    :switch("n", "no-ff", "No fast-forward", { exclusive_with = { "ff-only" } })
    :build()

  -- Enable ff-only
  data:toggle_switch("f")
  eq(data.switches[1].enabled, true) -- ff-only
  eq(data.switches[2].enabled, false) -- no-ff

  -- Enable no-ff should disable ff-only
  data:toggle_switch("n")
  eq(data.switches[1].enabled, false) -- ff-only disabled
  eq(data.switches[2].enabled, true) -- no-ff enabled
end

T["exclusive_with"]["toggle_switch() does not affect non-exclusive switches"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only", { exclusive_with = { "no-ff" } })
    :switch("n", "no-ff", "No fast-forward", { exclusive_with = { "ff-only" } })
    :switch("v", "verbose", "Verbose output")
    :build()

  -- Enable verbose
  data:toggle_switch("v")
  eq(data.switches[3].enabled, true)

  -- Enable ff-only should not affect verbose
  data:toggle_switch("f")
  eq(data.switches[1].enabled, true)
  eq(data.switches[3].enabled, true) -- verbose still enabled
end

T["exclusive_with"]["disabling a switch does not affect others"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :switch("f", "ff-only", "Fast-forward only", { exclusive_with = { "no-ff" }, enabled = true })
    :switch("n", "no-ff", "No fast-forward", { exclusive_with = { "ff-only" } })
    :build()

  -- Disable ff-only (toggle off)
  data:toggle_switch("f")
  eq(data.switches[1].enabled, false)
  eq(data.switches[2].enabled, false) -- no-ff should remain disabled
end

-- Choice option tests
T["choice_option"] = MiniTest.new_set()

T["choice_option"]["choice_option() adds an option with choices"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :choice_option("s", "strategy", { "resolve", "recursive", "octopus" }, "Strategy")

  eq(#builder._options, 1)
  eq(builder._options[1].key, "s")
  eq(builder._options[1].cli, "strategy")
  eq(builder._options[1].description, "Strategy")
  eq(builder._options[1].choices[1], "resolve")
  eq(builder._options[1].choices[2], "recursive")
  eq(builder._options[1].choices[3], "octopus")
end

T["choice_option"]["choice_option() uses default cli_prefix and separator"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():choice_option("s", "strategy", { "resolve" }, "Strategy"):build()

  eq(data.options[1].cli_prefix, "--")
  eq(data.options[1].separator, "=")
end

T["choice_option"]["choice_option() accepts custom cli_prefix and separator"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :choice_option("A", "Xdiff-algorithm", { "default" }, "Diff algorithm", {
      cli_prefix = "-",
      separator = "=",
    })
    :build()

  eq(data.options[1].cli_prefix, "-")
  eq(data.options[1].separator, "=")
end

T["choice_option"]["choice_option() with default value"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :choice_option(
      "s",
      "strategy",
      { "resolve", "recursive" },
      "Strategy",
      { default = "recursive" }
    )
    :build()

  eq(data.options[1].value, "recursive")
end

T["choice_option"]["get_arguments() includes choice option with value"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :choice_option("s", "strategy", { "resolve", "recursive" }, "Strategy", { default = "ours" })
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--strategy=ours")
end

T["choice_option"]["set_option() works for choice options"] = function()
  local popup = require("gitlad.ui.popup")
  local data =
    popup.builder():choice_option("s", "strategy", { "resolve", "recursive" }, "Strategy"):build()

  eq(data.options[1].value, "")
  data:set_option("s", "recursive")
  eq(data.options[1].value, "recursive")
end

T["choice_option"]["render_lines() shows choice option"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :choice_option("s", "strategy", { "resolve", "recursive" }, "Strategy", { default = "ours" })
    :build()

  local lines = data:render_lines()

  local found_option = false
  for _, line in ipairs(lines) do
    if line:match("=s.*Strategy.*%(%-%-strategy=ours%)") then
      found_option = true
      break
    end
  end

  eq(found_option, true)
end

return T
