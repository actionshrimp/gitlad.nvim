-- End-to-end tests for git config operations
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

-- Helper to read the .git/config file contents
local function read_git_config_file(child, repo)
  child.lua(string.format([[
    local path = %q .. "/.git/config"
    local f = io.open(path, "r")
    _G.config_file_content = f and f:read("*all") or ""
    if f then f:close() end
  ]], repo))
  return child.lua_get([[_G.config_file_content]])
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
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

-- Basic git config operations
T["git config"] = MiniTest.new_set()

T["git config"]["config_get returns value when set"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Set a config value using git command
  git(child, repo, "config test.mykey myvalue")

  -- Verify it was actually set using git command
  local git_value = git(child, repo, "config --get test.mykey"):gsub("%s+", "")
  eq(git_value, "myvalue")

  -- Now read it using our config_get
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[_G.config_value = require("gitlad.git").config_get("test.mykey")]])

  local value = child.lua_get([[_G.config_value]])
  eq(value, "myvalue")

  cleanup_repo(child, repo)
end

T["git config"]["config_get returns nil when not set"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  child.lua(string.format([[
    _G.config_value = require("gitlad.git").config_get("nonexistent.key", { cwd = %q })
  ]], repo))

  local value = child.lua_get([[_G.config_value]])
  eq(value, vim.NIL)

  cleanup_repo(child, repo)
end

T["git config"]["config_set writes value to git config"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Set using our config_set
  child.lua(string.format([[
    require("gitlad.git").config_set("test.newkey", "newvalue", { cwd = %q }, function(success, err)
      _G.config_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(1000, function() return _G.config_result ~= nil end)]])
  local result = child.lua_get([[_G.config_result]])
  eq(result.success, true)

  -- Verify using git command directly
  local value = git(child, repo, "config --get test.newkey"):gsub("%s+", "")
  eq(value, "newvalue")

  -- Verify the .git/config file contains the value
  local config_content = read_git_config_file(child, repo)
  eq(config_content:match("%[test%]") ~= nil, true)
  eq(config_content:match("newkey%s*=%s*newvalue") ~= nil, true)

  cleanup_repo(child, repo)
end

T["git config"]["config_unset removes value from git config"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- First set a value
  git(child, repo, "config test.toremove somevalue")

  -- Verify it exists in .git/config file
  local config_before = read_git_config_file(child, repo)
  eq(config_before:match("toremove%s*=%s*somevalue") ~= nil, true)

  -- Unset using our config_unset
  child.lua(string.format([[
    require("gitlad.git").config_unset("test.toremove", { cwd = %q }, function(success, err)
      _G.unset_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(1000, function() return _G.unset_result ~= nil end)]])
  local result = child.lua_get([[_G.unset_result]])
  eq(result.success, true)

  -- Verify it's gone from .git/config file
  local config_after = read_git_config_file(child, repo)
  eq(config_after:match("toremove%s*=%s*somevalue") == nil, true)

  cleanup_repo(child, repo)
end

T["git config"]["config_unset succeeds even if key doesn't exist"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Unset a key that doesn't exist
  child.lua(string.format([[
    require("gitlad.git").config_unset("nonexistent.key", { cwd = %q }, function(success, err)
      _G.unset_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(1000, function() return _G.unset_result ~= nil end)]])
  local result = child.lua_get([[_G.unset_result]])

  -- Should succeed (exit code 5 is acceptable for "key doesn't exist")
  eq(result.success, true)

  cleanup_repo(child, repo)
end

-- Boolean config operations
T["git config bool"] = MiniTest.new_set()

T["git config bool"]["config_get_bool returns true for 'true'"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  git(child, repo, "config test.mybool true")

  -- Verify it was set
  local git_value = git(child, repo, "config --get test.mybool"):gsub("%s+", "")
  eq(git_value, "true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[_G.bool_result = require("gitlad.git").config_get_bool("test.mybool")]])

  local value = child.lua_get([[_G.bool_result]])
  eq(value, true)

  cleanup_repo(child, repo)
end

T["git config bool"]["config_get_bool returns false for 'false'"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  git(child, repo, "config test.mybool false")

  child.lua(string.format([[
    _G.bool_result = require("gitlad.git").config_get_bool("test.mybool", { cwd = %q })
  ]], repo))

  local value = child.lua_get([[_G.bool_result]])
  eq(value, false)

  cleanup_repo(child, repo)
end

T["git config bool"]["config_get_bool returns false for unset"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  child.lua(string.format([[
    _G.bool_result = require("gitlad.git").config_get_bool("nonexistent.bool", { cwd = %q })
  ]], repo))

  local value = child.lua_get([[_G.bool_result]])
  eq(value, false)

  cleanup_repo(child, repo)
end

T["git config bool"]["config_toggle toggles false to true"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  git(child, repo, "config test.toggle false")

  child.lua(string.format([[
    require("gitlad.git").config_toggle("test.toggle", { cwd = %q }, function(new_value, err)
      _G.toggle_result = { new_value = new_value, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(1000, function() return _G.toggle_result ~= nil end)]])
  local result = child.lua_get([[_G.toggle_result]])

  eq(result.new_value, true)

  -- Verify in git config
  local value = git(child, repo, "config --get test.toggle"):gsub("%s+", "")
  eq(value, "true")

  cleanup_repo(child, repo)
end

T["git config bool"]["config_toggle toggles true to false"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  git(child, repo, "config test.toggle true")

  -- Verify it was set
  local git_value = git(child, repo, "config --get test.toggle"):gsub("%s+", "")
  eq(git_value, "true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[
    require("gitlad.git").config_toggle("test.toggle", nil, function(new_value, err)
      _G.toggle_result = { new_value = new_value, err = err }
    end)
  ]])

  child.lua([[vim.wait(1000, function() return _G.toggle_result ~= nil end)]])
  local result = child.lua_get([[_G.toggle_result]])

  eq(result.new_value, false)

  -- Verify in git config
  local value = git(child, repo, "config --get test.toggle"):gsub("%s+", "")
  eq(value, "false")

  cleanup_repo(child, repo)
end

-- Branch-specific config (upstream/pushRemote)
T["branch config"] = MiniTest.new_set()

T["branch config"]["setting upstream sets both remote and merge"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and branch
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  git(child, repo, "checkout -b feature-branch")
  git(child, repo, "remote add origin https://example.com/repo.git")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Use the popup's set_multiple_config_vars to simulate setting upstream
  child.lua(string.format([[
    local popup = require("gitlad.ui.popup")
    local data = popup.builder():repo_root(%q):build()
    data:set_multiple_config_vars({
      ["branch.feature-branch.remote"] = "origin",
      ["branch.feature-branch.merge"] = "refs/heads/main",
    }, function(success, err)
      _G.set_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(2000, function() return _G.set_result ~= nil end)]])
  local result = child.lua_get([[_G.set_result]])
  eq(result.success, true)

  -- Verify both values are set correctly in git config
  local remote = git(child, repo, "config --get branch.feature-branch.remote"):gsub("%s+", "")
  local merge = git(child, repo, "config --get branch.feature-branch.merge"):gsub("%s+", "")

  eq(remote, "origin")
  eq(merge, "refs/heads/main")

  -- Verify the .git/config file contains the branch section
  local config_content = read_git_config_file(child, repo)
  eq(config_content:match('%[branch "feature%-branch"%]') ~= nil, true)
  eq(config_content:match("remote%s*=%s*origin") ~= nil, true)
  eq(config_content:match("merge%s*=%s*refs/heads/main") ~= nil, true)

  cleanup_repo(child, repo)
end

T["branch config"]["setting local upstream sets remote to dot"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and branches
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  git(child, repo, "checkout -b feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Set upstream to a local branch (should use "." as remote)
  child.lua(string.format([[
    local popup = require("gitlad.ui.popup")
    local data = popup.builder():repo_root(%q):build()
    data:set_multiple_config_vars({
      ["branch.feature-branch.remote"] = ".",
      ["branch.feature-branch.merge"] = "refs/heads/main",
    }, function(success, err)
      _G.set_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(2000, function() return _G.set_result ~= nil end)]])
  local result = child.lua_get([[_G.set_result]])
  eq(result.success, true)

  -- Verify remote is set to "." in git config
  local remote = git(child, repo, "config --get branch.feature-branch.remote"):gsub("%s+", "")
  eq(remote, ".")

  -- Verify the .git/config file contains the literal dot
  local config_content = read_git_config_file(child, repo)
  eq(config_content:match("remote%s*=%s*%.") ~= nil, true)

  cleanup_repo(child, repo)
end

T["branch config"]["unsetting upstream clears both remote and merge"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and branch with upstream configured
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  git(child, repo, "checkout -b feature-branch")
  git(child, repo, "remote add origin https://example.com/repo.git")
  git(child, repo, "config branch.feature-branch.remote origin")
  git(child, repo, "config branch.feature-branch.merge refs/heads/main")

  -- Verify they're set in .git/config file
  local config_before = read_git_config_file(child, repo)
  eq(config_before:match('%[branch "feature%-branch"%]') ~= nil, true)
  eq(config_before:match("remote%s*=%s*origin") ~= nil, true)
  eq(config_before:match("merge%s*=%s*refs/heads/main") ~= nil, true)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Unset both using empty strings (simulating on_unset callback)
  child.lua(string.format([[
    local popup = require("gitlad.ui.popup")
    local data = popup.builder():repo_root(%q):build()
    data:set_multiple_config_vars({
      ["branch.feature-branch.remote"] = "",
      ["branch.feature-branch.merge"] = "",
    }, function(success, err)
      _G.unset_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(2000, function() return _G.unset_result ~= nil end)]])
  local result = child.lua_get([[_G.unset_result]])
  eq(result.success, true)

  -- Verify both are removed from .git/config file
  local config_after = read_git_config_file(child, repo)
  eq(config_after:match("remote%s*=%s*origin") == nil, true)
  eq(config_after:match("merge%s*=%s*refs/heads/main") == nil, true)

  cleanup_repo(child, repo)
end

T["branch config"]["pushRemote is set correctly"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and branch
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  git(child, repo, "checkout -b feature-branch")
  git(child, repo, "remote add origin https://example.com/repo.git")
  git(child, repo, "remote add fork https://example.com/fork.git")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Set pushRemote using config_set
  child.lua(string.format([[
    require("gitlad.git").config_set("branch.feature-branch.pushRemote", "fork", { cwd = %q }, function(success, err)
      _G.set_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(1000, function() return _G.set_result ~= nil end)]])
  local result = child.lua_get([[_G.set_result]])
  eq(result.success, true)

  -- Verify in git config
  local pushRemote = git(child, repo, "config --get branch.feature-branch.pushRemote"):gsub("%s+", "")
  eq(pushRemote, "fork")

  -- Verify in .git/config file
  local config_content = read_git_config_file(child, repo)
  eq(config_content:match("pushRemote%s*=%s*fork") ~= nil, true)

  cleanup_repo(child, repo)
end

T["branch config"]["remote.pushDefault is set correctly"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create repo with remotes
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  git(child, repo, "remote add origin https://example.com/repo.git")
  git(child, repo, "remote add upstream https://example.com/upstream.git")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Set remote.pushDefault
  child.lua(string.format([[
    require("gitlad.git").config_set("remote.pushDefault", "upstream", { cwd = %q }, function(success, err)
      _G.set_result = { success = success, err = err }
    end)
  ]], repo))

  child.lua([[vim.wait(1000, function() return _G.set_result ~= nil end)]])
  local result = child.lua_get([[_G.set_result]])
  eq(result.success, true)

  -- Verify in git config
  local pushDefault = git(child, repo, "config --get remote.pushDefault"):gsub("%s+", "")
  eq(pushDefault, "upstream")

  -- Verify in .git/config file
  local config_content = read_git_config_file(child, repo)
  eq(config_content:match("%[remote%]") ~= nil, true)
  eq(config_content:match("pushDefault%s*=%s*upstream") ~= nil, true)

  cleanup_repo(child, repo)
end

return T
