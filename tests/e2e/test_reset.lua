-- End-to-end tests for gitlad.nvim reset popup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to create a repo with multiple commits for reset testing
local function create_multi_commit_repo(child)
  local repo = helpers.create_test_repo(child)

  -- Commit 1
  helpers.create_file(child, repo, "file1.txt", "v1")
  helpers.git(child, repo, "add file1.txt")
  helpers.git(child, repo, 'commit -m "Commit 1"')

  -- Commit 2
  helpers.create_file(child, repo, "file2.txt", "v2")
  helpers.git(child, repo, "add file2.txt")
  helpers.git(child, repo, 'commit -m "Commit 2"')

  -- Commit 3
  helpers.create_file(child, repo, "file3.txt", "v3")
  helpers.git(child, repo, "add file3.txt")
  helpers.git(child, repo, 'commit -m "Commit 3"')

  return repo
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

-- Reset popup tests
T["reset popup"] = MiniTest.new_set()

T["reset popup"]["opens from status buffer with X key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press X to open reset popup
  child.type_keys("X")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains reset-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_mixed = false
  local found_soft = false
  local found_hard = false
  local found_keep = false
  local found_index = false
  local found_worktree = false
  for _, line in ipairs(lines) do
    if line:match("m%s+mixed") then
      found_mixed = true
    end
    if line:match("s%s+soft") then
      found_soft = true
    end
    if line:match("h%s+hard") then
      found_hard = true
    end
    if line:match("k%s+keep") then
      found_keep = true
    end
    if line:match("i%s+index") then
      found_index = true
    end
    if line:match("w%s+worktree") then
      found_worktree = true
    end
  end

  eq(found_mixed, true)
  eq(found_soft, true)
  eq(found_hard, true)
  eq(found_keep, true)
  eq(found_index, true)
  eq(found_worktree, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["reset popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open reset popup
  child.type_keys("X")
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["reset popup"]["X keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help with ?
  child.type_keys("?")

  -- Check for reset popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_reset = false
  for _, line in ipairs(lines) do
    if line:match("X%s+Reset") then
      found_reset = true
    end
  end

  eq(found_reset, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

-- Reset operations tests
T["reset operations"] = MiniTest.new_set()

T["reset operations"]["soft reset moves HEAD but preserves index"] = function()
  local child = _G.child
  local repo = create_multi_commit_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Stage some changes to verify they are preserved
  helpers.create_file(child, repo, "new.txt", "new content")
  helpers.git(child, repo, "add new.txt")

  -- Get current commit count
  local log_before = helpers.git(child, repo, "log --oneline")
  eq(log_before:match("Commit 3") ~= nil, true)

  -- Soft reset to HEAD~1
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.reset("HEAD~1", "soft", { cwd = %q }, function(success, err)
      _G.reset_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.reset_result ~= nil end)]])
  local result = child.lua_get([[_G.reset_result]])

  eq(result.success, true)

  -- Verify HEAD moved (Commit 3 is no longer latest)
  local log_after = helpers.git(child, repo, "log --oneline HEAD")
  eq(log_after:match("Commit 3") == nil, true)
  eq(log_after:match("Commit 2") ~= nil, true)

  -- Verify changes are staged (including the reset changes)
  local status = helpers.git(child, repo, "status --porcelain")
  -- file3.txt should now be staged (from the reset)
  eq(status:match("A%s+file3.txt") ~= nil or status:match("A  file3.txt") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["reset operations"]["mixed reset moves HEAD and unstages changes"] = function()
  local child = _G.child
  local repo = create_multi_commit_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Mixed reset to HEAD~1
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.reset("HEAD~1", "mixed", { cwd = %q }, function(success, err)
      _G.reset_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.reset_result ~= nil end)]])
  local result = child.lua_get([[_G.reset_result]])

  eq(result.success, true)

  -- Verify HEAD moved
  local log_after = helpers.git(child, repo, "log --oneline HEAD")
  eq(log_after:match("Commit 3") == nil, true)
  eq(log_after:match("Commit 2") ~= nil, true)

  -- Verify file3.txt is now untracked (unstaged from reset)
  local status = helpers.git(child, repo, "status --porcelain")
  eq(status:match("file3.txt") ~= nil, true)
  -- Should NOT be staged (mixed resets the index)
  eq(status:match("A%s+file3.txt") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["reset operations"]["hard reset moves HEAD and discards changes"] = function()
  local child = _G.child
  local repo = create_multi_commit_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Make uncommitted changes
  helpers.create_file(child, repo, "file3.txt", "modified content")

  -- Hard reset to HEAD~1
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.reset("HEAD~1", "hard", { cwd = %q }, function(success, err)
      _G.reset_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.reset_result ~= nil end)]])
  local result = child.lua_get([[_G.reset_result]])

  eq(result.success, true)

  -- Verify HEAD moved
  local log_after = helpers.git(child, repo, "log --oneline HEAD")
  eq(log_after:match("Commit 3") == nil, true)
  eq(log_after:match("Commit 2") ~= nil, true)

  -- Verify working directory is clean (all changes discarded)
  local status = helpers.git(child, repo, "status --porcelain")
  eq(status:gsub("%s+", ""), "")

  -- file3.txt should not exist anymore
  local file3_exists =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/file3.txt") == 1]], repo))
  eq(file3_exists, false)

  helpers.cleanup_repo(child, repo)
end

T["reset operations"]["keep reset preserves uncommitted changes"] = function()
  local child = _G.child
  local repo = create_multi_commit_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Make uncommitted changes to a file NOT affected by the reset
  helpers.create_file(child, repo, "file1.txt", "modified v1")

  -- Keep reset to HEAD~1
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.reset_keep("HEAD~1", { cwd = %q }, function(success, err)
      _G.reset_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.reset_result ~= nil end)]])
  local result = child.lua_get([[_G.reset_result]])

  eq(result.success, true)

  -- Verify HEAD moved
  local log_after = helpers.git(child, repo, "log --oneline HEAD")
  eq(log_after:match("Commit 3") == nil, true)
  eq(log_after:match("Commit 2") ~= nil, true)

  -- Verify uncommitted change to file1.txt is preserved
  local status = helpers.git(child, repo, "status --porcelain")
  eq(status:match("file1.txt") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["reset operations"]["index reset unstages all files"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Stage multiple files
  helpers.create_file(child, repo, "file1.txt", "content1")
  helpers.create_file(child, repo, "file2.txt", "content2")
  helpers.git(child, repo, "add file1.txt file2.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify files are staged
  local status_before = helpers.git(child, repo, "status --porcelain")
  eq(
    status_before:match("A%s+file1.txt") ~= nil or status_before:match("A  file1.txt") ~= nil,
    true
  )
  eq(
    status_before:match("A%s+file2.txt") ~= nil or status_before:match("A  file2.txt") ~= nil,
    true
  )

  -- Reset index
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.reset_index({ cwd = %q }, function(success, err)
      _G.reset_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.reset_result ~= nil end)]])
  local result = child.lua_get([[_G.reset_result]])

  eq(result.success, true)

  -- Verify files are now untracked (not staged)
  local status_after = helpers.git(child, repo, "status --porcelain")
  eq(status_after:match("??") ~= nil, true) -- Untracked files
  eq(status_after:match("A%s+file1.txt") == nil, true) -- Not staged
  eq(status_after:match("A%s+file2.txt") == nil, true) -- Not staged

  helpers.cleanup_repo(child, repo)
end

T["reset operations"]["worktree reset restores files without changing HEAD"] = function()
  local child = _G.child
  local repo = create_multi_commit_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Save current HEAD
  local head_before = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Modify a tracked file
  helpers.create_file(child, repo, "file1.txt", "modified content")

  -- Verify modification
  local status_before = helpers.git(child, repo, "status --porcelain")
  eq(
    status_before:match("M%s+file1.txt") ~= nil or status_before:match(" M file1.txt") ~= nil,
    true
  )

  -- Reset worktree to HEAD
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.reset_worktree("HEAD", { cwd = %q }, function(success, err)
      _G.reset_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.reset_result ~= nil end)]])
  local result = child.lua_get([[_G.reset_result]])

  eq(result.success, true)

  -- Verify HEAD unchanged
  local head_after = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")
  eq(head_before, head_after)

  -- Verify working directory is clean (modifications discarded)
  local status_after = helpers.git(child, repo, "status --porcelain")
  eq(status_after:gsub("%s+", ""), "")

  helpers.cleanup_repo(child, repo)
end

return T
