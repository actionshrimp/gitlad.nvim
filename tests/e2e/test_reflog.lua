-- E2E tests for reflog functionality
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
-- Log popup reflog group tests
-- =============================================================================

T["log popup reflog group"] = MiniTest.new_set()

T["log popup reflog group"]["shows reflog actions in log popup"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Press l to open log popup
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")

  -- Buffer should contain Reflog section
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_reflog = false
  local found_current = false
  local found_head = false
  local found_other = false
  for _, line in ipairs(lines) do
    if line:match("Reflog") then
      found_reflog = true
    end
    if line:match("r%s+Reflog current") then
      found_current = true
    end
    if line:match("H%s+Reflog HEAD") then
      found_head = true
    end
    if line:match("O%s+Reflog other") then
      found_other = true
    end
  end
  eq(found_reflog, true)
  eq(found_current, true)
  eq(found_head, true)
  eq(found_other, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Reflog view tests
-- =============================================================================

T["reflog view"] = MiniTest.new_set()

T["reflog view"]["opens via l H keybinding"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create some commits to have reflog entries
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'First commit'")

  create_file(child, repo, "file2.txt", "content2")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Second commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Press l then H to open HEAD reflog
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")
  child.type_keys("H")
  child.lua("vim.wait(500, function() end)")

  -- Should be in reflog buffer
  local bufname = child.lua_get("vim.api.nvim_buf_get_name(0)")
  assert(bufname:find("reflog"), "Should be in reflog buffer")

  -- Buffer should contain reflog header
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_header = false
  for _, line in ipairs(lines) do
    if line:match("Reflog for HEAD") then
      found_header = true
      break
    end
  end
  eq(found_header, true)

  cleanup_test_repo(child, repo)
end

T["reflog view"]["shows commit entries"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'First commit'")

  create_file(child, repo, "file2.txt", "content2")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Second commit'")

  -- Open status and reflog
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")
  child.type_keys("H")
  child.lua("vim.wait(500, function() end)")

  -- Buffer should show commit entries with HEAD@{n} selectors
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_selector = false
  local found_commit_action = false
  for _, line in ipairs(lines) do
    if line:match("HEAD@{%d+}") then
      found_selector = true
    end
    if line:match("commit") then
      found_commit_action = true
    end
  end
  eq(found_selector, true)
  eq(found_commit_action, true)

  cleanup_test_repo(child, repo)
end

T["reflog view"]["shows checkout entries after branch operations"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create and checkout a branch (creates checkout reflog entry)
  git(child, repo, "checkout -b feature")
  git(child, repo, "checkout master 2>/dev/null || git checkout main")

  -- Open status and reflog
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")
  child.type_keys("H")
  child.lua("vim.wait(500, function() end)")

  -- Buffer should show checkout entries
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_checkout = false
  for _, line in ipairs(lines) do
    if line:match("checkout") then
      found_checkout = true
      break
    end
  end
  eq(found_checkout, true)

  cleanup_test_repo(child, repo)
end

T["reflog view"]["closes with q"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status and reflog
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")
  child.type_keys("H")
  child.lua("vim.wait(500, function() end)")

  -- Verify we're in reflog buffer
  local bufname = child.lua_get("vim.api.nvim_buf_get_name(0)")
  assert(bufname:find("reflog"), "Should be in reflog buffer")

  -- Press q to close
  child.type_keys("q")
  child.lua("vim.wait(200, function() end)")

  -- Should be back in status buffer
  bufname = child.lua_get("vim.api.nvim_buf_get_name(0)")
  assert(bufname:find("status") or bufname:find("gitlad"), "Should be back in status buffer")

  cleanup_test_repo(child, repo)
end

T["reflog view"]["yanks hash with y"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status and reflog
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")
  child.type_keys("H")
  child.lua("vim.wait(500, function() end)")

  -- Move to first entry and yank
  child.type_keys("gj") -- Move to first entry
  child.type_keys("y")
  child.lua("vim.wait(100, function() end)")

  -- Check unnamed register contains a hash (7+ hex chars)
  -- Use unnamed register '"' instead of '+' since system clipboard may not work on CI
  local register = child.lua_get('vim.fn.getreg([["]])')
  assert(register:match("^%x%x%x%x%x%x%x"), "Register should contain commit hash")

  cleanup_test_repo(child, repo)
end

T["reflog view"]["navigates with gj/gk"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create multiple commits
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'First commit'")

  create_file(child, repo, "file2.txt", "content2")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Second commit'")

  create_file(child, repo, "file3.txt", "content3")
  git(child, repo, "add file3.txt")
  git(child, repo, "commit -m 'Third commit'")

  -- Open status and reflog
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")
  child.type_keys("H")
  child.lua("vim.wait(500, function() end)")

  -- Get initial cursor line
  local initial_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")

  -- Move down
  child.type_keys("gj")
  local after_down = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert(after_down > initial_line, "gj should move cursor down")

  -- Move up
  child.type_keys("gk")
  local after_up = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert(after_up < after_down, "gk should move cursor up")

  cleanup_test_repo(child, repo)
end

return T
