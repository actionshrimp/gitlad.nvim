-- Tests for gitlad.state.commands module
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["stage_file"] = MiniTest.new_set()

T["stage_file"]["creates correct command structure"] = function()
  local commands = require("gitlad.state.commands")

  local cmd = commands.stage_file("file.txt", "unstaged")

  eq(cmd.type, "stage_file")
  eq(cmd.path, "file.txt")
  eq(cmd.from_section, "unstaged")
end

T["stage_file"]["accepts untracked section"] = function()
  local commands = require("gitlad.state.commands")

  local cmd = commands.stage_file("new.txt", "untracked")

  eq(cmd.type, "stage_file")
  eq(cmd.from_section, "untracked")
end

T["unstage_file"] = MiniTest.new_set()

T["unstage_file"]["creates correct command structure"] = function()
  local commands = require("gitlad.state.commands")

  local cmd = commands.unstage_file("file.txt")

  eq(cmd.type, "unstage_file")
  eq(cmd.path, "file.txt")
  eq(cmd.from_section, "staged")
end

T["refresh"] = MiniTest.new_set()

T["refresh"]["stores the status object"] = function()
  local commands = require("gitlad.state.commands")

  local status = { branch = "main", staged = {} }
  local cmd = commands.refresh(status)

  eq(cmd.type, "refresh")
  eq(cmd.status, status)
end

T["stage_all"] = MiniTest.new_set()

T["stage_all"]["creates correct command"] = function()
  local commands = require("gitlad.state.commands")

  local cmd = commands.stage_all()

  eq(cmd.type, "stage_all")
end

T["unstage_all"] = MiniTest.new_set()

T["unstage_all"]["creates correct command"] = function()
  local commands = require("gitlad.state.commands")

  local cmd = commands.unstage_all()

  eq(cmd.type, "unstage_all")
end

return T
