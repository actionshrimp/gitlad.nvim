-- End-to-end tests for gitlad.nvim branch popup
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

-- Branch popup tests
T["branch popup"] = MiniTest.new_set()

T["branch popup"]["opens from status buffer with b key"] = function()
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

  -- Press b to open branch popup
  child.type_keys("b")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains branch-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_checkout = false
  local found_create = false
  local found_delete = false
  for _, line in ipairs(lines) do
    if line:match("b%s+Checkout branch") then
      found_checkout = true
    end
    if line:match("c%s+Create and checkout") then
      found_create = true
    end
    if line:match("D%s+Delete") then
      found_delete = true
    end
  end

  eq(found_checkout, true)
  eq(found_create, true)
  eq(found_delete, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["branch popup"]["has all expected actions"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("b")

  -- Check for all actions in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_checkout_branch = false
  local found_create_checkout = false
  local found_create_branch = false
  local found_rename = false
  local found_delete = false

  for _, line in ipairs(lines) do
    if line:match("b%s+Checkout branch") then
      found_checkout_branch = true
    end
    if line:match("c%s+Create and checkout") then
      found_create_checkout = true
    end
    if line:match("n%s+Create branch") then
      found_create_branch = true
    end
    if line:match("m%s+Rename") then
      found_rename = true
    end
    if line:match("D%s+Delete") then
      found_delete = true
    end
  end

  eq(found_checkout_branch, true)
  eq(found_create_checkout, true)
  eq(found_create_branch, true)
  eq(found_rename, true)
  eq(found_delete, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["branch popup"]["has force switch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("b")

  -- Check for force switch in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_force = false
  for _, line in ipairs(lines) do
    if line:match("%-f.*force") then
      found_force = true
    end
  end

  eq(found_force, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["branch popup"]["switch toggling with -f"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("b")

  -- Check initial state - force should not be enabled
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_before = child.lua_get([[popup_lines]])

  local force_enabled_before = false
  for _, line in ipairs(lines_before) do
    if line:match("%*%-f.*force") then
      force_enabled_before = true
    end
  end
  eq(force_enabled_before, false)

  -- Toggle force switch
  child.type_keys("-f")
  child.lua([[vim.wait(50, function() return false end)]])

  -- Check that switch is now enabled (has * marker)
  child.lua([[
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_after = child.lua_get([[popup_lines]])

  local force_enabled_after = false
  for _, line in ipairs(lines_after) do
    if line:match("%*%-f.*force") then
      force_enabled_after = true
    end
  end
  eq(force_enabled_after, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["branch popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open branch popup
  child.type_keys("b")
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

T["branch popup"]["b keybinding appears in help"] = function()
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

  -- Check for branch popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_branch = false
  for _, line in ipairs(lines) do
    if line:match("b%s+Branch") then
      found_branch = true
    end
  end

  eq(found_branch, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Branch operations tests
T["branch operations"] = MiniTest.new_set()

T["branch operations"]["create and checkout branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify we're on main/master
  local initial_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(initial_branch == "main" or initial_branch == "master", true)

  -- Create new branch using git directly (to test the git module)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.checkout_new_branch("feature-test", nil, {}, { cwd = %q }, function(success, err)
      _G.create_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.create_result ~= nil end)]])
  local result = child.lua_get([[_G.create_result]])

  eq(result.success, true)

  -- Verify we're now on the new branch
  local new_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(new_branch, "feature-test")

  cleanup_repo(child, repo)
end

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

T["branch operations"]["rename branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a branch
  git(child, repo, "branch old-name")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify branch exists with old name
  local branches_before = git(child, repo, "branch")
  eq(branches_before:match("old%-name") ~= nil, true)

  -- Rename the branch using git module
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.rename_branch("old-name", "new-name", { cwd = %q }, function(success, err)
      _G.rename_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.rename_result ~= nil end)]])
  local result = child.lua_get([[_G.rename_result]])

  eq(result.success, true)

  -- Verify branch is renamed
  local branches_after = git(child, repo, "branch")
  eq(branches_after:match("old%-name") == nil, true)
  eq(branches_after:match("new%-name") ~= nil, true)

  cleanup_repo(child, repo)
end

T["branch operations"]["spin-off switches to new branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a named branch to use as "main" for the upstream
  -- (avoids main/master ambiguity)
  git(child, repo, "branch -M main-branch")

  -- Set up a fake remote and upstream to simulate the spin-off scenario
  git(child, repo, "remote add origin https://example.com/repo.git")
  -- Create a "remote" branch by making a commit reference
  git(child, repo, "update-ref refs/remotes/origin/main-branch HEAD~0")
  git(child, repo, "branch --set-upstream-to=origin/main-branch main-branch")

  -- Add commits that will be "spun off"
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature commit"')

  -- Verify we're on main-branch and have a commit ahead
  local initial_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(initial_branch, "main-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Create the spin-off using the git module directly
  -- (testing the popup interaction would require mocking vim.ui.input)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    local branch = require("gitlad.popups.branch")

    -- Simulate spin-off steps:
    -- 1. Create new branch at current HEAD
    git.create_branch("spun-off-feature", "HEAD", { cwd = %q }, function(create_success, create_err)
      if not create_success then
        _G.spinoff_result = { success = false, err = "create failed: " .. (create_err or "") }
        return
      end

      -- 2. Reset current branch to upstream
      git.reset("origin/main-branch", "hard", { cwd = %q }, function(reset_success, reset_err)
        if not reset_success then
          _G.spinoff_result = { success = false, err = "reset failed: " .. (reset_err or "") }
          return
        end

        -- 3. Switch to new branch (this is the fix being tested)
        git.checkout("spun-off-feature", {}, { cwd = %q }, function(checkout_success, checkout_err)
          _G.spinoff_result = { success = checkout_success, err = checkout_err }
        end)
      end)
    end)
  ]],
    repo,
    repo,
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.spinoff_result ~= nil end)]])
  local result = child.lua_get([[_G.spinoff_result]])

  eq(result.success, true)

  -- Verify we're now on the spun-off branch (the key fix)
  local current_branch = git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "spun-off-feature")

  -- Verify the spun-off branch has the feature commit
  local log_spinoff = git(child, repo, "log --oneline -1")
  eq(log_spinoff:match("Feature commit") ~= nil, true)

  -- Verify main-branch was reset (doesn't have the feature commit)
  local log_main = git(child, repo, "log --oneline main-branch -1")
  eq(log_main:match("Feature commit") == nil, true)
  eq(log_main:match("Initial") ~= nil, true)

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
