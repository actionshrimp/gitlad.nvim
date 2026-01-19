-- Tests for gitlad.popups.refs module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- =============================================================================
-- Refs popup tests
-- =============================================================================

T["refs popup"] = MiniTest.new_set()

T["refs popup"]["creates popup with correct name"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("References")
    :group_heading("Show refs")
    :action("y", "Show refs at HEAD", function() end)
    :action("r", "Show refs at current branch", function() end)
    :action("o", "Show refs at other ref...", function() end)
    :build()

  eq(data.name, "References")
end

T["refs popup"]["creates popup with correct actions"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("References")
    :group_heading("Show refs")
    :action("y", "Show refs at HEAD", function() end)
    :action("r", "Show refs at current branch", function() end)
    :action("o", "Show refs at other ref...", function() end)
    :build()

  -- 4 items: 1 heading + 3 actions
  eq(#data.actions, 4)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Show refs")
  eq(data.actions[2].key, "y")
  eq(data.actions[2].description, "Show refs at HEAD")
  eq(data.actions[3].key, "r")
  eq(data.actions[3].description, "Show refs at current branch")
  eq(data.actions[4].key, "o")
  eq(data.actions[4].description, "Show refs at other ref...")
end

T["refs popup"]["has no switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("References")
    :action("y", "Show refs at HEAD", function() end)
    :build()

  eq(#data.switches, 0)
end

T["refs popup"]["has no options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("References")
    :action("y", "Show refs at HEAD", function() end)
    :build()

  eq(#data.options, 0)
end

T["refs popup"]["has group heading in actions"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("References")
    :group_heading("Show refs")
    :action("y", "Show refs at HEAD", function() end)
    :build()

  -- Group headings are stored in the actions array with type = "heading"
  eq(#data.actions, 2)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Show refs")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "y")
end

return T
