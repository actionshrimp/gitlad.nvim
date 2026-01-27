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

-- Visibility level tests (global scope)
T["expansion.reducer"]["set_visibility_level 1 global collapses all sections"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = false }
  state.sections["unstaged"] = { collapsed = false }

  local cmd = commands.set_visibility_level(1, scope.global(), {
    sections = { "staged", "unstaged" },
  })
  local new_state = reducer.apply(state, cmd)

  eq(new_state.visibility_level, 1)
  eq(new_state.sections["staged"].collapsed, true)
  eq(new_state.sections["unstaged"].collapsed, true)
end

T["expansion.reducer"]["set_visibility_level 1 global clears file expansions"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }
  state.commits["abc123"] = true

  local cmd = commands.set_visibility_level(1, scope.global(), {
    sections = {},
  })
  local new_state = reducer.apply(state, cmd)

  eq(new_state.files, {})
  eq(new_state.commits, {})
end

T["expansion.reducer"]["set_visibility_level 2 global expands sections"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = true }
  state.sections["unstaged"] = { collapsed = true }

  local cmd = commands.set_visibility_level(2, scope.global(), {
    sections = { "staged", "unstaged" },
  })
  local new_state = reducer.apply(state, cmd)

  eq(new_state.visibility_level, 2)
  eq(new_state.sections["staged"].collapsed, false)
  eq(new_state.sections["unstaged"].collapsed, false)
end

T["expansion.reducer"]["set_visibility_level 3 global sets files to headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()

  local cmd = commands.set_visibility_level(3, scope.global(), {
    sections = { "unstaged" },
    file_keys = { "unstaged:file1.txt", "unstaged:file2.txt" },
  })
  local new_state = reducer.apply(state, cmd)

  eq(new_state.visibility_level, 3)
  eq(new_state.files["unstaged:file1.txt"].expanded, "headers")
  eq(new_state.files["unstaged:file2.txt"].expanded, "headers")
end

T["expansion.reducer"]["set_visibility_level 4 global fully expands everything"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()

  local cmd = commands.set_visibility_level(4, scope.global(), {
    sections = { "unstaged" },
    file_keys = { "unstaged:file.txt" },
    commit_hashes = { "abc123", "def456" },
  })
  local new_state = reducer.apply(state, cmd)

  eq(new_state.visibility_level, 4)
  eq(new_state.sections["unstaged"].collapsed, false)
  eq(new_state.files["unstaged:file.txt"].expanded, true)
  eq(new_state.commits["abc123"], true)
  eq(new_state.commits["def456"], true)
end

-- Visibility level tests (section scope)
T["expansion.reducer"]["set_visibility_level 1 section collapses that section"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.sections["unstaged"] = { collapsed = false }
  state.files["unstaged:file.txt"] = { expanded = true }

  local cmd = commands.set_visibility_level(1, scope.section("unstaged"), {
    file_keys = { "unstaged:file.txt" },
  })
  local new_state = reducer.apply(state, cmd)

  eq(new_state.sections["unstaged"].collapsed, true)
  eq(new_state.files["unstaged:file.txt"], nil)
end

T["expansion.reducer"]["set_visibility_level 4 section expands only that section"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.sections["staged"] = { collapsed = true }

  local cmd = commands.set_visibility_level(4, scope.section("unstaged"), {
    file_keys = { "unstaged:file.txt" },
    commit_hashes = { "abc123" },
  })
  local new_state = reducer.apply(state, cmd)

  -- Only unstaged section is affected
  eq(new_state.sections["unstaged"].collapsed, false)
  eq(new_state.sections["staged"].collapsed, true) -- Unchanged
  eq(new_state.files["unstaged:file.txt"].expanded, true)
  eq(new_state.commits["abc123"], true)
end

-- Visibility level tests (file scope)
T["expansion.reducer"]["set_visibility_level 1 file collapses that file"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = true }

  local cmd = commands.set_visibility_level(1, scope.file("unstaged", "unstaged:file.txt"))
  local new_state = reducer.apply(state, cmd)

  eq(new_state.files["unstaged:file.txt"].expanded, false)
end

T["expansion.reducer"]["set_visibility_level 3 file sets to headers mode"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()

  local cmd = commands.set_visibility_level(3, scope.file("unstaged", "unstaged:file.txt"))
  local new_state = reducer.apply(state, cmd)

  eq(new_state.files["unstaged:file.txt"].expanded, "headers")
end

T["expansion.reducer"]["set_visibility_level 4 file fully expands that file"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = { expanded = false }

  local cmd = commands.set_visibility_level(4, scope.file("unstaged", "unstaged:file.txt"))
  local new_state = reducer.apply(state, cmd)

  eq(new_state.files["unstaged:file.txt"].expanded, true)
end

T["expansion.reducer"]["set_visibility_level preserves remembered state"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()
  state.files["unstaged:file.txt"] = {
    expanded = true,
    remembered = { [1] = true, [2] = false },
  }

  local cmd = commands.set_visibility_level(1, scope.file("unstaged", "unstaged:file.txt"))
  local new_state = reducer.apply(state, cmd)

  eq(new_state.files["unstaged:file.txt"].expanded, false)
  eq(new_state.files["unstaged:file.txt"].remembered[1], true)
  eq(new_state.files["unstaged:file.txt"].remembered[2], false)
end

T["expansion.reducer"]["set_visibility_level clamps level to 1-4"] = function()
  local reducer = require("gitlad.state.expansion.reducer")
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local state = reducer.new()

  -- Level 0 should clamp to 1
  local cmd1 = commands.set_visibility_level(0, scope.global())
  local new_state1 = reducer.apply(state, cmd1)
  eq(new_state1.visibility_level, 1)

  -- Level 5 should clamp to 4
  local cmd2 = commands.set_visibility_level(5, scope.global())
  local new_state2 = reducer.apply(state, cmd2)
  eq(new_state2.visibility_level, 4)
end

return T
