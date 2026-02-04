-- End-to-end tests for gitlad.nvim commit amend/extend/reword functionality
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
    vim.fn.system("git -C " .. repo .. " config commit.gpgsign false")
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

-- Reword action tests
T["reword action"] = MiniTest.new_set()

T["reword action"]["opens editor with previous commit message"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Original commit message"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup and press w for reword
  child.type_keys("c")
  child.type_keys("w")

  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify editor contains previous message
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local found_message = false
  for _, line in ipairs(lines) do
    if line:match("Original commit message") then
      found_message = true
    end
  end
  eq(found_message, true)

  -- Clean up - abort the reword
  child.type_keys("<C-c><C-k>")
  cleanup_repo(child, repo)
end

T["reword action"]["ignores staged changes"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Stage a new file that should NOT be included in the reword
  create_file(child, repo, "newfile.txt", "new content")
  git(child, repo, "add newfile.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup and press w for reword
  child.type_keys("c")
  child.type_keys("w")

  child.lua([[vim.wait(500, function() return false end)]])

  -- Edit the commit message
  child.type_keys("ggdG") -- Delete all
  child.type_keys("iReworded message")
  child.type_keys("<Esc>")

  -- Confirm with C-c C-c
  child.type_keys("<C-c><C-c>")

  -- Wait for async commit operation to complete
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify only one commit exists (reword, not new commit)
  local log = git(child, repo, "log --oneline")
  local commit_count = 0
  for _ in log:gmatch("[^\n]+") do
    commit_count = commit_count + 1
  end
  eq(commit_count, 1)

  -- Verify commit message was changed
  local message = git(child, repo, "log -1 --pretty=%B")
  eq(message:match("Reworded message") ~= nil, true)

  -- Verify newfile.txt is NOT in the commit (still staged, not committed)
  local show = git(child, repo, "show --name-only")
  eq(show:match("newfile.txt") == nil, true)

  -- Verify newfile.txt is still staged
  local status = git(child, repo, "status --porcelain")
  eq(status:match("A%s+newfile.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

return T
