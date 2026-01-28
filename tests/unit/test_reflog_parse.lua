---@diagnostic disable: undefined-global
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_reflog"] = MiniTest.new_set()

-- Separator used in reflog format (ASCII record separator)
local SEP = "\30"

T["parse_reflog"]["parses basic reflog entries"] = function()
  local parse = require("gitlad.git.parse")

  local lines = {
    "abc1234" .. SEP .. "John Doe" .. SEP .. "HEAD@{0}" .. SEP .. "commit: Initial commit",
    "def5678"
      .. SEP
      .. "Jane Smith"
      .. SEP
      .. "HEAD@{1}"
      .. SEP
      .. "checkout: moving from main to feature",
    "ghi9012" .. SEP .. "John Doe" .. SEP .. "HEAD@{2}" .. SEP .. "reset: moving to HEAD~1",
  }

  local entries = parse.parse_reflog(lines)

  eq(#entries, 3)

  -- First entry
  eq(entries[1].hash, "abc1234")
  eq(entries[1].author, "John Doe")
  eq(entries[1].selector, "HEAD@{0}")
  eq(entries[1].subject, "commit: Initial commit")
  eq(entries[1].action_type, "commit")

  -- Second entry
  eq(entries[2].hash, "def5678")
  eq(entries[2].author, "Jane Smith")
  eq(entries[2].selector, "HEAD@{1}")
  eq(entries[2].subject, "checkout: moving from main to feature")
  eq(entries[2].action_type, "checkout")

  -- Third entry
  eq(entries[3].hash, "ghi9012")
  eq(entries[3].author, "John Doe")
  eq(entries[3].selector, "HEAD@{2}")
  eq(entries[3].subject, "reset: moving to HEAD~1")
  eq(entries[3].action_type, "reset")
end

T["parse_reflog"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")
  local entries = parse.parse_reflog({})
  eq(#entries, 0)
end

T["parse_reflog"]["handles branch-specific selectors"] = function()
  local parse = require("gitlad.git.parse")

  local lines = {
    "abc1234" .. SEP .. "John Doe" .. SEP .. "main@{0}" .. SEP .. "commit: Feature complete",
    "def5678"
      .. SEP
      .. "Jane Smith"
      .. SEP
      .. "feature/foo@{1}"
      .. SEP
      .. "branch: Created from HEAD",
  }

  local entries = parse.parse_reflog(lines)

  eq(#entries, 2)
  eq(entries[1].selector, "main@{0}")
  eq(entries[2].selector, "feature/foo@{1}")
  eq(entries[2].action_type, "branch")
end

T["parse_reflog"]["skips malformed lines"] = function()
  local parse = require("gitlad.git.parse")

  local lines = {
    "abc1234" .. SEP .. "John Doe" .. SEP .. "HEAD@{0}" .. SEP .. "commit: Valid entry",
    "malformed line without separators",
    "def5678" .. SEP .. "Jane Smith" .. SEP .. "HEAD@{1}" .. SEP .. "checkout: Another valid entry",
  }

  local entries = parse.parse_reflog(lines)

  eq(#entries, 2)
  eq(entries[1].hash, "abc1234")
  eq(entries[2].hash, "def5678")
end

T["extract_reflog_action_type"] = MiniTest.new_set()

T["extract_reflog_action_type"]["extracts basic action types"] = function()
  local parse = require("gitlad.git.parse")

  eq(parse.extract_reflog_action_type("commit: Initial commit"), "commit")
  eq(parse.extract_reflog_action_type("checkout: moving from main to feature"), "checkout")
  eq(parse.extract_reflog_action_type("reset: moving to HEAD~1"), "reset")
  eq(parse.extract_reflog_action_type("branch: Created from HEAD"), "branch")
  eq(parse.extract_reflog_action_type("pull: Fast-forward"), "pull")
  eq(parse.extract_reflog_action_type("clone: from https://github.com/user/repo"), "clone")
end

T["extract_reflog_action_type"]["extracts commit subtypes"] = function()
  local parse = require("gitlad.git.parse")

  -- commit (amend) should return "amend"
  eq(parse.extract_reflog_action_type("commit (amend): Fix typo"), "amend")

  -- commit (initial) should return "initial"
  eq(parse.extract_reflog_action_type("commit (initial): Initial commit"), "initial")

  -- commit (merge) should return "merge"
  eq(parse.extract_reflog_action_type("commit (merge): Merge branch 'feature'"), "merge")
end

T["extract_reflog_action_type"]["extracts rebase action types"] = function()
  local parse = require("gitlad.git.parse")

  -- All rebase variants should return "rebase"
  eq(parse.extract_reflog_action_type("rebase (start): checkout abc1234"), "rebase")
  eq(parse.extract_reflog_action_type("rebase (continue): pick def5678"), "rebase")
  eq(parse.extract_reflog_action_type("rebase (finish): refs/heads/feature onto abc1234"), "rebase")
  eq(parse.extract_reflog_action_type("rebase -i (start): checkout abc1234"), "rebase")
  eq(parse.extract_reflog_action_type("rebase (interactive) (start): checkout abc1234"), "rebase")
end

T["extract_reflog_action_type"]["handles merge action type"] = function()
  local parse = require("gitlad.git.parse")

  -- Various merge formats
  eq(parse.extract_reflog_action_type("merge feature-branch: Fast-forward"), "merge")
  eq(
    parse.extract_reflog_action_type("merge origin/main: Merge made by the 'ort' strategy"),
    "merge"
  )
end

T["extract_reflog_action_type"]["handles cherry-pick action type"] = function()
  local parse = require("gitlad.git.parse")

  eq(parse.extract_reflog_action_type("cherry-pick: picked abc1234"), "cherry-pick")
end

T["extract_reflog_action_type"]["handles empty and unknown subjects"] = function()
  local parse = require("gitlad.git.parse")

  eq(parse.extract_reflog_action_type(""), "unknown")
  eq(parse.extract_reflog_action_type(nil), "unknown")
  eq(parse.extract_reflog_action_type("some weird format without colon"), "unknown")
end

T["extract_reflog_action_type"]["handles rewritten action type"] = function()
  local parse = require("gitlad.git.parse")

  -- "rewritten" appears during rebases (like from filter-branch)
  eq(parse.extract_reflog_action_type("rewritten: abc1234 -> def5678"), "rewritten")
end

T["extract_reflog_action_type"]["handles restart action type"] = function()
  local parse = require("gitlad.git.parse")

  -- "restart" appears when restarting a checkout
  eq(parse.extract_reflog_action_type("restart: checkout main"), "restart")
end

return T
