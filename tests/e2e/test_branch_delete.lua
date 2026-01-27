-- End-to-end tests for gitlad.nvim branch deletion functionality
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

-- Branch deletion tests
T["branch operations"] = MiniTest.new_set()

T["branch operations"]["delete branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a branch
  git(child, repo, "branch to-delete")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify branch exists
  local branches_before = git(child, repo, "branch")
  eq(branches_before:match("to%-delete") ~= nil, true)

  -- Delete the branch using git module
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.delete_branch("to-delete", false, { cwd = %q }, function(success, err)
      _G.delete_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.delete_result ~= nil end)]])
  local result = child.lua_get([[_G.delete_result]])

  eq(result.success, true)

  -- Verify branch is gone
  local branches_after = git(child, repo, "branch")
  eq(branches_after:match("to%-delete") == nil, true)

  cleanup_repo(child, repo)
end

T["branch operations"]["force delete unmerged branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a branch with a commit that's not merged
  git(child, repo, "checkout -b unmerged-feature")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature commit"')
  git(child, repo, "checkout -")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Try to delete without force (should fail)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.delete_branch("unmerged-feature", false, { cwd = %q }, function(success, err)
      _G.delete_no_force = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.delete_no_force ~= nil end)]])
  local result_no_force = child.lua_get([[_G.delete_no_force]])

  eq(result_no_force.success, false)

  -- Branch should still exist
  local branches_mid = git(child, repo, "branch")
  eq(branches_mid:match("unmerged%-feature") ~= nil, true)

  -- Force delete (should succeed)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.delete_branch("unmerged-feature", true, { cwd = %q }, function(success, err)
      _G.delete_force = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.delete_force ~= nil end)]])
  local result_force = child.lua_get([[_G.delete_force]])

  eq(result_force.success, true)

  -- Branch should be gone
  local branches_after = git(child, repo, "branch")
  eq(branches_after:match("unmerged%-feature") == nil, true)

  cleanup_repo(child, repo)
end

return T
