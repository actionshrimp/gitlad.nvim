local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Help popup builder tests
T["help popup"] = MiniTest.new_set()

T["help popup"]["creates popup with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build a minimal help popup to verify structure
  local data = popup
    .builder()
    :name("Help")
    :group_heading("Navigation")
    :action("j", "Next item", function() end)
    :action("k", "Previous item", function() end)
    :group_heading("Staging")
    :action("s", "Stage file/hunk at cursor", function() end)
    :action("u", "Unstage file/hunk at cursor", function() end)
    :action("S", "Stage all", function() end)
    :action("U", "Unstage all", function() end)
    :group_heading("Popups")
    :action("c", "Commit", function() end)
    :action("p", "Push", function() end)
    :group_heading("Other")
    :action("g", "Refresh", function() end)
    :action("$", "Git command history", function() end)
    :action("q", "Close status buffer", function() end)
    :action("?", "This help", function() end)
    :build()

  eq(data.name, "Help")
  -- No switches or options in help popup
  eq(#data.switches, 0)
  eq(#data.options, 0)
  -- 4 headings + 12 actions = 16 total
  eq(#data.actions, 16)
end

T["help popup"]["has navigation section"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :group_heading("Navigation")
    :action("j", "Next item", function() end)
    :action("k", "Previous item", function() end)
    :action("<Tab>", "Toggle inline diff", function() end)
    :action("<CR>", "Visit file at point", function() end)
    :build()

  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Navigation")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "j")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "k")
  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "<Tab>")
  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "<CR>")
end

T["help popup"]["has staging section"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :group_heading("Staging")
    :action("s", "Stage file/hunk at cursor", function() end)
    :action("u", "Unstage file/hunk at cursor", function() end)
    :action("S", "Stage all", function() end)
    :action("U", "Unstage all", function() end)
    :action("x", "Discard changes at point", function() end)
    :build()

  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Staging")
  eq(data.actions[2].key, "s")
  eq(data.actions[3].key, "u")
  eq(data.actions[4].key, "S")
  eq(data.actions[5].key, "U")
  eq(data.actions[6].key, "x")
end

T["help popup"]["has popups section"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :group_heading("Popups")
    :action("c", "Commit", function() end)
    :action("p", "Push", function() end)
    :build()

  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Popups")
  eq(data.actions[2].key, "c")
  eq(data.actions[2].description, "Commit")
  eq(data.actions[3].key, "p")
  eq(data.actions[3].description, "Push")
end

T["help popup"]["has other section"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :group_heading("Other")
    :action("g", "Refresh", function() end)
    :action("$", "Git command history", function() end)
    :action("q", "Close status buffer", function() end)
    :action("?", "This help", function() end)
    :build()

  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Other")
  eq(data.actions[2].key, "g")
  eq(data.actions[3].key, "$")
  eq(data.actions[4].key, "q")
  eq(data.actions[5].key, "?")
end

T["help popup"]["action callbacks are invoked"] = function()
  local popup = require("gitlad.ui.popup")

  local stage_all_called = false
  local unstage_all_called = false
  local refresh_called = false

  local data = popup
    .builder()
    :action("S", "Stage all", function()
      stage_all_called = true
    end)
    :action("U", "Unstage all", function()
      unstage_all_called = true
    end)
    :action("g", "Refresh", function()
      refresh_called = true
    end)
    :build()

  -- Invoke callbacks
  data.actions[1].callback(data)
  eq(stage_all_called, true)

  data.actions[2].callback(data)
  eq(unstage_all_called, true)

  data.actions[3].callback(data)
  eq(refresh_called, true)
end

T["help popup"]["supports special key notations"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :action("<Tab>", "Toggle diff", function() end)
    :action("<CR>", "Visit file", function() end)
    :build()

  eq(data.actions[1].key, "<Tab>")
  eq(data.actions[2].key, "<CR>")
end

T["help popup"]["renders correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Help")
    :group_heading("Navigation")
    :action("j", "Next item", function() end)
    :action("k", "Previous item", function() end)
    :build()

  local lines = data:render_lines()

  -- Check that heading and actions are rendered
  local found_heading = false
  local found_j = false
  local found_k = false

  for _, line in ipairs(lines) do
    if line:match("Navigation") then
      found_heading = true
    end
    if line:match("j") and line:match("Next item") then
      found_j = true
    end
    if line:match("k") and line:match("Previous item") then
      found_k = true
    end
  end

  eq(found_heading, true)
  eq(found_j, true)
  eq(found_k, true)
end

return T
