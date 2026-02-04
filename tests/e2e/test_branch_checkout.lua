-- End-to-end tests for gitlad.nvim branch checkout functionality
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

-- Branch checkout tests
T["branch operations"] = MiniTest.new_set()

T["branch operations"]["checkout existing branch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a branch
  helpers.git(child, repo, "branch feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Checkout the branch using git module
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.checkout("feature-branch", {}, { cwd = %q }, function(success, err)
      _G.checkout_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.checkout_result ~= nil end)]])
  local result = child.lua_get([[_G.checkout_result]])

  eq(result.success, true)

  -- Verify we're now on the branch
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature-branch")

  helpers.cleanup_repo(child, repo)
end

-- Remote branch checkout tests (smart checkout behavior)
T["remote branch checkout"] = MiniTest.new_set()

T["remote branch checkout"]["creates local branch from remote when local doesn't exist"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Set up a fake remote with a branch
  helpers.git(child, repo, "remote add origin https://example.com/repo.git")
  -- Create a remote branch by creating a local branch and simulating remote ref
  helpers.git(child, repo, "checkout -b feature-branch")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Feature commit"')
  -- Create remote tracking ref
  helpers.git(child, repo, "update-ref refs/remotes/origin/feature-branch HEAD")
  -- Go back to main and delete local feature-branch
  helpers.git(child, repo, "checkout -")
  helpers.git(child, repo, "branch -D feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify local feature-branch doesn't exist
  local branches_before = helpers.git(child, repo, "branch")
  eq(branches_before:match("feature%-branch") == nil, true)

  -- Verify remote branch exists
  local remote_branches = helpers.git(child, repo, "branch -r")
  eq(remote_branches:match("origin/feature%-branch") ~= nil, true)

  -- Use _checkout_branch with remote ref type to simulate refs view behavior
  child.lua(string.format(
    [[
    local branch_popup = require("gitlad.popups.branch")
    local state = require("gitlad.state")

    -- Create a mock popup_data
    local mock_popup_data = {
      get_arguments = function() return {} end
    }

    -- Create repo_state
    local repo_state = state.get(%q)

    -- Call _checkout_branch with remote ref type
    branch_popup._checkout_branch(
      repo_state,
      mock_popup_data,
      "origin/feature-branch",
      "remote"
    )
  ]],
    repo
  ))

  -- Wait for async operation
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify we're now on the local feature-branch
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature-branch")

  -- Verify local branch now exists
  local branches_after = helpers.git(child, repo, "branch")
  eq(branches_after:match("feature%-branch") ~= nil, true)

  -- Verify upstream is set correctly
  local upstream = helpers.git(child, repo, "config branch.feature-branch.remote"):gsub("%s+", "")
  eq(upstream, "origin")

  helpers.cleanup_repo(child, repo)
end

T["remote branch checkout"]["checks out existing local branch when it exists"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a local branch
  helpers.git(child, repo, "branch feature-branch")

  -- Set up a fake remote with same-named branch
  helpers.git(child, repo, "remote add origin https://example.com/repo.git")
  helpers.git(child, repo, "update-ref refs/remotes/origin/feature-branch HEAD")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify we're on main
  local initial_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(initial_branch == "main" or initial_branch == "master", true)

  -- Use _checkout_branch with remote ref type
  child.lua(string.format(
    [[
    local branch_popup = require("gitlad.popups.branch")
    local state = require("gitlad.state")

    local mock_popup_data = {
      get_arguments = function() return {} end
    }

    local repo_state = state.get(%q)

    -- Call _checkout_branch with remote ref - should checkout existing local
    branch_popup._checkout_branch(
      repo_state,
      mock_popup_data,
      "origin/feature-branch",
      "remote"
    )
  ]],
    repo
  ))

  -- Wait for async operation
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify we're now on the local feature-branch
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature-branch")

  helpers.cleanup_repo(child, repo)
end

T["remote branch checkout"]["handles nested branch names correctly"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Set up a fake remote with a nested branch name
  helpers.git(child, repo, "remote add origin https://example.com/repo.git")
  helpers.git(child, repo, "checkout -b feature/add-login")
  helpers.create_file(child, repo, "login.txt", "login feature")
  helpers.git(child, repo, "add login.txt")
  helpers.git(child, repo, 'commit -m "Add login"')
  helpers.git(child, repo, "update-ref refs/remotes/origin/feature/add-login HEAD")
  helpers.git(child, repo, "checkout -")
  helpers.git(child, repo, "branch -D feature/add-login")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify local branch doesn't exist
  local branches_before = helpers.git(child, repo, "branch")
  eq(branches_before:match("feature/add%-login") == nil, true)

  -- Use _checkout_branch with remote ref type
  child.lua(string.format(
    [[
    local branch_popup = require("gitlad.popups.branch")
    local state = require("gitlad.state")

    local mock_popup_data = {
      get_arguments = function() return {} end
    }

    local repo_state = state.get(%q)

    branch_popup._checkout_branch(
      repo_state,
      mock_popup_data,
      "origin/feature/add-login",
      "remote"
    )
  ]],
    repo
  ))

  -- Wait for async operation
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify we're now on the local feature/add-login branch
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature/add-login")

  helpers.cleanup_repo(child, repo)
end

T["remote branch checkout"]["falls back to direct checkout for local refs"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a local branch
  helpers.git(child, repo, "branch other-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Use _checkout_branch with local ref type (should just checkout directly)
  child.lua(string.format(
    [[
    local branch_popup = require("gitlad.popups.branch")
    local state = require("gitlad.state")

    local mock_popup_data = {
      get_arguments = function() return {} end
    }

    local repo_state = state.get(%q)

    branch_popup._checkout_branch(
      repo_state,
      mock_popup_data,
      "other-branch",
      "local"
    )
  ]],
    repo
  ))

  -- Wait for async operation
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify we're now on other-branch
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "other-branch")

  helpers.cleanup_repo(child, repo)
end

return T
