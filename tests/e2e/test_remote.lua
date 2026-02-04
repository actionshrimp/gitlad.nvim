-- End-to-end tests for gitlad.nvim remote popup and operations
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

-- Remote popup tests
T["remote popup"] = MiniTest.new_set()

T["remote popup"]["opens from status buffer with M key"] = function()
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

  -- Press M to open remote popup
  child.type_keys("M")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains remote-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_add = false
  local found_rename = false
  local found_remove = false
  local found_prune = false

  for _, line in ipairs(lines) do
    if line:match("a%s+Add") then
      found_add = true
    end
    if line:match("r%s+Rename") then
      found_rename = true
    end
    if line:match("x%s+Remove") then
      found_remove = true
    end
    if line:match("p%s+Prune stale branches") then
      found_prune = true
    end
  end

  eq(found_add, true)
  eq(found_rename, true)
  eq(found_remove, true)
  eq(found_prune, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["remote popup"]["has fetch after add switch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("M")

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_fetch = false
  for _, line in ipairs(lines) do
    if line:match("%-f.*[Ff]etch") then
      found_fetch = true
    end
  end

  eq(found_fetch, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["remote popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open remote popup
  child.type_keys("M")
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

T["remote popup"]["M keybinding appears in help"] = function()
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

  -- Check for remote popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_remote = false
  for _, line in ipairs(lines) do
    if line:match("M%s+Remotes") then
      found_remote = true
    end
  end

  eq(found_remote, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Git remote operations tests
T["git remote operations"] = MiniTest.new_set()

T["git remote operations"]["remote_add adds a new remote"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add a remote using gitlad
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.remote_add("origin", "https://github.com/test/repo.git", {}, { cwd = %q }, function(success, err)
      _G.add_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  -- Wait for operation to complete
  child.lua([[vim.wait(1000, function() return _G.add_result ~= nil end)]])

  local result = child.lua_get([[_G.add_result]])
  eq(result.success, true)

  -- Verify remote was added
  local remotes = git(child, repo, "remote -v")
  eq(remotes:match("origin") ~= nil, true)
  eq(remotes:match("https://github.com/test/repo.git") ~= nil, true)

  cleanup_repo(child, repo)
end

T["git remote operations"]["remote_rename renames a remote"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add a remote first
  git(child, repo, "remote add origin https://github.com/test/repo.git")

  -- Rename using gitlad
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.remote_rename("origin", "upstream", { cwd = %q }, function(success, err)
      _G.rename_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  -- Wait for operation to complete
  child.lua([[vim.wait(1000, function() return _G.rename_result ~= nil end)]])

  local result = child.lua_get([[_G.rename_result]])
  eq(result.success, true)

  -- Verify remote was renamed
  local remotes = git(child, repo, "remote -v")
  eq(remotes:match("origin") == nil, true)
  eq(remotes:match("upstream") ~= nil, true)

  cleanup_repo(child, repo)
end

T["git remote operations"]["remote_remove removes a remote"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add a remote first
  git(child, repo, "remote add origin https://github.com/test/repo.git")

  -- Remove using gitlad
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.remote_remove("origin", { cwd = %q }, function(success, err)
      _G.remove_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  -- Wait for operation to complete
  child.lua([[vim.wait(1000, function() return _G.remove_result ~= nil end)]])

  local result = child.lua_get([[_G.remove_result]])
  eq(result.success, true)

  -- Verify remote was removed
  local remotes = git(child, repo, "remote -v")
  eq(remotes:match("origin") == nil, true)

  cleanup_repo(child, repo)
end

T["git remote operations"]["remote_get_url returns the URL of a remote"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add a remote first
  git(child, repo, "remote add origin https://github.com/test/repo.git")

  -- Get URL using gitlad
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.remote_get_url("origin", { cwd = %q }, function(url, err)
      _G.url_result = { url = url, err = err }
    end)
  ]],
    repo
  ))

  -- Wait for operation to complete
  child.lua([[vim.wait(1000, function() return _G.url_result ~= nil end)]])

  local result = child.lua_get([[_G.url_result]])
  eq(result.url, "https://github.com/test/repo.git")
  eq(result.err, nil)

  cleanup_repo(child, repo)
end

T["git remote operations"]["remote_set_url changes the URL of a remote"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add a remote first
  git(child, repo, "remote add origin https://github.com/test/repo.git")

  -- Set URL using gitlad
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.remote_set_url("origin", "https://github.com/new/url.git", { cwd = %q }, function(success, err)
      _G.set_url_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  -- Wait for operation to complete
  child.lua([[vim.wait(1000, function() return _G.set_url_result ~= nil end)]])

  local result = child.lua_get([[_G.set_url_result]])
  eq(result.success, true)

  -- Verify URL was changed
  local remotes = git(child, repo, "remote -v")
  eq(remotes:match("https://github.com/new/url.git") ~= nil, true)

  cleanup_repo(child, repo)
end

return T
