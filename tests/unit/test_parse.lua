-- Tests for gitlad.git.parse module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_status"] = MiniTest.new_set()

T["parse_status"]["parses branch header"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123def456",
  })

  eq(result.branch, "main")
  eq(result.oid, "abc123def456")
end

T["parse_status"]["parses upstream info"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "# branch.upstream origin/main",
    "# branch.ab +2 -1",
  })

  eq(result.upstream, "origin/main")
  eq(result.ahead, 2)
  eq(result.behind, 1)
end

T["parse_status"]["parses untracked files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "? newfile.txt",
    "? another.lua",
  })

  eq(#result.untracked, 2)
  eq(result.untracked[1].path, "newfile.txt")
  eq(result.untracked[2].path, "another.lua")
end

T["parse_status"]["parses staged files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 abc123def456abc123def456abc123def456abc123 staged.txt",
  })

  eq(#result.staged, 1)
  eq(result.staged[1].path, "staged.txt")
  eq(result.staged[1].index_status, "A")
end

T["parse_status"]["parses unstaged files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "1 .M N... 100644 100644 100644 abc123def456abc123def456abc123def456abc123 abc123def456abc123def456abc123def456abc123 modified.txt",
  })

  eq(#result.unstaged, 1)
  eq(result.unstaged[1].path, "modified.txt")
  eq(result.unstaged[1].worktree_status, "M")
end

T["parse_status"]["parses file with both staged and unstaged changes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "1 MM N... 100644 100644 100644 abc123def456abc123def456abc123def456abc123 abc123def456abc123def456abc123def456abc123 both.txt",
  })

  eq(#result.staged, 1)
  eq(#result.unstaged, 1)
  eq(result.staged[1].path, "both.txt")
  eq(result.unstaged[1].path, "both.txt")
end

T["parse_status"]["parses renamed files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "2 R. N... 100644 100644 100644 abc123def456abc123def456abc123def456abc123 abc123def456abc123def456abc123def456abc123 R100 newname.txt\toldname.txt",
  })

  eq(#result.staged, 1)
  eq(result.staged[1].path, "newname.txt")
  eq(result.staged[1].orig_path, "oldname.txt")
end

T["parse_status"]["parses conflicted files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "u UU N... 100644 100644 100644 100644 abc123 def456 789abc conflict.txt",
  })

  eq(#result.conflicted, 1)
  eq(result.conflicted[1].path, "conflict.txt")
end

T["parse_status"]["handles empty status"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
  })

  eq(#result.staged, 0)
  eq(#result.unstaged, 0)
  eq(#result.untracked, 0)
  eq(#result.conflicted, 0)
end

T["parse_branches"] = MiniTest.new_set()

T["parse_branches"]["parses branch list"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({
    "  feature/branch",
    "* main",
    "  develop",
  })

  eq(#result, 3)
  eq(result[1].name, "feature/branch")
  eq(result[1].current, false)
  eq(result[2].name, "main")
  eq(result[2].current, true)
  eq(result[3].name, "develop")
  eq(result[3].current, false)
end

T["status_description"] = MiniTest.new_set()

T["status_description"]["returns correct descriptions"] = function()
  local parse = require("gitlad.git.parse")

  eq(parse.status_description("M"), "modified")
  eq(parse.status_description("A"), "added")
  eq(parse.status_description("D"), "deleted")
  eq(parse.status_description("."), "unmodified")
  eq(parse.status_description("X"), "unknown")
end

return T
