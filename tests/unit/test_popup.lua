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

-- Config var tests
T["config_var"] = MiniTest.new_set()

T["config_var"]["branch_scope() sets branch name"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():branch_scope("main")
  eq(builder._branch_scope, "main")
end

T["config_var"]["repo_root() sets repository root"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():repo_root("/path/to/repo")
  eq(builder._repo_root, "/path/to/repo")
end

T["config_var"]["config_heading() adds a heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():config_heading("Configure main")
  eq(#builder._config_vars, 1)
  eq(builder._config_vars[1].type, "config_heading")
  eq(builder._config_vars[1].text, "Configure main")
end

T["config_var"]["config_var() adds a config variable"] = function()
  local popup = require("gitlad.ui.popup")
  local builder =
    popup
      .builder()
      :config_var("d", "branch.main.description", "branch.main.description", { type = "text" })
  eq(#builder._config_vars, 1)
  eq(builder._config_vars[1].type, "config_var")
  eq(builder._config_vars[1].key, "d")
  eq(builder._config_vars[1].config_key, "branch.main.description")
  eq(builder._config_vars[1].label, "branch.main.description")
  eq(builder._config_vars[1].var_type, "text")
end

T["config_var"]["config_var() with cycle type"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():config_var("r", "branch.main.rebase", "branch.main.rebase", {
    type = "cycle",
    choices = { "true", "false", "" },
    default_display = "default:false",
  })
  eq(builder._config_vars[1].var_type, "cycle")
  eq(builder._config_vars[1].choices[1], "true")
  eq(builder._config_vars[1].choices[2], "false")
  eq(builder._config_vars[1].choices[3], "")
  eq(builder._config_vars[1].default_display, "default:false")
end

T["config_var"]["build() substitutes %s in config keys with branch scope"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :branch_scope("feature-branch")
    :config_var("d", "branch.%s.description", "branch.%s.description", { type = "text" })
    :build()

  eq(data.config_vars[1].config_key, "branch.feature-branch.description")
  eq(data.config_vars[1].label, "branch.feature-branch.description")
end

T["config_var"]["build() substitutes %s in config headings"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():branch_scope("main"):config_heading("Configure %s"):build()

  eq(data.config_vars[1].text, "Configure main")
end

T["config_var"]["build() preserves branch_scope and repo_root"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():branch_scope("main"):repo_root("/path/to/repo"):build()

  eq(data.branch_scope, "main")
  eq(data.repo_root, "/path/to/repo")
end

T["config_var"]["render_lines() includes config section before Arguments"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Configure main")
    :config_var("d", "test.key", "test.key", { type = "text" })
    :switch("a", "all", "All")
    :build()

  local lines = data:render_lines()

  -- Find indices of config heading and Arguments
  local config_idx = nil
  local args_idx = nil
  for i, line in ipairs(lines) do
    if line:match("Configure main") then
      config_idx = i
    end
    if line:match("Arguments") then
      args_idx = i
    end
  end

  expect.no_equality(config_idx, nil)
  expect.no_equality(args_idx, nil)
  -- Config should come before Arguments
  eq(config_idx < args_idx, true)
end

T["config_var"]["render_lines() shows unset for nil values"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Config")
    :config_var("d", "nonexistent.key", "nonexistent.key", { type = "text" })
    :build()

  local lines = data:render_lines()

  local found_unset = false
  for _, line in ipairs(lines) do
    if line:match("unset") then
      found_unset = true
      break
    end
  end

  eq(found_unset, true)
end

T["config_var"]["render_lines() shows choice format for cycle type"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Config")
    :config_var("r", "test.rebase", "test.rebase", {
      type = "cycle",
      choices = { "true", "false", "" },
      default_display = "default:false",
    })
    :build()

  local lines = data:render_lines()

  local found_choices = false
  for _, line in ipairs(lines) do
    if line:match("%[.*true.*false.*default") then
      found_choices = true
      break
    end
  end

  eq(found_choices, true)
end

T["config_var"]["tracks config positions for highlighting"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Config")
    :config_var("d", "test.key", "test.key", { type = "text" })
    :build()

  local _ = data:render_lines()

  -- Should have config positions tracked
  local found_positions = false
  for _, pos_table in pairs(data.config_positions) do
    for key, pos in pairs(pos_table) do
      if key == "d" then
        expect.no_equality(pos.col, nil)
        expect.no_equality(pos.len, nil)
        expect.no_equality(pos.config_key, nil)
        found_positions = true
      end
    end
  end

  eq(found_positions, true)
end

T["config_var"]["_find_config_var() finds config var by key"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Config")
    :config_var("d", "test.desc", "test.desc", { type = "text" })
    :config_var("r", "test.rebase", "test.rebase", { type = "cycle" })
    :build()

  local cv = data:_find_config_var("r")
  expect.no_equality(cv, nil)
  eq(cv.config_key, "test.rebase")
end

T["config_var"]["_find_config_var() returns nil for unknown key"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():config_var("d", "test.desc", "test.desc", { type = "text" }):build()

  local cv = data:_find_config_var("x")
  eq(cv, nil)
end

-- remote_cycle type tests
T["config_var"]["config_var() with remote_cycle type"] = function()
  local popup = require("gitlad.ui.popup")
  local builder =
    popup.builder():config_var("p", "branch.main.pushRemote", "branch.main.pushRemote", {
      type = "remote_cycle",
      fallback = "remote.pushDefault",
    })
  eq(builder._config_vars[1].var_type, "remote_cycle")
  eq(builder._config_vars[1].fallback, "remote.pushDefault")
end

T["config_var"]["config_var() with remote_cycle type without fallback"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():config_var("P", "remote.pushDefault", "remote.pushDefault", {
    type = "remote_cycle",
  })
  eq(builder._config_vars[1].var_type, "remote_cycle")
  eq(builder._config_vars[1].fallback, nil)
end

T["config_var"]["remote_cycle renders in bracket format"] = function()
  local popup = require("gitlad.ui.popup")
  -- Build popup - remotes_choices will be populated from current git repo
  local data = popup
    .builder()
    :config_heading("Config")
    :config_var("p", "test.pushRemote", "test.pushRemote", { type = "remote_cycle" })
    :build()

  -- config_vars[1] is the heading, config_vars[2] is the config_var
  -- remote_choices should be a table (may or may not have remotes depending on test env)
  eq(type(data.config_vars[2].remote_choices), "table")

  local lines = data:render_lines()

  -- Should show bracket format [something] (could be [] or [origin] etc)
  local found_bracket = false
  for _, line in ipairs(lines) do
    if line:match("%[.*%]") then
      found_bracket = true
      break
    end
  end

  eq(found_bracket, true)
end

T["config_var"]["tracks remote_choices and fallback in config_positions"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_var("p", "test.pushRemote", "test.pushRemote", {
      type = "remote_cycle",
      fallback = "remote.pushDefault",
    })
    :build()

  local _ = data:render_lines()

  -- Should have remote_cycle metadata in positions
  local found_positions = false
  for _, pos_table in pairs(data.config_positions) do
    for key, pos in pairs(pos_table) do
      if key == "p" then
        eq(pos.var_type, "remote_cycle")
        eq(pos.fallback, "remote.pushDefault")
        eq(type(pos.remote_choices), "table")
        found_positions = true
      end
    end
  end

  eq(found_positions, true)
end

-- config_display tests (read-only config vars)
T["config_var"]["config_display() adds a read-only config var"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():config_display("branch.main.remote", "branch.main.remote")
  eq(#builder._config_vars, 1)
  eq(builder._config_vars[1].type, "config_var")
  eq(builder._config_vars[1].key, nil) -- No key for read-only
  eq(builder._config_vars[1].config_key, "branch.main.remote")
  eq(builder._config_vars[1].label, "branch.main.remote")
  eq(builder._config_vars[1].read_only, true)
end

T["config_var"]["config_display() renders with 3-space indent"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Config")
    :config_display("test.readonly", "test.readonly")
    :build()

  local lines = data:render_lines()

  -- Should have a line starting with 3 spaces (not " k " pattern)
  local found_readonly = false
  for _, line in ipairs(lines) do
    -- Pattern: starts with 3 spaces, then the label
    if line:match("^   test%.readonly") then
      found_readonly = true
      break
    end
  end

  eq(found_readonly, true)
end

T["config_var"]["config_display() has no position entry for highlighting"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():config_display("test.readonly", "test.readonly"):build()

  local _ = data:render_lines()

  -- Should have no config_positions entries (read-only has no key to highlight)
  local has_positions = false
  for _, pos_table in pairs(data.config_positions) do
    if next(pos_table) then
      has_positions = true
      break
    end
  end

  eq(has_positions, false)
end

T["config_var"]["config_display() substitutes %s with branch scope"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :branch_scope("feature")
    :config_display("branch.%s.remote", "branch.%s.remote")
    :build()

  eq(data.config_vars[1].config_key, "branch.feature.remote")
  eq(data.config_vars[1].label, "branch.feature.remote")
end

-- on_set callback tests
T["config_var"]["config_var() accepts on_set callback"] = function()
  local popup = require("gitlad.ui.popup")
  local on_set_called = false
  local builder = popup.builder():config_var("u", "test.merge", "test.merge", {
    type = "text",
    on_set = function(value, popup_data)
      on_set_called = true
      return { ["test.key1"] = "val1", ["test.key2"] = "val2" }
    end,
  })
  expect.no_equality(builder._config_vars[1].on_set, nil)
end

T["config_var"]["on_set callback is preserved after build"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_var("u", "test.merge", "test.merge", {
      type = "text",
      on_set = function(value, popup_data)
        return { ["test.key"] = value }
      end,
    })
    :build()

  expect.no_equality(data.config_vars[1].on_set, nil)
end

-- ref type tests
T["config_var"]["config_var() with ref type"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():config_var("u", "branch.main.merge", "branch.main.merge", {
    type = "ref",
  })
  eq(builder._config_vars[1].var_type, "ref")
end

T["config_var"]["ref type is preserved after build"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_var("u", "branch.main.merge", "branch.main.merge", {
      type = "ref",
    })
    :build()

  eq(data.config_vars[1].var_type, "ref")
end

T["config_var"]["ref type renders same as text type"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_heading("Config")
    :config_var("u", "test.merge", "test.merge", { type = "ref" })
    :build()

  local lines = data:render_lines()

  -- Should show unset like text type (value display is same)
  local found_line = false
  for _, line in ipairs(lines) do
    if line:match("u.*test%.merge") then
      found_line = true
      break
    end
  end

  eq(found_line, true)
end

T["config_var"]["ref type tracks positions for highlighting"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():config_var("u", "test.merge", "test.merge", { type = "ref" }):build()

  local _ = data:render_lines()

  -- Should have config positions tracked
  local found_positions = false
  for _, pos_table in pairs(data.config_positions) do
    for key, pos in pairs(pos_table) do
      if key == "u" then
        expect.no_equality(pos.col, nil)
        expect.no_equality(pos.len, nil)
        eq(pos.var_type, "ref")
        found_positions = true
      end
    end
  end

  eq(found_positions, true)
end

T["config_var"]["ref type with on_set callback"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :config_var("u", "branch.main.merge", "branch.main.merge", {
      type = "ref",
      on_set = function(value, popup_data)
        return { ["branch.main.remote"] = "origin", ["branch.main.merge"] = "refs/heads/" .. value }
      end,
    })
    :build()

  expect.no_equality(data.config_vars[1].on_set, nil)
  eq(data.config_vars[1].var_type, "ref")
end

return T
