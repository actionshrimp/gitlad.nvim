-- End-to-end tests for gitlad.nvim commit amend/extend/reword functionality
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to run a git command
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
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Modify file and stage
  helpers.create_file(child, repo, "test.txt", "hello world")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup and press e for extend
  child.type_keys("c")
  child.type_keys("e")

  helpers.wait_for_status(child)

  -- Verify only one commit exists (amend, not new commit)
  local log = helpers.git(child, repo, "log --oneline")
  local commit_count = 0
  for _ in log:gmatch("[^\n]+") do
    commit_count = commit_count + 1
  end
  eq(commit_count, 1)

  -- Verify the file change is in the commit
  local show = helpers.git(child, repo, "show --name-only")
  eq(show:match("test.txt") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- Amend action tests
T["amend action"] = MiniTest.new_set()

T["amend action"]["opens editor with previous commit message"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "My original message"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup and press a for amend
  child.type_keys("c")
  child.type_keys("a")

  helpers.wait_for_status(child)

  -- Verify editor contains previous message
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local found_message = false
  for _, line in ipairs(lines) do
    if line:match("My original message") then
      found_message = true
    end
  end
  eq(found_message, true)

  -- Clean up - abort the amend (split keys with delay to avoid <C-c> interrupt race on slow CI)
  child.type_keys("Z", "Q")
  helpers.cleanup_repo(child, repo)
end

-- Reword action tests
T["reword action"] = MiniTest.new_set()

T["reword action"]["opens editor with previous commit message"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Original commit message"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup and press w for reword
  child.type_keys("c")
  child.type_keys("w")

  helpers.wait_for_status(child)

  -- Verify editor contains previous message
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local found_message = false
  for _, line in ipairs(lines) do
    if line:match("Original commit message") then
      found_message = true
    end
  end
  eq(found_message, true)

  -- Clean up - abort the reword (split keys with delay to avoid <C-c> interrupt race on slow CI)
  child.type_keys("Z", "Q")
  helpers.cleanup_repo(child, repo)
end

T["reword action"]["ignores staged changes"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Stage a new file that should NOT be included in the reword
  helpers.create_file(child, repo, "newfile.txt", "new content")
  helpers.git(child, repo, "add newfile.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup and press w for reword
  child.type_keys("c")
  child.type_keys("w")

  helpers.wait_for_status(child)

  -- Edit the commit message
  child.type_keys("ggdG") -- Delete all
  child.type_keys("iReworded message")
  child.type_keys("<Esc>")

  -- Confirm with ZZ (avoid <C-c><C-c> which is unreliable on nightly due to
  -- <C-c> interrupt semantics breaking the chord mapping)
  child.type_keys("Z", "Z")

  -- Wait for async commit operation to complete
  helpers.wait_for_buffer(child, "gitlad://status")

  -- Verify only one commit exists (reword, not new commit)
  local log = helpers.git(child, repo, "log --oneline")
  local commit_count = 0
  for _ in log:gmatch("[^\n]+") do
    commit_count = commit_count + 1
  end
  eq(commit_count, 1)

  -- Verify commit message was changed
  local message = helpers.git(child, repo, "log -1 --pretty=%B")
  eq(message:match("Reworded message") ~= nil, true)

  -- Verify newfile.txt is NOT in the commit (still staged, not committed)
  local show = helpers.git(child, repo, "show --name-only")
  eq(show:match("newfile.txt") == nil, true)

  -- Verify newfile.txt is still staged
  local status = helpers.git(child, repo, "status --porcelain")
  eq(status:match("A%s+newfile.txt") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

return T
