local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_blame_porcelain"] = MiniTest.new_set()

T["parse_blame_porcelain"]["parses single commit with one line"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "b4292f5abc123def456789012345678901234567 1 1 1",
    "author Dave",
    "author-mail <dave@example.com>",
    "author-time 1705420800",
    "author-tz +0000",
    "committer Dave",
    "committer-mail <dave@example.com>",
    "committer-time 1705420800",
    "committer-tz +0000",
    "summary initial commit",
    "filename init.lua",
    "\tlocal M = {}",
  }

  local result = parse.parse_blame_porcelain(output)

  eq(#result.lines, 1)
  eq(result.lines[1].hash, "b4292f5abc123def456789012345678901234567")
  eq(result.lines[1].orig_line, 1)
  eq(result.lines[1].final_line, 1)
  eq(result.lines[1].content, "local M = {}")

  local commit = result.commits["b4292f5abc123def456789012345678901234567"]
  expect.no_equality(commit, nil)
  eq(commit.author, "Dave")
  eq(commit.author_time, 1705420800)
  eq(commit.summary, "initial commit")
  eq(commit.filename, "init.lua")
  eq(commit.boundary, false)
end

T["parse_blame_porcelain"]["parses multiple commits"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 2",
    "author Alice",
    "author-time 1705420800",
    "summary first commit",
    "filename file.lua",
    "\tline one",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 2 2",
    "\tline two",
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 3 3 1",
    "author Bob",
    "author-time 1705507200",
    "summary second commit",
    "filename file.lua",
    "\tline three",
  }

  local result = parse.parse_blame_porcelain(output)

  eq(#result.lines, 3)

  -- First two lines from commit aaa
  eq(result.lines[1].hash, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  eq(result.lines[1].content, "line one")
  eq(result.lines[2].hash, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  eq(result.lines[2].content, "line two")

  -- Third line from commit bbb
  eq(result.lines[3].hash, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
  eq(result.lines[3].content, "line three")

  -- Two unique commits
  local commit_count = 0
  for _ in pairs(result.commits) do
    commit_count = commit_count + 1
  end
  eq(commit_count, 2)

  eq(result.commits["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].author, "Alice")
  eq(result.commits["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"].author, "Bob")
end

T["parse_blame_porcelain"]["handles boundary commits"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "cccccccccccccccccccccccccccccccccccccccc 1 1 1",
    "author Charlie",
    "author-time 1705420800",
    "summary root commit",
    "boundary",
    "filename readme.md",
    "\t# README",
  }

  local result = parse.parse_blame_porcelain(output)

  local commit = result.commits["cccccccccccccccccccccccccccccccccccccccc"]
  eq(commit.boundary, true)
end

T["parse_blame_porcelain"]["handles uncommitted lines"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "0000000000000000000000000000000000000000 1 1 1",
    "author Not Committed Yet",
    "author-time 1705420800",
    "summary Not Yet Committed",
    "filename new_file.lua",
    "\tuncommitted content",
  }

  local result = parse.parse_blame_porcelain(output)

  eq(#result.lines, 1)
  eq(result.lines[1].hash, "0000000000000000000000000000000000000000")
  eq(result.lines[1].content, "uncommitted content")

  local commit = result.commits["0000000000000000000000000000000000000000"]
  eq(commit.author, "Not Committed Yet")
  eq(commit.summary, "Not Yet Committed")
end

T["parse_blame_porcelain"]["parses previous field for renames"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "dddddddddddddddddddddddddddddddddddddddd 1 1 1",
    "author Dave",
    "author-time 1705420800",
    "summary rename file",
    "previous eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee old_name.lua",
    "filename new_name.lua",
    "\tcontent",
  }

  local result = parse.parse_blame_porcelain(output)

  local commit = result.commits["dddddddddddddddddddddddddddddddddddddddd"]
  eq(commit.previous_hash, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
  eq(commit.previous_filename, "old_name.lua")
end

T["parse_blame_porcelain"]["handles empty output"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_blame_porcelain({})

  eq(#result.lines, 0)
  local commit_count = 0
  for _ in pairs(result.commits) do
    commit_count = commit_count + 1
  end
  eq(commit_count, 0)
  eq(result.file, "")
end

T["parse_blame_porcelain"]["sets file from first filename seen"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 1",
    "author Alice",
    "author-time 1705420800",
    "summary commit",
    "filename my_file.lua",
    "\tcontent",
  }

  local result = parse.parse_blame_porcelain(output)

  eq(result.file, "my_file.lua")
end

T["parse_blame_porcelain"]["handles tab-only content line (empty source line)"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 1",
    "author Alice",
    "author-time 1705420800",
    "summary commit",
    "filename file.lua",
    "\t",
  }

  local result = parse.parse_blame_porcelain(output)

  eq(#result.lines, 1)
  eq(result.lines[1].content, "")
end

T["parse_blame_porcelain"]["preserves line numbering across chunks"] = function()
  local parse = require("gitlad.git.parse")

  local output = {
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 1",
    "author Alice",
    "author-time 1705420800",
    "summary first",
    "filename f.lua",
    "\tline 1",
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 5 2 1",
    "author Bob",
    "author-time 1705507200",
    "summary second",
    "filename f.lua",
    "\tline 2",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 3 3",
    "\tline 3",
  }

  local result = parse.parse_blame_porcelain(output)

  eq(#result.lines, 3)
  eq(result.lines[1].final_line, 1)
  eq(result.lines[1].orig_line, 1)
  eq(result.lines[2].final_line, 2)
  eq(result.lines[2].orig_line, 5)
  eq(result.lines[3].final_line, 3)
  eq(result.lines[3].orig_line, 3)
end

return T
