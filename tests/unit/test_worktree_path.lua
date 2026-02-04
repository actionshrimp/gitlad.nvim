-- Tests for worktree path generation strategies
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local worktree = require("gitlad.popups.worktree")

T["generate_sibling_path"] = MiniTest.new_set()

T["generate_sibling_path"]["creates path with repo name prefix"] = function()
  local result = worktree._generate_sibling_path("/path/to/repo", "feature")
  eq(result, "/path/to/repo_feature")
end

T["generate_sibling_path"]["replaces slashes in branch names with dashes"] = function()
  local result = worktree._generate_sibling_path("/path/to/repo", "feature/awesome")
  eq(result, "/path/to/repo_feature-awesome")
end

T["generate_sibling_path"]["handles trailing slash in repo_root"] = function()
  -- This is the bug fix - vim.fn.fnamemodify with :p adds trailing slash
  local result = worktree._generate_sibling_path("/path/to/repo/", "feature")
  eq(result, "/path/to/repo_feature")
end

T["generate_sibling_path"]["works in worktree scenario (main worktree)"] = function()
  -- User's scenario: they're in repo-name/main and want sibling worktrees
  local result = worktree._generate_sibling_path("/code/myproject/main", "feature/foo")
  eq(result, "/code/myproject/main_feature-foo")
end

T["generate_sibling_path"]["handles trailing slash in worktree scenario"] = function()
  local result = worktree._generate_sibling_path("/code/myproject/main/", "feature/foo")
  eq(result, "/code/myproject/main_feature-foo")
end

T["generate_sibling_path"]["handles deeply nested paths"] = function()
  local result = worktree._generate_sibling_path("/a/b/c/d/repo", "branch")
  eq(result, "/a/b/c/d/repo_branch")
end

T["generate_sibling_bare_path"] = MiniTest.new_set()

T["generate_sibling_bare_path"]["creates path with just branch name"] = function()
  local result = worktree._generate_sibling_bare_path("/path/to/main", "feature")
  eq(result, "/path/to/feature")
end

T["generate_sibling_bare_path"]["replaces slashes in branch names with dashes"] = function()
  local result = worktree._generate_sibling_bare_path("/path/to/main", "feature/awesome")
  eq(result, "/path/to/feature-awesome")
end

T["generate_sibling_bare_path"]["handles trailing slash in repo_root"] = function()
  local result = worktree._generate_sibling_bare_path("/path/to/main/", "feature")
  eq(result, "/path/to/feature")
end

T["generate_sibling_bare_path"]["works for user's preferred structure"] = function()
  -- User wants: repo-name/main/, repo-name/branch1/, repo-name/branch2/
  -- When in repo-name/main, creating branch1 should give repo-name/branch1
  local result = worktree._generate_sibling_bare_path("/code/myproject/main", "branch1")
  eq(result, "/code/myproject/branch1")
end

T["generate_sibling_bare_path"]["handles complex branch names"] = function()
  local result = worktree._generate_sibling_bare_path("/code/repo/main", "feature/user/add-auth")
  eq(result, "/code/repo/feature-user-add-auth")
end

T["generate_sibling_bare_path"]["handles trailing slash in worktree scenario"] = function()
  local result = worktree._generate_sibling_bare_path("/code/myproject/main/", "feature/foo")
  eq(result, "/code/myproject/feature-foo")
end

return T
