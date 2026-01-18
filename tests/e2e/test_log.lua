-- E2E tests for log functionality
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to create a test git repository
local function create_test_repo(child_nvim)
  local repo = child_nvim.lua_get("vim.fn.tempname()")
  child_nvim.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init")
    vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")
  ]],
    repo
  ))
  return repo
end

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
-- Log popup tests
-- =============================================================================

T["log popup"] = MiniTest.new_set()

T["log popup"]["opens from status buffer with l key"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit so status works
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Press l to open log popup
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")

  -- Should have a popup window
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count > 1, true)

  -- Buffer should contain "Log" (popup title)
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_log = false
  for _, line in ipairs(lines) do
    if line:match("Log") then
      found_log = true
      break
    end
  end
  eq(found_log, true)

  cleanup_test_repo(child, repo)
end

T["log popup"]["has switches and options"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have switches
  expect.equality(content:match("All branches") ~= nil, true)

  -- Should have options
  expect.equality(content:match("Limit") ~= nil, true)

  -- Should have actions
  expect.equality(content:match("Log current") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log popup"]["closes with q"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  child.type_keys("q")
  child.lua("vim.wait(200, function() end)")

  local win_count_after = child.lua_get("vim.fn.winnr('$')")

  -- Window should have closed
  eq(win_count_after < win_count_before, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Log view tests
-- =============================================================================

T["log view"] = MiniTest.new_set()

T["log view"]["opens when action is triggered"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create some commits to show
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'Add file1'")

  create_file(child, repo, "file2.txt", "content 2")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Add file2'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log popup
  child.type_keys("l")
  child.lua("vim.wait(200, function() end)")

  -- Trigger "log current branch" action
  child.type_keys("l")
  child.lua("vim.wait(1000, function() end)")

  -- Should now be in log buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name:match("gitlad://log") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["displays commits"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commits
  create_file(child, repo, "file1.txt", "content")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'First commit'")

  create_file(child, repo, "file2.txt", "content")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Second commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log view
  child.type_keys("ll")
  child.lua("vim.wait(1000, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should show commit messages
  expect.equality(content:match("First commit") ~= nil, true)
  expect.equality(content:match("Second commit") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["can yank commit hash with y"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create a commit
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log view
  child.type_keys("ll")
  child.lua("vim.wait(1000, function() end)")

  -- Navigate to first commit (after header)
  child.type_keys("j")
  child.lua("vim.wait(100, function() end)")

  -- Yank the hash
  child.type_keys("y")
  child.lua("vim.wait(200, function() end)")

  -- Check clipboard has a hash-like value
  local reg = child.lua_get("vim.fn.getreg('\"')")
  -- Should be a hex string (commit hash)
  expect.equality(reg:match("^%x+$") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["closes with q"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Test'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log view
  child.type_keys("ll")
  child.lua("vim.wait(1000, function() end)")

  -- Verify in log buffer
  local buf_name_before = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name_before:match("gitlad://log") ~= nil, true)

  -- Close with q
  child.type_keys("q")
  child.lua("vim.wait(200, function() end)")

  -- Should be back in status or previous buffer
  local buf_name_after = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name_after:match("gitlad://log") == nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["j/k keymaps are set up"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commits
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add file1.txt")
  git(child, repo, "commit -m 'Commit 1'")

  create_file(child, repo, "file2.txt", "content 2")
  git(child, repo, "add file2.txt")
  git(child, repo, "commit -m 'Commit 2'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open log view
  child.type_keys("ll")
  child.lua("vim.wait(1000, function() end)")

  -- Verify we're in the log buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name:match("gitlad://log") ~= nil, true)

  -- Check that j and k keymaps exist by checking if they have mappings
  child.lua([[
    _G.has_j = false
    _G.has_k = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "j" then _G.has_j = true end
      if km.lhs == "k" then _G.has_k = true end
    end
  ]])
  local has_j = child.lua_get("_G.has_j")
  local has_k = child.lua_get("_G.has_k")
  eq(has_j, true)
  eq(has_k, true)

  cleanup_test_repo(child, repo)
end

return T
