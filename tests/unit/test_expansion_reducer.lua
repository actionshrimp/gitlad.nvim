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

return T
