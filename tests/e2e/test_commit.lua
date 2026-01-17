-- End-to-end tests for gitlad.nvim commit popup
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

-- Helper to create a test git repository
local function create_test_repo(child)
  local repo = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
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

-- Helper to create a file in the repo
local function create_file(child, repo, filename, content)
  child.lua(string.format(
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

-- Helper to run a git command
local function git(child, repo, args)
  -- Use %q to properly escape the entire command
  return child.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
end

-- Helper to cleanup repo
local function cleanup_repo(child, repo)
  child.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start fresh child process for each test
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
      _G.child = child
    end,
    post_case = function()
      if _G.child then
        _G.child.stop()
        _G.child = nil
      end
    end,
  },
})

-- Commit popup tests
T["commit popup"] = MiniTest.new_set()

T["commit popup"]["opens from status buffer with c key"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and stage a file
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press c to open commit popup
  child.type_keys("c")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains commit-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_commit = false
  local found_amend = false
  local found_extend = false
  for _, line in ipairs(lines) do
    if line:match("c%s+Commit") then
      found_commit = true
    end
    if line:match("a%s+Amend") then
      found_amend = true
    end
    if line:match("e%s+Extend") then
      found_extend = true
    end
  end

  eq(found_commit, true)
  eq(found_amend, true)
  eq(found_extend, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["commit popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("c")

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_all = false
  local found_allow_empty = false
  local found_verbose = false
  local found_no_verify = false

  for _, line in ipairs(lines) do
    if line:match("%-a.*all") then
      found_all = true
    end
    if line:match("%-e.*allow%-empty") then
      found_allow_empty = true
    end
    if line:match("%-v.*verbose") then
      found_verbose = true
    end
    if line:match("%-n.*no%-verify") then
      found_no_verify = true
    end
  end

  eq(found_all, true)
  eq(found_allow_empty, true)
  eq(found_verbose, true)
  eq(found_no_verify, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Commit editor tests
T["commit editor"] = MiniTest.new_set()

T["commit editor"]["opens when pressing c in commit popup"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and stage a file
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup
  child.type_keys("c")
  -- Press c again to open commit editor
  child.type_keys("c")

  child.lua([[vim.wait(200, function() return false end)]])

  -- Verify we're in a commit editor buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("COMMIT_EDITMSG") ~= nil, true)

  -- Verify filetype is gitcommit
  local filetype = child.lua_get([[vim.bo.filetype]])
  eq(filetype, "gitcommit")

  cleanup_repo(child, repo)
end

T["commit editor"]["has help comments"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("c")
  child.type_keys("c")

  child.lua([[vim.wait(200, function() return false end)]])

  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])

  local found_help = false
  for _, line in ipairs(lines) do
    if line:match("C%-c C%-c to commit") then
      found_help = true
    end
  end

  eq(found_help, true)

  cleanup_repo(child, repo)
end

T["commit editor"]["aborts with C-c C-k"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("c")
  child.type_keys("c")

  child.lua([[vim.wait(200, function() return false end)]])

  -- Abort with C-c C-k
  child.type_keys("<C-c><C-k>")

  child.lua([[vim.wait(200, function() return false end)]])

  -- Verify we returned to status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  -- Verify no commit was made
  local log = git(child, repo, "log --oneline 2>&1")
  eq(log:match("does not have any commits") ~= nil, true)

  cleanup_repo(child, repo)
end

T["commit editor"]["can close status with q after abort"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup and editor
  child.type_keys("c")
  child.type_keys("c")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Abort
  child.type_keys("<C-c><C-k>")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Verify we're in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  -- Press q to close status - should not error
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify we're no longer in status buffer (switched to empty buffer since last window)
  bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") == nil, true)

  cleanup_repo(child, repo)
end

T["commit editor"]["creates commit with C-c C-c"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("c")
  child.type_keys("c")

  child.lua([[vim.wait(200, function() return false end)]])

  -- Type commit message
  child.type_keys("iTest commit message")
  child.type_keys("<Esc>")

  -- Commit with C-c C-c
  child.type_keys("<C-c><C-c>")

  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify we returned to status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  -- Verify commit was made
  local log = git(child, repo, "log --oneline")
  eq(log:match("Test commit message") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Extend action tests
T["extend action"] = MiniTest.new_set()

T["extend action"]["amends without opening editor"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Modify file and stage
  create_file(child, repo, "test.txt", "hello world")
  git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup and press e for extend
  child.type_keys("c")
  child.type_keys("e")

  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify only one commit exists (amend, not new commit)
  local log = git(child, repo, "log --oneline")
  local commit_count = 0
  for _ in log:gmatch("[^\n]+") do
    commit_count = commit_count + 1
  end
  eq(commit_count, 1)

  -- Verify the file change is in the commit
  local show = git(child, repo, "show --name-only")
  eq(show:match("test.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Amend action tests
T["amend action"] = MiniTest.new_set()

T["amend action"]["opens editor with previous commit message"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "My original message"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup and press a for amend
  child.type_keys("c")
  child.type_keys("a")

  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify editor contains previous message
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local found_message = false
  for _, line in ipairs(lines) do
    if line:match("My original message") then
      found_message = true
    end
  end
  eq(found_message, true)

  -- Clean up - abort the amend
  child.type_keys("<C-c><C-k>")
  cleanup_repo(child, repo)
end

return T
