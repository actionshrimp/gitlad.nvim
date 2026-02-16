---@diagnostic disable: undefined-global
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_rebase_todo_lines"] = MiniTest.new_set()

T["parse_rebase_todo_lines"]["parses pick actions"] = function()
  local git = require("gitlad.git")

  local lines = {
    "pick abc1234 First commit",
    "pick def5678 Second commit",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 2)
  eq(entries[1].action, "pick")
  eq(entries[1].hash, "abc1234")
  eq(entries[1].subject, "First commit")
  eq(entries[2].action, "pick")
  eq(entries[2].hash, "def5678")
  eq(entries[2].subject, "Second commit")
end

T["parse_rebase_todo_lines"]["parses various action types"] = function()
  local git = require("gitlad.git")

  local lines = {
    "pick abc1234 Pick this",
    "reword def5678 Reword this",
    "edit ghi9012 Edit this",
    "squash jkl3456 Squash this",
    "fixup mno7890 Fixup this",
    "drop pqr1234 Drop this",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 6)
  eq(entries[1].action, "pick")
  eq(entries[2].action, "reword")
  eq(entries[3].action, "edit")
  eq(entries[4].action, "squash")
  eq(entries[5].action, "fixup")
  eq(entries[6].action, "drop")
end

T["parse_rebase_todo_lines"]["parses short aliases"] = function()
  local git = require("gitlad.git")

  local lines = {
    "p abc1234 Pick alias",
    "r def5678 Reword alias",
    "e ghi9012 Edit alias",
    "s jkl3456 Squash alias",
    "f mno7890 Fixup alias",
    "d pqr1234 Drop alias",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 6)
  eq(entries[1].action, "pick")
  eq(entries[2].action, "reword")
  eq(entries[3].action, "edit")
  eq(entries[4].action, "squash")
  eq(entries[5].action, "fixup")
  eq(entries[6].action, "drop")
end

T["parse_rebase_todo_lines"]["parses exec action"] = function()
  local git = require("gitlad.git")

  local lines = {
    "exec make test",
    "x echo hello",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 2)
  eq(entries[1].action, "exec")
  eq(entries[1].hash, nil)
  eq(entries[1].subject, "make test")
  eq(entries[2].action, "exec")
  eq(entries[2].subject, "echo hello")
end

T["parse_rebase_todo_lines"]["parses break action"] = function()
  local git = require("gitlad.git")

  local lines = {
    "break",
    "b",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 2)
  eq(entries[1].action, "break")
  eq(entries[1].hash, nil)
  eq(entries[1].subject, nil)
  eq(entries[2].action, "break")
end

T["parse_rebase_todo_lines"]["parses label and reset actions"] = function()
  local git = require("gitlad.git")

  local lines = {
    "label onto",
    "reset onto",
    "update-ref refs/heads/feature",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 3)
  eq(entries[1].action, "label")
  eq(entries[1].hash, nil)
  eq(entries[1].subject, "onto")
  eq(entries[2].action, "reset")
  eq(entries[2].subject, "onto")
  eq(entries[3].action, "update-ref")
  eq(entries[3].subject, "refs/heads/feature")
end

T["parse_rebase_todo_lines"]["parses fixup with flags"] = function()
  local git = require("gitlad.git")

  local lines = {
    "fixup -C abc1234 Fixup with message",
    "fixup -c def5678 Fixup with edit",
    "fixup ghi9012 Normal fixup",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 3)
  eq(entries[1].action, "fixup")
  eq(entries[1].hash, "abc1234")
  eq(entries[1].subject, "Fixup with message")
  eq(entries[2].action, "fixup")
  eq(entries[2].hash, "def5678")
  eq(entries[2].subject, "Fixup with edit")
  eq(entries[3].action, "fixup")
  eq(entries[3].hash, "ghi9012")
  eq(entries[3].subject, "Normal fixup")
end

T["parse_rebase_todo_lines"]["skips comment lines"] = function()
  local git = require("gitlad.git")

  local lines = {
    "pick abc1234 First commit",
    "# This is a comment",
    "  # Indented comment",
    "pick def5678 Second commit",
    "# Commands:",
    "# p, pick = use commit",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 2)
  eq(entries[1].hash, "abc1234")
  eq(entries[2].hash, "def5678")
end

T["parse_rebase_todo_lines"]["skips empty lines"] = function()
  local git = require("gitlad.git")

  local lines = {
    "pick abc1234 First commit",
    "",
    "pick def5678 Second commit",
    "",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 2)
end

T["parse_rebase_todo_lines"]["handles empty input"] = function()
  local git = require("gitlad.git")

  local entries = git.parse_rebase_todo_lines({})

  eq(#entries, 0)
end

T["parse_rebase_todo_lines"]["handles mixed todo file"] = function()
  local git = require("gitlad.git")

  local lines = {
    "pick abc1234 Add feature A",
    "squash def5678 Fix typo in A",
    "exec make test",
    "pick ghi9012 Add feature B",
    "fixup -C jkl3456 Improve B message",
    "break",
    "pick mno7890 Add feature C",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 7)
  eq(entries[1].action, "pick")
  eq(entries[2].action, "squash")
  eq(entries[3].action, "exec")
  eq(entries[3].subject, "make test")
  eq(entries[4].action, "pick")
  eq(entries[5].action, "fixup")
  eq(entries[6].action, "break")
  eq(entries[7].action, "pick")
end

T["parse_rebase_todo_lines"]["handles done file format"] = function()
  local git = require("gitlad.git")

  -- Done file has the same format as todo file
  local lines = {
    "pick abc1234 Already applied commit 1",
    "pick def5678 Already applied commit 2",
    "reword ghi9012 Reworded commit",
  }

  local entries = git.parse_rebase_todo_lines(lines)

  eq(#entries, 3)
  eq(entries[1].action, "pick")
  eq(entries[1].hash, "abc1234")
  eq(entries[2].action, "pick")
  eq(entries[3].action, "reword")
end

return T
