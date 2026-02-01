-- Tests for gitlad.git.parse worktree parsing
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_worktree_list"] = MiniTest.new_set()

T["parse_worktree_list"]["parses basic worktree"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/main-repo",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
    "",
  })

  eq(#result, 1)
  eq(result[1].path, "/path/to/main-repo")
  eq(result[1].head, "abc123def456abc123def456abc123def456abc123")
  eq(result[1].branch, "main")
  eq(result[1].is_main, true)
  eq(result[1].is_bare, false)
  eq(result[1].locked, false)
  eq(result[1].prunable, false)
end

T["parse_worktree_list"]["parses multiple worktrees"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/main-repo",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
    "",
    "worktree /path/to/feature-worktree",
    "HEAD def456abc123def456abc123def456abc123def456",
    "branch refs/heads/feature/awesome",
    "",
  })

  eq(#result, 2)
  eq(result[1].path, "/path/to/main-repo")
  eq(result[1].branch, "main")
  eq(result[1].is_main, true)
  eq(result[2].path, "/path/to/feature-worktree")
  eq(result[2].branch, "feature/awesome")
  eq(result[2].is_main, false)
end

T["parse_worktree_list"]["parses detached HEAD worktree"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/main",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
    "",
    "worktree /path/to/detached",
    "HEAD def456abc123def456abc123def456abc123def456",
    "detached",
    "",
  })

  eq(#result, 2)
  eq(result[1].branch, "main")
  eq(result[2].path, "/path/to/detached")
  eq(result[2].branch, nil)
end

T["parse_worktree_list"]["parses locked worktree without reason"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/main",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
    "",
    "worktree /path/to/locked",
    "HEAD def456abc123def456abc123def456abc123def456",
    "branch refs/heads/feature",
    "locked",
    "",
  })

  eq(#result, 2)
  eq(result[2].locked, true)
  eq(result[2].lock_reason, nil)
end

T["parse_worktree_list"]["parses locked worktree with reason"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/locked",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/feature",
    "locked external drive backup",
    "",
  })

  eq(#result, 1)
  eq(result[1].locked, true)
  eq(result[1].lock_reason, "external drive backup")
end

T["parse_worktree_list"]["parses prunable worktree"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/main",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
    "",
    "worktree /path/to/stale",
    "HEAD def456abc123def456abc123def456abc123def456",
    "branch refs/heads/stale-branch",
    "prunable gitdir file points to non-existent location",
    "",
  })

  eq(#result, 2)
  eq(result[2].prunable, true)
  eq(result[2].prune_reason, "gitdir file points to non-existent location")
end

T["parse_worktree_list"]["parses bare repository"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/bare.git",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "bare",
    "",
    "worktree /path/to/worktree",
    "HEAD def456abc123def456abc123def456abc123def456",
    "branch refs/heads/main",
    "",
  })

  eq(#result, 2)
  eq(result[1].is_bare, true)
  eq(result[1].branch, nil)
  eq(result[2].is_bare, false)
end

T["parse_worktree_list"]["handles worktree with all attributes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/complex",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/feature/complex",
    "locked protecting important work",
    "",
  })

  eq(#result, 1)
  eq(result[1].path, "/path/to/complex")
  eq(result[1].head, "abc123def456abc123def456abc123def456abc123")
  eq(result[1].branch, "feature/complex")
  eq(result[1].locked, true)
  eq(result[1].lock_reason, "protecting important work")
  eq(result[1].is_main, true)
end

T["parse_worktree_list"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({})

  eq(#result, 0)
end

T["parse_worktree_list"]["handles input without trailing blank line"] = function()
  local parse = require("gitlad.git.parse")

  -- Some git versions might not include trailing blank line
  local result = parse.parse_worktree_list({
    "worktree /path/to/repo",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
  })

  eq(#result, 1)
  eq(result[1].path, "/path/to/repo")
  eq(result[1].branch, "main")
end

T["parse_worktree_list"]["marks only first worktree as main"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/first",
    "HEAD aaa",
    "branch refs/heads/main",
    "",
    "worktree /path/to/second",
    "HEAD bbb",
    "branch refs/heads/feature1",
    "",
    "worktree /path/to/third",
    "HEAD ccc",
    "branch refs/heads/feature2",
    "",
  })

  eq(#result, 3)
  eq(result[1].is_main, true)
  eq(result[2].is_main, false)
  eq(result[3].is_main, false)
end

T["parse_worktree_list"]["strips refs/heads/ prefix from branch name"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/to/repo",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/feature/nested/deep/branch",
    "",
  })

  eq(#result, 1)
  eq(result[1].branch, "feature/nested/deep/branch")
end

T["parse_worktree_list"]["handles paths with spaces"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_worktree_list({
    "worktree /path/with spaces/to repo",
    "HEAD abc123def456abc123def456abc123def456abc123",
    "branch refs/heads/main",
    "",
  })

  eq(#result, 1)
  eq(result[1].path, "/path/with spaces/to repo")
end

return T
