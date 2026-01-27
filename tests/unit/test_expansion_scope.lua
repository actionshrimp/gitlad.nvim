---@diagnostic disable: undefined-field
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["expansion.scope"] = MiniTest.new_set()

-- Scope factory tests
T["expansion.scope"]["global() creates global scope"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local s = scope.global()

  eq(s.type, "global")
  eq(s.section_key, nil)
  eq(s.file_key, nil)
  eq(s.hunk_index, nil)
end

T["expansion.scope"]["section() creates section scope"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local s = scope.section("unstaged")

  eq(s.type, "section")
  eq(s.section_key, "unstaged")
  eq(s.file_key, nil)
end

T["expansion.scope"]["file() creates file scope"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local s = scope.file("unstaged", "unstaged:file.txt")

  eq(s.type, "file")
  eq(s.section_key, "unstaged")
  eq(s.file_key, "unstaged:file.txt")
  eq(s.hunk_index, nil)
end

T["expansion.scope"]["hunk() creates hunk scope"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local s = scope.hunk("unstaged", "unstaged:file.txt", 2)

  eq(s.type, "hunk")
  eq(s.section_key, "unstaged")
  eq(s.file_key, "unstaged:file.txt")
  eq(s.hunk_index, 2)
end

-- Scope resolution tests
T["expansion.scope"]["resolve() returns global scope when cursor on empty line"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local line_map = {}
  local section_lines = {}

  local s = scope.resolve(5, line_map, section_lines)

  eq(s.type, "global")
end

T["expansion.scope"]["resolve() returns section scope when cursor on section header"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local line_map = {}
  local section_lines = {
    [3] = { name = "Unstaged changes", section = "unstaged" },
  }

  local s = scope.resolve(3, line_map, section_lines)

  eq(s.type, "section")
  eq(s.section_key, "unstaged")
end

T["expansion.scope"]["resolve() returns file scope when cursor on file line"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local line_map = {
    [5] = { type = "file", path = "src/main.lua", section = "unstaged" },
  }
  local section_lines = {}

  local s = scope.resolve(5, line_map, section_lines)

  eq(s.type, "file")
  eq(s.section_key, "unstaged")
  eq(s.file_key, "unstaged:src/main.lua")
end

T["expansion.scope"]["resolve() returns hunk scope when cursor on hunk header"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local line_map = {
    [7] = {
      type = "file",
      path = "src/main.lua",
      section = "unstaged",
      is_hunk_header = true,
      hunk_index = 2,
    },
  }
  local section_lines = {}

  local s = scope.resolve(7, line_map, section_lines)

  eq(s.type, "hunk")
  eq(s.section_key, "unstaged")
  eq(s.file_key, "unstaged:src/main.lua")
  eq(s.hunk_index, 2)
end

T["expansion.scope"]["resolve() returns file scope for diff line that is not hunk header"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local line_map = {
    [8] = {
      type = "file",
      path = "src/main.lua",
      section = "unstaged",
      hunk_index = 2,
      is_hunk_header = false,
    },
  }
  local section_lines = {}

  local s = scope.resolve(8, line_map, section_lines)

  eq(s.type, "file")
  eq(s.file_key, "unstaged:src/main.lua")
end

-- find_parent_section tests
T["expansion.scope"]["find_parent_section() returns nil when no sections"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local section_lines = {}

  local section_key, section_line = scope.find_parent_section(10, section_lines)

  eq(section_key, nil)
  eq(section_line, nil)
end

T["expansion.scope"]["find_parent_section() finds closest section above"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local section_lines = {
    [2] = { section = "staged" },
    [10] = { section = "unstaged" },
    [20] = { section = "untracked" },
  }

  local section_key, section_line = scope.find_parent_section(15, section_lines)

  eq(section_key, "unstaged")
  eq(section_line, 10)
end

T["expansion.scope"]["find_parent_section() returns section when cursor is on section header"] = function()
  local scope = require("gitlad.state.expansion.scope")

  local section_lines = {
    [10] = { section = "unstaged" },
  }

  local section_key, section_line = scope.find_parent_section(10, section_lines)

  eq(section_key, "unstaged")
  eq(section_line, 10)
end

return T
