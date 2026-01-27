---@diagnostic disable: undefined-field
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["expansion.reducer"] = MiniTest.new_set()

-- State creation tests
T["expansion.reducer"]["new() creates empty state with default visibility level"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()

  eq(state.visibility_level, 2)
  eq(state.files, {})
  eq(state.sections, {})
  eq(state.commits, {})
end

T["expansion.reducer"]["new() accepts custom visibility level"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new(3)

  eq(state.visibility_level, 3)
end

-- Reset command tests
T["expansion.reducer"]["apply reset clears all state but preserves visibility level"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new(3)
  state.files["unstaged:file.txt"] = { expanded = true }
  state.sections["staged"] = { collapsed = true }

  local new_state = reducer.apply(state, commands.reset())

  eq(new_state.visibility_level, 3)
  eq(new_state.files, {})
  eq(new_state.sections, {})
end

-- Immutability tests
T["expansion.reducer"]["apply returns new state without mutating original"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  local new_state = reducer.apply(state, commands.reset())

  -- Original should be unchanged
  eq(state.files["unstaged:file.txt"].expanded, true)
  -- New state should be reset
  eq(new_state.files, {})
end

-- Helper function tests
T["expansion.reducer"]["get_file returns default when not set"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()

  local file = reducer.get_file(state, "unstaged:file.txt")

  eq(file.expanded, false)
end

T["expansion.reducer"]["get_file returns existing state when set"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = "headers", hunks = { [1] = true } }

  local file = reducer.get_file(state, "unstaged:file.txt")

  eq(file.expanded, "headers")
  eq(file.hunks[1], true)
end

T["expansion.reducer"]["get_section returns default when not set"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()

  local section = reducer.get_section(state, "staged")

  eq(section.collapsed, false)
end

T["expansion.reducer"]["get_section returns existing state when set"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = true }

  local section = reducer.get_section(state, "staged")

  eq(section.collapsed, true)
end

T["expansion.reducer"]["is_file_expanded returns false for collapsed file"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = false }

  local expanded = reducer.is_file_expanded(state, "unstaged:file.txt")

  eq(expanded, false)
end

T["expansion.reducer"]["is_file_expanded returns true for headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = "headers" }

  local expanded = reducer.is_file_expanded(state, "unstaged:file.txt")

  eq(expanded, true)
end

T["expansion.reducer"]["is_file_expanded returns true for fully expanded"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  local expanded = reducer.is_file_expanded(state, "unstaged:file.txt")

  eq(expanded, true)
end

T["expansion.reducer"]["is_section_collapsed returns false by default"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()

  local collapsed = reducer.is_section_collapsed(state, "staged")

  eq(collapsed, false)
end

T["expansion.reducer"]["is_section_collapsed returns true when collapsed"] = function()
  local reducer = require("gitlad.state.expansion.reducer")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = true }

  local collapsed = reducer.is_section_collapsed(state, "staged")

  eq(collapsed, true)
end

-- toggle_file tests
T["expansion.reducer"]["toggle_file collapses expanded file"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  local new_state = reducer.apply(state, commands.toggle_file("unstaged:file.txt"))

  eq(new_state.files["unstaged:file.txt"].expanded, false)
end

T["expansion.reducer"]["toggle_file expands collapsed file to true by default"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = false }

  local new_state = reducer.apply(state, commands.toggle_file("unstaged:file.txt"))

  eq(new_state.files["unstaged:file.txt"].expanded, true)
end

T["expansion.reducer"]["toggle_file restores remembered hunk state when expanding"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = {
    expanded = false,
    remembered = { [1] = true, [2] = false },
  }

  local new_state = reducer.apply(state, commands.toggle_file("unstaged:file.txt"))

  eq(new_state.files["unstaged:file.txt"].expanded, "headers")
  eq(new_state.files["unstaged:file.txt"].hunks[1], true)
  eq(new_state.files["unstaged:file.txt"].hunks[2], false)
end

T["expansion.reducer"]["toggle_file saves hunk state when collapsing from headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = {
    expanded = "headers",
    hunks = { [1] = true, [2] = false, [3] = true },
  }

  local new_state = reducer.apply(state, commands.toggle_file("unstaged:file.txt"))

  eq(new_state.files["unstaged:file.txt"].expanded, false)
  eq(new_state.files["unstaged:file.txt"].remembered[1], true)
  eq(new_state.files["unstaged:file.txt"].remembered[2], false)
  eq(new_state.files["unstaged:file.txt"].remembered[3], true)
end

T["expansion.reducer"]["toggle_file does not save remembered when collapsing from fully expanded"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  local new_state = reducer.apply(state, commands.toggle_file("unstaged:file.txt"))

  eq(new_state.files["unstaged:file.txt"].expanded, false)
  eq(new_state.files["unstaged:file.txt"].remembered, nil)
end

T["expansion.reducer"]["toggle_file on non-existent file expands it"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()

  local new_state = reducer.apply(state, commands.toggle_file("unstaged:file.txt"))

  eq(new_state.files["unstaged:file.txt"].expanded, true)
end

-- toggle_section tests
T["expansion.reducer"]["toggle_section collapses expanded section"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = false }

  local new_state = reducer.apply(state, commands.toggle_section("staged"))

  eq(new_state.sections["staged"].collapsed, true)
end

T["expansion.reducer"]["toggle_section expands collapsed section"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = true }

  local new_state = reducer.apply(state, commands.toggle_section("staged"))

  eq(new_state.sections["staged"].collapsed, false)
end

T["expansion.reducer"]["toggle_section on non-existent section collapses it"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()

  local new_state = reducer.apply(state, commands.toggle_section("staged"))

  eq(new_state.sections["staged"].collapsed, true)
end

T["expansion.reducer"]["toggle_section preserves remembered_files"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.sections["staged"] = {
    collapsed = false,
    remembered_files = { ["staged:file.txt"] = { expanded = true } },
  }

  local new_state = reducer.apply(state, commands.toggle_section("staged"))

  eq(new_state.sections["staged"].collapsed, true)
  eq(new_state.sections["staged"].remembered_files["staged:file.txt"].expanded, true)
end

-- toggle_hunk tests
T["expansion.reducer"]["toggle_hunk expands collapsed hunk in headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = {
    expanded = "headers",
    hunks = { [1] = false, [2] = false },
  }

  local new_state = reducer.apply(state, commands.toggle_hunk("unstaged:file.txt", 1))

  eq(new_state.files["unstaged:file.txt"].expanded, "headers")
  eq(new_state.files["unstaged:file.txt"].hunks[1], true)
  eq(new_state.files["unstaged:file.txt"].hunks[2], false)
end

T["expansion.reducer"]["toggle_hunk collapses expanded hunk in headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = {
    expanded = "headers",
    hunks = { [1] = true, [2] = false },
  }

  local new_state = reducer.apply(state, commands.toggle_hunk("unstaged:file.txt", 1))

  eq(new_state.files["unstaged:file.txt"].hunks[1], false)
end

T["expansion.reducer"]["toggle_hunk transitions from fully expanded to headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  -- total_hunks = 3, toggling hunk 2 should collapse it
  local new_state = reducer.apply(state, commands.toggle_hunk("unstaged:file.txt", 2, 3))

  eq(new_state.files["unstaged:file.txt"].expanded, "headers")
  eq(new_state.files["unstaged:file.txt"].hunks[1], true)
  eq(new_state.files["unstaged:file.txt"].hunks[2], false) -- The toggled hunk
  eq(new_state.files["unstaged:file.txt"].hunks[3], true)
end

T["expansion.reducer"]["toggle_hunk does nothing on collapsed file"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = false }

  local new_state = reducer.apply(state, commands.toggle_hunk("unstaged:file.txt", 1, 2))

  eq(new_state.files["unstaged:file.txt"].expanded, false)
end

T["expansion.reducer"]["toggle_hunk does nothing on non-existent file"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()

  local new_state = reducer.apply(state, commands.toggle_hunk("unstaged:file.txt", 1, 2))

  eq(new_state.files["unstaged:file.txt"], nil)
end

-- set_file_expansion tests
T["expansion.reducer"]["set_file_expansion sets to false"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  local new_state = reducer.apply(state, commands.set_file_expansion("unstaged:file.txt", false))

  eq(new_state.files["unstaged:file.txt"].expanded, false)
end

T["expansion.reducer"]["set_file_expansion sets to headers"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()

  local new_state =
    reducer.apply(state, commands.set_file_expansion("unstaged:file.txt", "headers"))

  eq(new_state.files["unstaged:file.txt"].expanded, "headers")
  eq(new_state.files["unstaged:file.txt"].hunks, {})
end

T["expansion.reducer"]["set_file_expansion sets to true"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = false }

  local new_state = reducer.apply(state, commands.set_file_expansion("unstaged:file.txt", true))

  eq(new_state.files["unstaged:file.txt"].expanded, true)
end

T["expansion.reducer"]["set_file_expansion preserves remembered state"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = {
    expanded = false,
    remembered = { [1] = true },
  }

  local new_state =
    reducer.apply(state, commands.set_file_expansion("unstaged:file.txt", "headers"))

  eq(new_state.files["unstaged:file.txt"].remembered[1], true)
end

return T
