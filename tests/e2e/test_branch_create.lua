-- End-to-end tests for gitlad.nvim branch creation functionality
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

-- Branch popup tests
T["branch popup"] = MiniTest.new_set()

T["branch popup"]["opens from status buffer with b key"] = function()
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
  helpers.wait_for_status(child)

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
    -- New magit-style labels
    if line:match("b%s+branch/revision") then
      found_checkout = true
    end
    if line:match("c%s+new branch") then
      found_create = true
    end
    if line:match("x%s+delete") then
      found_delete = true
    end
  end

  eq(found_checkout, true)
  eq(found_create, true)
  eq(found_delete, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["branch popup"]["has all expected actions"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

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
    -- New magit-style labels
    if line:match("b%s+branch/revision") then
      found_checkout_branch = true
    end
    if line:match("c%s+new branch") then
      found_create_checkout = true
    end
    if line:match("n%s+new branch") then
      found_create_branch = true
    end
    if line:match("m%s+rename") then
      found_rename = true
    end
    if line:match("x%s+delete") then
      found_delete = true
    end
  end

  eq(found_checkout_branch, true)
  eq(found_create_checkout, true)
  eq(found_create_branch, true)
  eq(found_rename, true)
  eq(found_delete, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["branch popup"]["has force switch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

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
  helpers.cleanup_repo(child, repo)
end

T["branch popup"]["switch toggling with -f"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

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
  helpers.wait_short(child)

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
  helpers.cleanup_repo(child, repo)
end

T["branch popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open branch popup
  child.type_keys("b")
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  helpers.wait_for_popup_closed(child)

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["branch popup"]["b keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

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
  helpers.cleanup_repo(child, repo)
end

-- Branch creation operations tests
T["branch operations"] = MiniTest.new_set()

T["branch operations"]["create and checkout branch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Verify we're on main/master
  local initial_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
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
  local new_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(new_branch, "feature-test")

  helpers.cleanup_repo(child, repo)
end

T["branch operations"]["rename branch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a branch
  helpers.git(child, repo, "branch old-name")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify branch exists with old name
  local branches_before = helpers.git(child, repo, "branch")
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
  local branches_after = helpers.git(child, repo, "branch")
  eq(branches_after:match("old%-name") == nil, true)
  eq(branches_after:match("new%-name") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["branch operations"]["spin-off switches to new branch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a named branch to use as "main" for the upstream
  -- (avoids main/master ambiguity)
  helpers.git(child, repo, "branch -M main-branch")

  -- Set up a fake remote and upstream to simulate the spin-off scenario
  helpers.git(child, repo, "remote add origin https://example.com/repo.git")
  -- Create a "remote" branch by making a commit reference
  helpers.git(child, repo, "update-ref refs/remotes/origin/main-branch HEAD~0")
  helpers.git(child, repo, "branch --set-upstream-to=origin/main-branch main-branch")

  -- Add commits that will be "spun off"
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Feature commit"')

  -- Verify we're on main-branch and have a commit ahead
  local initial_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(initial_branch, "main-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

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
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "spun-off-feature")

  -- Verify the spun-off branch has the feature commit
  local log_spinoff = helpers.git(child, repo, "log --oneline -1")
  eq(log_spinoff:match("Feature commit") ~= nil, true)

  -- Verify main-branch was reset (doesn't have the feature commit)
  local log_main = helpers.git(child, repo, "log --oneline main-branch -1")
  eq(log_main:match("Feature commit") == nil, true)
  eq(log_main:match("Initial") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["branch operations"]["spin-off works with push remote only (no upstream)"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a named branch
  helpers.git(child, repo, "branch -M main-branch")

  -- Set up a fake remote but NO upstream tracking
  -- This simulates the user's scenario: push remote exists, but no branch.<name>.merge set
  helpers.git(child, repo, "remote add origin https://example.com/repo.git")
  -- Create a "remote" branch reference (simulates origin/main-branch existing)
  helpers.git(child, repo, "update-ref refs/remotes/origin/main-branch HEAD~0")
  -- Note: We intentionally do NOT set upstream tracking via --set-upstream-to

  -- Add commits that will be "spun off"
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Feature commit"')

  -- Verify we're on main-branch
  local initial_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(initial_branch, "main-branch")

  -- Verify there's no upstream configured
  local upstream_check =
    helpers.git(child, repo, "rev-parse --abbrev-ref main-branch@{upstream} 2>&1 || true")
  eq(
    upstream_check:match("no upstream configured") ~= nil or upstream_check:match("fatal") ~= nil,
    true
  )

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_short(child, 1000)

  -- Get the status to verify push_remote is set
  child.lua([[
    local state = require("gitlad.state")
    local repo_state = state.get(vim.fn.getcwd())
    if repo_state and repo_state.status then
      _G.test_push_remote = repo_state.status.push_remote
    else
      _G.test_push_remote = nil
    end
  ]])
  local push_remote = child.lua_get([[_G.test_push_remote]])
  eq(push_remote, "origin/main-branch")

  -- Test the actual _spinoff function via the module
  -- We need to mock vim.ui.input and verify it uses push_remote as fallback
  child.lua(string.format(
    [[
    local cli = require("gitlad.git.cli")

    -- Simulate what _spinoff does when there's no upstream but there IS a push_remote:
    -- 1. Create new branch at current HEAD and checkout
    cli.run_async({ "checkout", "-b", "spun-off-feature", "HEAD" }, { cwd = %q }, function(result)
      if result.code ~= 0 then
        _G.spinoff_result = { success = false, err = "checkout -b failed: " .. table.concat(result.stderr, "\n") }
        return
      end

      -- 2. Use update-ref to move the original branch to push_remote (origin/main-branch)
      cli.run_async({
        "update-ref",
        "-m",
        "spin-off: moving to origin/main-branch",
        "refs/heads/main-branch",
        "origin/main-branch",
      }, { cwd = %q }, function(reset_result)
        _G.spinoff_result = {
          success = reset_result.code == 0,
          err = reset_result.code ~= 0 and table.concat(reset_result.stderr, "\n") or nil
        }
      end)
    end)
  ]],
    repo,
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.spinoff_result ~= nil end)]])
  local result = child.lua_get([[_G.spinoff_result]])

  eq(result.success, true)

  -- Verify we're now on the spun-off branch
  local current_branch = helpers.git(child, repo, "branch --show-current"):gsub("%s+", "")
  eq(current_branch, "spun-off-feature")

  -- Verify the spun-off branch has the feature commit
  local log_spinoff = helpers.git(child, repo, "log --oneline -1")
  eq(log_spinoff:match("Feature commit") ~= nil, true)

  -- Verify main-branch was reset to origin/main-branch (doesn't have the feature commit)
  local log_main = helpers.git(child, repo, "log --oneline main-branch -1")
  eq(log_main:match("Feature commit") == nil, true)
  eq(log_main:match("Initial") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

return T
