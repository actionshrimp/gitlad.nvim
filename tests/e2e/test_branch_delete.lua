-- End-to-end tests for gitlad.nvim branch deletion functionality
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

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
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a branch
  helpers.git(child, repo, "branch to-delete")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify branch exists
  local branches_before = helpers.git(child, repo, "branch")
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
  local branches_after = helpers.git(child, repo, "branch")
  eq(branches_after:match("to%-delete") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["branch operations"]["force delete unmerged branch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a branch with a commit that's not merged
  helpers.git(child, repo, "checkout -b unmerged-feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Feature commit"')
  helpers.git(child, repo, "checkout -")

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
  local branches_mid = helpers.git(child, repo, "branch")
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
  local branches_after = helpers.git(child, repo, "branch")
  eq(branches_after:match("unmerged%-feature") == nil, true)

  helpers.cleanup_repo(child, repo)
end

return T
