-- End-to-end tests for gitlad.nvim stash popup
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

-- Stash popup tests
T["stash popup"] = MiniTest.new_set()

T["stash popup"]["opens from status buffer with z key"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press z to open stash popup
  child.type_keys("z")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains stash-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_stash = false
  local found_pop = false
  local found_apply = false
  for _, line in ipairs(lines) do
    if line:match("z%s+Stash") then
      found_stash = true
    end
    if line:match("p%s+Pop") then
      found_pop = true
    end
    if line:match("a%s+Apply") then
      found_apply = true
    end
  end

  eq(found_stash, true)
  eq(found_pop, true)
  eq(found_apply, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["stash popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("z")

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_untracked = false
  local found_all = false
  local found_keep_index = false

  for _, line in ipairs(lines) do
    if line:match("%-u.*include%-untracked") then
      found_untracked = true
    end
    if line:match("%-a.*all") then
      found_all = true
    end
    if line:match("%-k.*keep%-index") then
      found_keep_index = true
    end
  end

  eq(found_untracked, true)
  eq(found_all, true)
  eq(found_keep_index, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["stash popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open stash popup
  child.type_keys("z")
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

  cleanup_repo(child, repo)
end

T["stash popup"]["z keybinding appears in help"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help with ?
  child.type_keys("?")

  -- Check for stash popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_stash = false
  for _, line in ipairs(lines) do
    if line:match("z%s+Stash") then
      found_stash = true
    end
  end

  eq(found_stash, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Stash operations tests
T["stash operations"] = MiniTest.new_set()

T["stash operations"]["stash push creates a stash"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes
  create_file(child, repo, "test.txt", "modified")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify no stashes initially
  local stashes_before = git(child, repo, "stash list")
  eq(stashes_before:match("stash@") == nil, true)

  -- Stash changes using git module
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_push("test stash", {}, { cwd = %q }, function(success, err)
      _G.stash_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.stash_result ~= nil end)]])
  local result = child.lua_get([[_G.stash_result]])

  eq(result.success, true)

  -- Verify stash was created
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") ~= nil, true)
  eq(stashes_after:match("test stash") ~= nil, true)

  -- Verify working directory is clean
  local status = git(child, repo, "status --porcelain")
  eq(status:gsub("%s+", ""), "")

  cleanup_repo(child, repo)
end

T["stash operations"]["stash pop applies and removes stash"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes and stash them
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify stash exists
  local stashes_before = git(child, repo, "stash list")
  eq(stashes_before:match("stash@{0}") ~= nil, true)

  -- Pop the stash
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_pop("stash@{0}", { cwd = %q }, function(success, err)
      _G.pop_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.pop_result ~= nil end)]])
  local result = child.lua_get([[_G.pop_result]])

  eq(result.success, true)

  -- Verify stash is gone
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") == nil, true)

  -- Verify changes are back
  local status = git(child, repo, "status --porcelain")
  eq(status:match("M test.txt") ~= nil or status:match("M%s+test.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

T["stash operations"]["stash apply keeps stash in list"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes and stash them
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Apply the stash (without removing)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_apply("stash@{0}", { cwd = %q }, function(success, err)
      _G.apply_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.apply_result ~= nil end)]])
  local result = child.lua_get([[_G.apply_result]])

  eq(result.success, true)

  -- Verify stash still exists
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") ~= nil, true)

  -- Verify changes are applied
  local status = git(child, repo, "status --porcelain")
  eq(status:match("M test.txt") ~= nil or status:match("M%s+test.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

T["stash operations"]["stash drop removes stash without applying"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes and stash them
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify stash exists
  local stashes_before = git(child, repo, "stash list")
  eq(stashes_before:match("stash@{0}") ~= nil, true)

  -- Verify working directory is clean
  local status_before = git(child, repo, "status --porcelain")
  eq(status_before:gsub("%s+", ""), "")

  -- Drop the stash
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_drop("stash@{0}", { cwd = %q }, function(success, err)
      _G.drop_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.drop_result ~= nil end)]])
  local result = child.lua_get([[_G.drop_result]])

  eq(result.success, true)

  -- Verify stash is gone
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") == nil, true)

  -- Verify working directory is still clean (changes weren't applied)
  local status_after = git(child, repo, "status --porcelain")
  eq(status_after:gsub("%s+", ""), "")

  cleanup_repo(child, repo)
end

T["stash operations"]["stash list returns parsed entries"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create multiple stashes
  create_file(child, repo, "test.txt", "modified 1")
  git(child, repo, "stash push -m 'first stash'")

  create_file(child, repo, "test.txt", "modified 2")
  git(child, repo, "stash push -m 'second stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Get stash list
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_list({ cwd = %q }, function(stashes, err)
      _G.list_result = { stashes = stashes, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.list_result ~= nil end)]])
  local result = child.lua_get([[_G.list_result]])

  eq(result.err == nil, true)
  eq(#result.stashes, 2)

  -- Most recent stash is first (index 0)
  eq(result.stashes[1].index, 0)
  eq(result.stashes[1].ref, "stash@{0}")
  eq(result.stashes[1].message, "second stash")

  eq(result.stashes[2].index, 1)
  eq(result.stashes[2].ref, "stash@{1}")
  eq(result.stashes[2].message, "first stash")

  cleanup_repo(child, repo)
end

return T
