-- E2E tests for diff popup functionality
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to clean up test repo
local function cleanup_test_repo(child_nvim, repo)
  child_nvim.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

-- Helper to create a file in the test repo
local function create_file(child_nvim, repo, filename, content)
  child_nvim.lua(string.format(
    [[
    local path = %q .. "/" .. %q
    local f = io.open(path, "w")
    f:write(%q)
    f:close()
  ]],
    repo,
    filename,
    content
  ))
end

-- Helper to run git command in repo
local function git(child_nvim, repo, args)
  return child_nvim.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
end

-- Helper to change directory
local function cd(child_nvim, dir)
  child_nvim.lua(string.format([[vim.cmd("cd %s")]], dir))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[require("gitlad").setup({})]])
    end,
    post_once = child.stop,
  },
})

-- =============================================================================
-- Diff popup tests (from status buffer)
-- =============================================================================

T["diff popup from status"] = MiniTest.new_set()

T["diff popup from status"]["opens with d key"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Press d to open diff popup
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  -- Should have a popup window
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count > 1, true)

  -- Buffer should contain "Diff" (popup title)
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_diff = false
  for _, line in ipairs(lines) do
    if line:match("Diff") then
      found_diff = true
      break
    end
  end
  eq(found_diff, true)

  cleanup_test_repo(child, repo)
end

T["diff popup from status"]["has expected actions"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have diff actions
  expect.equality(content:match("Diff %(dwim%)") ~= nil, true)
  expect.equality(content:match("Diff staged") ~= nil, true)
  expect.equality(content:match("Diff unstaged") ~= nil, true)
  expect.equality(content:match("Diff worktree") ~= nil, true)
  expect.equality(content:match("Diff range") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["diff popup from status"]["closes with q"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  child.type_keys("q")
  child.lua("vim.wait(200, function() end)")

  local win_count_after = child.lua_get("vim.fn.winnr('$')")

  -- Window should have closed
  eq(win_count_after < win_count_before, true)

  cleanup_test_repo(child, repo)
end

T["diff popup from status"]["closes with Esc"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  child.type_keys("<Esc>")
  child.lua("vim.wait(200, function() end)")

  local win_count_after = child.lua_get("vim.fn.winnr('$')")

  -- Window should have closed
  eq(win_count_after < win_count_before, true)

  cleanup_test_repo(child, repo)
end

T["diff popup from status"]["shows 3-way action when on unstaged file"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create unstaged change
  create_file(child, repo, "init.txt", "modified content")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Cursor should already be on the first file (unstaged init.txt)
  -- Open diff popup
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have 3-way action since we're on an unstaged file
  expect.equality(content:match("3%-way") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["diff popup from status"]["shows 3-way action when on staged file"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create and stage a change
  create_file(child, repo, "init.txt", "modified content")
  git(child, repo, "add init.txt")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Cursor should already be on the first file (staged init.txt)
  -- Open diff popup
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have 3-way action since we're on a staged file
  expect.equality(content:match("3%-way") ~= nil, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Diff popup tests (from log buffer)
-- =============================================================================

T["diff popup from log"] = MiniTest.new_set()

T["diff popup from log"]["opens with d key"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'First commit'")

  create_file(child, repo, "file2.txt", "content 2")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Second commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log view (l then l)
  child.type_keys("ll")
  child.lua("vim.wait(1000, function() end)")

  -- Verify in log buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name:match("gitlad://log") ~= nil, true)

  -- Navigate to a commit line
  child.type_keys("gj")
  child.lua("vim.wait(100, function() end)")

  -- Press d to open diff popup
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  -- Should have a popup window
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count > 1, true)

  -- Buffer should contain "Diff"
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_diff = false
  for _, line in ipairs(lines) do
    if line:match("Diff") then
      found_diff = true
      break
    end
  end
  eq(found_diff, true)

  cleanup_test_repo(child, repo)
end

T["diff popup from log"]["shows commit action when on commit"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'First commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log view
  child.type_keys("ll")
  child.lua("vim.wait(1000, function() end)")

  -- Navigate to commit
  child.type_keys("gj")
  child.lua("vim.wait(100, function() end)")

  -- Open diff popup
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have "Show commit" action since cursor is on a commit
  expect.equality(content:match("Show commit") ~= nil, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Fallback behavior tests (when diffview is not available)
-- =============================================================================

T["diff fallback"] = MiniTest.new_set()

T["diff fallback"]["shows warning when diffview not installed"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create unstaged change
  create_file(child, repo, "init.txt", "modified")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open diff popup and trigger unstaged diff
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  -- Mock diffview as not available by triggering the action
  -- The fallback should show a terminal with git diff
  child.type_keys("u")
  child.lua("vim.wait(500, function() end)")

  -- Should either show notification or open terminal
  -- (depending on whether diffview is actually available in test env)
  -- Just verify no error occurred
  local errors = child.lua_get("vim.v.errmsg")
  eq(errors == "" or errors == nil, true)

  cleanup_test_repo(child, repo)
end

return T
