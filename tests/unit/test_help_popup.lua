local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Help view tests
T["HelpView"] = MiniTest.new_set()

T["HelpView"]["creates view with correct structure"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Test Section",
      columns = 2,
      items = {
        { key = "a", desc = "Action A" },
        { key = "b", desc = "Action B" },
        { key = "c", desc = "Action C" },
      },
    },
  }

  local view = HelpView.new(sections)
  eq(#view.sections, 1)
  eq(view.sections[1].name, "Test Section")
  eq(view.sections[1].columns, 2)
  eq(#view.sections[1].items, 3)
end

T["HelpView"]["renders items in columns"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Test",
      columns = 2,
      items = {
        { key = "a", desc = "First" },
        { key = "b", desc = "Second" },
        { key = "c", desc = "Third" },
        { key = "d", desc = "Fourth" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  -- Should have: header + 2 rows (4 items in 2 columns = 2 rows)
  eq(#lines, 3)
  eq(lines[1], "Test")

  -- First row should have items a and b
  eq(lines[2]:match("a%s+First") ~= nil, true)
  eq(lines[2]:match("b%s+Second") ~= nil, true)

  -- Second row should have items c and d
  eq(lines[3]:match("c%s+Third") ~= nil, true)
  eq(lines[3]:match("d%s+Fourth") ~= nil, true)
end

T["HelpView"]["renders 3 columns correctly"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Commands",
      columns = 3,
      items = {
        { key = "c", desc = "Commit" },
        { key = "b", desc = "Branch" },
        { key = "l", desc = "Log" },
        { key = "p", desc = "Push" },
        { key = "F", desc = "Pull" },
        { key = "f", desc = "Fetch" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  -- Header + 2 rows (6 items / 3 columns = 2 rows)
  eq(#lines, 3)

  -- First row: c, b, l
  eq(lines[2]:match("c%s+Commit") ~= nil, true)
  eq(lines[2]:match("b%s+Branch") ~= nil, true)
  eq(lines[2]:match("l%s+Log") ~= nil, true)

  -- Second row: p, F, f
  eq(lines[3]:match("p%s+Push") ~= nil, true)
  eq(lines[3]:match("F%s+Pull") ~= nil, true)
  eq(lines[3]:match("f%s+Fetch") ~= nil, true)
end

T["HelpView"]["renders multiple sections with blank lines between"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Section One",
      columns = 1,
      items = {
        { key = "a", desc = "Item A" },
      },
    },
    {
      name = "Section Two",
      columns = 1,
      items = {
        { key = "b", desc = "Item B" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  -- Section 1 header + 1 item + blank line + Section 2 header + 1 item = 5 lines
  eq(#lines, 5)
  eq(lines[1], "Section One")
  eq(lines[3], "") -- Blank line between sections
  eq(lines[4], "Section Two")
end

T["HelpView"]["tracks action positions for highlighting"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Test",
      columns = 2,
      items = {
        { key = "ab", desc = "Multi-char key" },
        { key = "c", desc = "Single char" },
      },
    },
  }

  local view = HelpView.new(sections)
  view:render_lines()

  -- Line 2 should have position info (line 1 is header)
  local positions = view.action_positions[2]
  eq(positions ~= nil, true)

  -- Should track both keys
  eq(positions["ab"] ~= nil, true)
  eq(positions["c"] ~= nil, true)

  -- First key starts at col 1 (after leading space)
  eq(positions["ab"].col, 1)
  eq(positions["ab"].len, 2) -- "ab" is 2 chars
end

T["HelpView"]["handles special key notations"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Navigation",
      columns = 1,
      items = {
        { key = "<Tab>", desc = "Toggle" },
        { key = "<CR>", desc = "Visit" },
        { key = "<S-Tab>", desc = "Toggle all" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  eq(lines[2]:match("<Tab>%s+Toggle") ~= nil, true)
  eq(lines[3]:match("<CR>%s+Visit") ~= nil, true)
  eq(lines[4]:match("<S%-Tab>%s+Toggle all") ~= nil, true)
end

T["HelpView"]["action callbacks are invoked"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local action_a_called = false
  local action_b_called = false

  local sections = {
    {
      name = "Test",
      columns = 1,
      items = {
        {
          key = "a",
          desc = "Action A",
          action = function()
            action_a_called = true
          end,
        },
        {
          key = "b",
          desc = "Action B",
          action = function()
            action_b_called = true
          end,
        },
      },
    },
  }

  local view = HelpView.new(sections)

  -- Directly invoke actions
  view.sections[1].items[1].action()
  eq(action_a_called, true)

  view.sections[1].items[2].action()
  eq(action_b_called, true)
end

T["HelpView"]["handles uneven items in columns"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Test",
      columns = 3,
      items = {
        { key = "a", desc = "One" },
        { key = "b", desc = "Two" },
        { key = "c", desc = "Three" },
        { key = "d", desc = "Four" },
        { key = "e", desc = "Five" }, -- Only 5 items, last row has 2
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  -- Header + 2 rows (ceil(5/3) = 2)
  eq(#lines, 3)

  -- Second row should have d and e (but not 3 items)
  eq(lines[3]:match("d%s+Four") ~= nil, true)
  eq(lines[3]:match("e%s+Five") ~= nil, true)
end

T["HelpView"]["empty section renders only header"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Empty Section",
      columns = 2,
      items = {},
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  eq(#lines, 1)
  eq(lines[1], "Empty Section")
end

-- Tests for content matching e2e patterns
T["HelpView content"] = MiniTest.new_set()

T["HelpView content"]["has Navigation section content"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Navigation",
      columns = 3,
      items = {
        { key = "j", desc = "Next item" },
        { key = "k", desc = "Previous item" },
        { key = "<Tab>", desc = "Toggle section" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  local found_navigation = false
  local found_j = false
  local found_k = false

  for _, line in ipairs(lines) do
    if line:match("Navigation") then
      found_navigation = true
    end
    if line:match("j%s+Next item") then
      found_j = true
    end
    if line:match("k%s+Previous item") then
      found_k = true
    end
  end

  eq(found_navigation, true)
  eq(found_j, true)
  eq(found_k, true)
end

T["HelpView content"]["has Staging-equivalent content"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Applying changes",
      columns = 3,
      items = {
        { key = "s", desc = "Stage" },
        { key = "u", desc = "Unstage" },
        { key = "S", desc = "Stage all" },
        { key = "U", desc = "Unstage all" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  local found_s = false
  local found_u = false
  local found_S = false
  local found_U = false

  for _, line in ipairs(lines) do
    if line:match("s%s+Stage[^%s]") or line:match("s%s+Stage%s") then
      found_s = true
    end
    if line:match("u%s+Unstage[^%s]") or line:match("u%s+Unstage%s") then
      found_u = true
    end
    if line:match("S%s+Stage all") then
      found_S = true
    end
    if line:match("U%s+Unstage all") then
      found_U = true
    end
  end

  eq(found_s, true)
  eq(found_u, true)
  eq(found_S, true)
  eq(found_U, true)
end

T["HelpView content"]["has Popups-equivalent content"] = function()
  local help = require("gitlad.popups.help")
  local HelpView = help.HelpView

  local sections = {
    {
      name = "Transient commands",
      columns = 3,
      items = {
        { key = "c", desc = "Commit" },
        { key = "p", desc = "Push" },
      },
    },
  }

  local view = HelpView.new(sections)
  local lines = view:render_lines()

  local found_c = false
  local found_p = false

  for _, line in ipairs(lines) do
    if line:match("c%s+Commit") then
      found_c = true
    end
    if line:match("p%s+Push") then
      found_p = true
    end
  end

  eq(found_c, true)
  eq(found_p, true)
end

return T
