-- E2E tests for multi-project support
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

-- Helper to wait
local function wait(child_nvim, ms)
  child_nvim.lua(string.format([[vim.wait(%d, function() return false end)]], ms))
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
-- Multi-project status buffer tests
-- =============================================================================

T["multi-project"] = MiniTest.new_set()

T["multi-project"]["can open status for two different repos without E95 error"] = function()
  -- Create two test repos
  local repo_a = create_test_repo(child)
  local repo_b = create_test_repo(child)

  -- Create initial commits so status works
  create_file(child, repo_a, "a.txt", "repo a content")
  git(child, repo_a, "add a.txt")
  git(child, repo_a, "commit -m 'Initial commit A'")

  create_file(child, repo_b, "b.txt", "repo b content")
  git(child, repo_b, "add b.txt")
  git(child, repo_b, "commit -m 'Initial commit B'")

  -- Open status for repo A
  cd(child, repo_a)
  child.cmd("Gitlad")
  wait(child, 300)

  local buf_a = child.lua_get("vim.api.nvim_get_current_buf()")
  local name_a = child.lua_get("vim.api.nvim_buf_get_name(0)")

  -- Verify we're in a gitlad status buffer
  local ft_a = child.lua_get("vim.bo.filetype")
  eq(ft_a, "gitlad")

  -- Open status for repo B (should NOT error with E95)
  cd(child, repo_b)
  child.cmd("Gitlad")
  wait(child, 300)

  local buf_b = child.lua_get("vim.api.nvim_get_current_buf()")
  local name_b = child.lua_get("vim.api.nvim_buf_get_name(0)")

  -- Verify we're in a gitlad status buffer
  local ft_b = child.lua_get("vim.bo.filetype")
  eq(ft_b, "gitlad")

  -- Different buffers should have been created
  eq(buf_a ~= buf_b, true)

  -- Names should contain repo paths (use plain match to handle special chars in temp paths)
  eq(name_a:find(repo_a, 1, true) ~= nil, true)
  eq(name_b:find(repo_b, 1, true) ~= nil, true)

  -- Cleanup
  cleanup_test_repo(child, repo_a)
  cleanup_test_repo(child, repo_b)
end

T["multi-project"]["reopening same repo focuses existing window"] = function()
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "content")
  git(child, repo, "add test.txt")
  git(child, repo, "commit -m 'Initial commit'")

  cd(child, repo)

  -- Open status
  child.cmd("Gitlad")
  wait(child, 300)

  local status_win = child.lua_get("vim.api.nvim_get_current_win()")
  local status_buf = child.lua_get("vim.api.nvim_get_current_buf()")

  -- Open a different buffer in a new split
  child.cmd("vsplit")
  child.cmd("enew")
  wait(child, 100)

  local new_win = child.lua_get("vim.api.nvim_get_current_win()")
  eq(new_win ~= status_win, true)

  -- Run :Gitlad again - should switch to existing status window
  child.cmd("Gitlad")
  wait(child, 100)

  local current_win = child.lua_get("vim.api.nvim_get_current_win()")
  local current_buf = child.lua_get("vim.api.nvim_get_current_buf()")

  eq(current_win, status_win)
  eq(current_buf, status_buf)

  -- Cleanup
  cleanup_test_repo(child, repo)
end

T["multi-project"]["each repo gets independent status buffer"] = function()
  -- Create two test repos with different content
  local repo_a = create_test_repo(child)
  local repo_b = create_test_repo(child)

  -- Create different files in each repo
  create_file(child, repo_a, "file_a.txt", "content a")
  git(child, repo_a, "add file_a.txt")
  git(child, repo_a, "commit -m 'Commit A'")
  create_file(child, repo_a, "unstaged_a.txt", "unstaged a")

  create_file(child, repo_b, "file_b.txt", "content b")
  git(child, repo_b, "add file_b.txt")
  git(child, repo_b, "commit -m 'Commit B'")
  create_file(child, repo_b, "unstaged_b.txt", "unstaged b")

  -- Open repo A's status
  cd(child, repo_a)
  child.cmd("Gitlad")
  wait(child, 500)

  -- Get buffer content for repo A
  local lines_a = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content_a = table.concat(lines_a, "\n")

  -- Should contain repo A's unstaged file
  eq(content_a:find("unstaged_a.txt", 1, true) ~= nil, true)

  -- Open repo B's status (in new window)
  child.cmd("vsplit")
  cd(child, repo_b)
  child.cmd("Gitlad")
  wait(child, 500)

  -- Get buffer content for repo B
  local lines_b = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content_b = table.concat(lines_b, "\n")

  -- Should contain repo B's unstaged file
  eq(content_b:find("unstaged_b.txt", 1, true) ~= nil, true)

  -- Content should be different
  eq(content_a ~= content_b, true)

  -- Cleanup
  cleanup_test_repo(child, repo_a)
  cleanup_test_repo(child, repo_b)
end

T["multi-project"]["q key closes correct window when multiple status buffers open"] = function()
  -- Create two test repos
  local repo_a = create_test_repo(child)
  local repo_b = create_test_repo(child)

  -- Create initial commits
  create_file(child, repo_a, "a.txt", "content a")
  git(child, repo_a, "add a.txt")
  git(child, repo_a, "commit -m 'Commit A'")

  create_file(child, repo_b, "b.txt", "content b")
  git(child, repo_b, "add b.txt")
  git(child, repo_b, "commit -m 'Commit B'")

  -- Open status for repo A
  cd(child, repo_a)
  child.cmd("Gitlad")
  wait(child, 300)

  local win_a = child.lua_get("vim.api.nvim_get_current_win()")
  local buf_a = child.lua_get("vim.api.nvim_get_current_buf()")

  -- Create split and open status for repo B
  child.cmd("vsplit")
  cd(child, repo_b)
  child.cmd("Gitlad")
  wait(child, 300)

  local win_b = child.lua_get("vim.api.nvim_get_current_win()")
  local buf_b = child.lua_get("vim.api.nvim_get_current_buf()")

  -- Verify we have two different windows and buffers
  eq(win_a ~= win_b, true)
  eq(buf_a ~= buf_b, true)

  -- Go back to window A (repo A's status)
  child.lua(string.format("vim.api.nvim_set_current_win(%d)", win_a))
  wait(child, 100)

  -- Verify we're in window A with buffer A
  eq(child.lua_get("vim.api.nvim_get_current_win()"), win_a)
  eq(child.lua_get("vim.api.nvim_get_current_buf()"), buf_a)

  -- Press 'q' to close status in window A
  child.type_keys("q")
  wait(child, 100)

  -- Window A should now show a different buffer (not status A)
  local new_buf_in_win_a = child.lua_get(string.format("vim.api.nvim_win_get_buf(%d)", win_a))
  eq(new_buf_in_win_a ~= buf_a, true)

  -- Window B should still show status B (unchanged)
  local buf_in_win_b = child.lua_get(string.format("vim.api.nvim_win_get_buf(%d)", win_b))
  eq(buf_in_win_b, buf_b)

  -- Cleanup
  cleanup_test_repo(child, repo_a)
  cleanup_test_repo(child, repo_b)
end

return T
