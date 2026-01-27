---@diagnostic disable: undefined-field
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["expansion.commands"] = MiniTest.new_set()

T["expansion.commands"]["toggle_file creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.toggle_file("unstaged:file.txt")

  eq(cmd.type, "toggle_file")
  eq(cmd.file_key, "unstaged:file.txt")
end

T["expansion.commands"]["toggle_section creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.toggle_section("staged")

  eq(cmd.type, "toggle_section")
  eq(cmd.section_key, "staged")
end

T["expansion.commands"]["toggle_hunk creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.toggle_hunk("unstaged:file.txt", 2)

  eq(cmd.type, "toggle_hunk")
  eq(cmd.file_key, "unstaged:file.txt")
  eq(cmd.hunk_index, 2)
  eq(cmd.total_hunks, nil)
end

T["expansion.commands"]["toggle_hunk includes total_hunks when provided"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.toggle_hunk("unstaged:file.txt", 2, 5)

  eq(cmd.type, "toggle_hunk")
  eq(cmd.file_key, "unstaged:file.txt")
  eq(cmd.hunk_index, 2)
  eq(cmd.total_hunks, 5)
end

T["expansion.commands"]["set_file_expansion creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.set_file_expansion("unstaged:file.txt", "headers")

  eq(cmd.type, "set_file_expansion")
  eq(cmd.file_key, "unstaged:file.txt")
  eq(cmd.value, "headers")
end

T["expansion.commands"]["set_visibility_level creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local file_scope = scope.file("unstaged", "unstaged:file.txt")
  local cmd = commands.set_visibility_level(3, file_scope)

  eq(cmd.type, "set_visibility_level")
  eq(cmd.level, 3)
  eq(cmd.scope.type, "file")
  eq(cmd.scope.file_key, "unstaged:file.txt")
end

T["expansion.commands"]["set_visibility_level includes context when provided"] = function()
  local commands = require("gitlad.state.expansion.commands")
  local scope = require("gitlad.state.expansion.scope")

  local cmd = commands.set_visibility_level(4, scope.global(), {
    sections = { "staged", "unstaged" },
    file_keys = { "unstaged:file.txt" },
    commit_hashes = { "abc123" },
  })

  eq(cmd.type, "set_visibility_level")
  eq(cmd.level, 4)
  eq(cmd.sections, { "staged", "unstaged" })
  eq(cmd.file_keys, { "unstaged:file.txt" })
  eq(cmd.commit_hashes, { "abc123" })
end

T["expansion.commands"]["toggle_all_sections creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.toggle_all_sections({ "staged", "unstaged" }, false)

  eq(cmd.type, "toggle_all_sections")
  eq(cmd.sections, { "staged", "unstaged" })
  eq(cmd.all_collapsed, false)
end

T["expansion.commands"]["reset creates correct command"] = function()
  local commands = require("gitlad.state.expansion.commands")

  local cmd = commands.reset()

  eq(cmd.type, "reset")
end

return T
