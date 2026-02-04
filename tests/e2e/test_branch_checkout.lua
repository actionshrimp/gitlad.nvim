-- End-to-end tests for gitlad.nvim branch checkout functionality
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

-- Branch checkout tests
T["branch operations"] = MiniTest.new_set()

T["branch operations"]["checkout existing branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a branch
  git(child, repo, "branch feature-branch")

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
  local current_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature-branch")

  cleanup_repo(child, repo)
end

-- Remote branch checkout tests (smart checkout behavior)
T["remote branch checkout"] = MiniTest.new_set()

T["remote branch checkout"]["creates local branch from remote when local doesn't exist"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Set up a fake remote with a branch
  git(child, repo, "remote add origin https://example.com/repo.git")
  -- Create a remote branch by creating a local branch and simulating remote ref
  git(child, repo, "checkout -b feature-branch")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature commit"')
  -- Create remote tracking ref
  git(child, repo, "update-ref refs/remotes/origin/feature-branch HEAD")
  -- Go back to main and delete local feature-branch
  git(child, repo, "checkout -")
  git(child, repo, "branch -D feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify local feature-branch doesn't exist
  local branches_before = git(child, repo, "branch")
  eq(branches_before:match("feature%-branch") == nil, true)

  -- Verify remote branch exists
  local remote_branches = git(child, repo, "branch -r")
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
  local current_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature-branch")

  -- Verify local branch now exists
  local branches_after = git(child, repo, "branch")
  eq(branches_after:match("feature%-branch") ~= nil, true)

  -- Verify upstream is set correctly
  local upstream = git(child, repo, "config branch.feature-branch.remote"):gsub("%s+", "")
  eq(upstream, "origin")

  cleanup_repo(child, repo)
end

T["remote branch checkout"]["checks out existing local branch when it exists"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a local branch
  git(child, repo, "branch feature-branch")

  -- Set up a fake remote with same-named branch
  git(child, repo, "remote add origin https://example.com/repo.git")
  git(child, repo, "update-ref refs/remotes/origin/feature-branch HEAD")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify we're on main
  local initial_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
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
  local current_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature-branch")

  cleanup_repo(child, repo)
end

T["remote branch checkout"]["handles nested branch names correctly"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Set up a fake remote with a nested branch name
  git(child, repo, "remote add origin https://example.com/repo.git")
  git(child, repo, "checkout -b feature/add-login")
  create_file(child, repo, "login.txt", "login feature")
  git(child, repo, "add login.txt")
  git(child, repo, 'commit -m "Add login"')
  git(child, repo, "update-ref refs/remotes/origin/feature/add-login HEAD")
  git(child, repo, "checkout -")
  git(child, repo, "branch -D feature/add-login")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify local branch doesn't exist
  local branches_before = git(child, repo, "branch")
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
  local current_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "feature/add-login")

  cleanup_repo(child, repo)
end

T["remote branch checkout"]["falls back to direct checkout for local refs"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a local branch
  git(child, repo, "branch other-branch")

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
  local current_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "other-branch")

  cleanup_repo(child, repo)
end

return T
