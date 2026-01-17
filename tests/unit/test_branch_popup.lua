local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Branch popup builder tests
T["branch popup"] = MiniTest.new_set()

T["branch popup"]["creates popup with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build a similar popup structure as branch.lua
  local data = popup
    .builder()
    :name("Branch")
    :switch("f", "force", "Force delete (even if not merged)")
    :group_heading("Checkout")
    :action("b", "Checkout branch", function() end)
    :action("c", "Create and checkout", function() end)
    :group_heading("Create")
    :action("n", "Create branch", function() end)
    :group_heading("Do")
    :action("m", "Rename", function() end)
    :action("D", "Delete", function() end)
    :build()

  eq(data.name, "Branch")
  eq(#data.switches, 1)
  eq(data.switches[1].key, "f")
  eq(data.switches[1].cli, "force")
end

T["branch popup"]["has force switch"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():name("Branch"):switch("f", "force", "Force delete"):build()

  eq(#data.switches, 1)
  eq(data.switches[1].key, "f")
  eq(data.switches[1].cli, "force")
  eq(data.switches[1].enabled, false)
end

T["branch popup"]["force switch toggles correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local data =
    popup.builder():name("Branch"):switch("f", "force", "Force delete", { enabled = true }):build()

  eq(data.switches[1].enabled, true)
end

T["branch popup"]["has correct action groups"] = function()
  local popup = require("gitlad.ui.popup")

  local checkout_called = false
  local create_checkout_called = false
  local create_called = false
  local rename_called = false
  local delete_called = false

  local data = popup
    .builder()
    :name("Branch")
    :group_heading("Checkout")
    :action("b", "Checkout branch", function()
      checkout_called = true
    end)
    :action("c", "Create and checkout", function()
      create_checkout_called = true
    end)
    :group_heading("Create")
    :action("n", "Create branch", function()
      create_called = true
    end)
    :group_heading("Do")
    :action("m", "Rename", function()
      rename_called = true
    end)
    :action("D", "Delete", function()
      delete_called = true
    end)
    :build()

  -- 3 headings + 5 actions = 8 items
  eq(#data.actions, 8)

  -- Check headings
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Checkout")
  eq(data.actions[4].type, "heading")
  eq(data.actions[4].text, "Create")
  eq(data.actions[6].type, "heading")
  eq(data.actions[6].text, "Do")

  -- Check actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "b")
  eq(data.actions[2].description, "Checkout branch")

  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "c")
  eq(data.actions[3].description, "Create and checkout")

  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "n")
  eq(data.actions[5].description, "Create branch")

  eq(data.actions[7].type, "action")
  eq(data.actions[7].key, "m")
  eq(data.actions[7].description, "Rename")

  eq(data.actions[8].type, "action")
  eq(data.actions[8].key, "D")
  eq(data.actions[8].description, "Delete")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(checkout_called, true)

  data.actions[3].callback(data)
  eq(create_checkout_called, true)

  data.actions[5].callback(data)
  eq(create_called, true)

  data.actions[7].callback(data)
  eq(rename_called, true)

  data.actions[8].callback(data)
  eq(delete_called, true)
end

-- Parse branches tests
T["parse_branches"] = MiniTest.new_set()

T["parse_branches"]["parses single branch"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({
    "* main",
  })

  eq(#result, 1)
  eq(result[1].name, "main")
  eq(result[1].current, true)
end

T["parse_branches"]["parses multiple branches"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({
    "  feature-a",
    "* main",
    "  feature-b",
  })

  eq(#result, 3)
  eq(result[1].name, "feature-a")
  eq(result[1].current, false)
  eq(result[2].name, "main")
  eq(result[2].current, true)
  eq(result[3].name, "feature-b")
  eq(result[3].current, false)
end

T["parse_branches"]["handles detached HEAD"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({
    "* (HEAD detached at abc1234)",
    "  main",
  })

  eq(#result, 2)
  eq(result[1].name, "HEAD (detached)")
  eq(result[1].current, true)
  eq(result[2].name, "main")
  eq(result[2].current, false)
end

T["parse_branches"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({})

  eq(#result, 0)
end

T["parse_branches"]["handles branches with slashes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({
    "  feature/add-login",
    "* main",
    "  bugfix/fix-crash",
  })

  eq(#result, 3)
  eq(result[1].name, "feature/add-login")
  eq(result[2].name, "main")
  eq(result[3].name, "bugfix/fix-crash")
end

-- Configure group tests
T["branch popup configure"] = MiniTest.new_set()

T["branch popup configure"]["has Configure group with set upstream action"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Branch")
    :group_heading("Configure")
    :action("u", "Set upstream", function() end)
    :action("r", "Configure push remote", function() end)
    :build()

  -- Check that Configure heading exists
  local found_configure = false
  local found_upstream = false
  local found_push_remote = false

  for _, action in ipairs(data.actions) do
    if action.type == "heading" and action.text == "Configure" then
      found_configure = true
    end
    if action.type == "action" and action.key == "u" and action.description == "Set upstream" then
      found_upstream = true
    end
    if
      action.type == "action"
      and action.key == "r"
      and action.description == "Configure push remote"
    then
      found_push_remote = true
    end
  end

  eq(found_configure, true)
  eq(found_upstream, true)
  eq(found_push_remote, true)
end

return T
