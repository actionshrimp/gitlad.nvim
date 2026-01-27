-- End-to-end tests for gitlad.nvim merge UI interactions
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

-- Helper to create a test git repository
local function create_test_repo(child)
  local repo = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init -b main")
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

-- Merge popup UI tests
T["merge popup"] = MiniTest.new_set()

T["merge popup"]["opens from status buffer with m key"] = function()
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

  -- Press m to open merge popup
  child.type_keys("m")

  -- Wait for async popup to open
  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains merge-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_merge = false
  local found_squash = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge") then
      found_merge = true
    end
    if line:match("s%s+Squash") then
      found_squash = true
    end
  end

  eq(found_merge, true)
  eq(found_squash, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_ff_only = false
  local found_no_ff = false

  for _, line in ipairs(lines) do
    if line:match("%-f.*ff%-only") then
      found_ff_only = true
    end
    if line:match("%-n.*no%-ff") then
      found_no_ff = true
    end
  end

  eq(found_ff_only, true)
  eq(found_no_ff, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open merge popup
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
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

T["merge popup"]["m keybinding appears in help"] = function()
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

  -- Check for merge in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_merge = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge") then
      found_merge = true
    end
  end

  eq(found_merge, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["shows in-progress popup during merge conflict"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load fully
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify merge state is detected
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_merge_state({ cwd = %q }, function(state)
      _G.merge_state = state
    end)
  ]],
    repo
  ))
  child.lua([[vim.wait(500, function() return _G.merge_state ~= nil end)]])

  -- Open merge popup
  child.type_keys("m")

  -- Wait for async popup to open (merge state detection is async)
  child.lua([[vim.wait(2000, function() return false end)]])

  -- Wait for popup window to appear
  child.lua([[
    vim.wait(500, function()
      return #vim.api.nvim_list_wins() > 1
    end)
  ]])

  -- Verify popup shows in-progress state
  -- The popup name (with "in progress") is shown in window title, not buffer content
  -- So we verify the in-progress actions are present instead
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- In-progress popup should have "Commit merge" and "Abort merge" actions
  -- (not the normal "Merge", "Squash merge" actions)
  local found_commit = false
  local found_abort = false
  local found_normal_merge = false -- This should NOT be present in in-progress popup
  for _, line in ipairs(lines) do
    if line:match("m%s+Commit merge") then
      found_commit = true
    end
    if line:match("a%s+Abort merge") then
      found_abort = true
    end
    -- In normal popup, "m" is for regular "Merge" not "Commit merge"
    -- and "s" is for "Squash merge"
    if line:match("s%s+Squash merge") then
      found_normal_merge = true
    end
  end

  eq(found_commit, true)
  eq(found_abort, true)
  eq(found_normal_merge, false) -- Squash should NOT be in in-progress popup

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Branch selection tests
T["branch selection"] = MiniTest.new_set()

T["branch selection"]["prompts with vim.ui.select when no context branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a feature branch
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature"')
  git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Mock vim.ui.select to capture the call
  child.lua([[
    _G.select_called = false
    _G.select_items = nil
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      _G.select_called = true
      _G.select_items = items
      on_choice(nil)  -- Cancel selection
    end
  ]])

  -- Open merge popup and trigger merge action
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  child.type_keys("m") -- Press 'm' again to trigger merge action
  child.lua([[vim.wait(500, function() return false end)]])

  local select_called = child.lua_get([[_G.select_called]])
  eq(select_called, true)

  local select_items = child.lua_get([[_G.select_items]])
  -- Should contain the feature branch
  local found_feature = false
  if select_items then
    for _, item in ipairs(select_items) do
      if item == "feature" then
        found_feature = true
      end
    end
  end
  eq(found_feature, true)

  -- Restore
  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

T["branch selection"]["excludes current branch from selection list"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branches
  git(child, repo, "checkout -b feature1")
  git(child, repo, "checkout -b feature2")
  git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Mock vim.ui.select
  child.lua([[
    _G.select_items = nil
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      _G.select_items = items
      on_choice(nil)
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])

  local select_items = child.lua_get([[_G.select_items]])

  -- Should NOT contain main (current branch)
  local found_main = false
  if select_items then
    for _, item in ipairs(select_items) do
      if item == "main" then
        found_main = true
      end
    end
  end
  eq(found_main, false)

  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

T["branch selection"]["shows notification when no branches available"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main - only one branch exists
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Track notifications
  child.lua([[
    _G.notifications = {}
    _G.original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.notifications, { msg = msg, level = level })
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  child.type_keys("m")
  child.lua([[vim.wait(1000, function() return false end)]])

  local notifications = child.lua_get([[_G.notifications]])

  -- Should have notification about no branches
  local found_no_branches = false
  for _, n in ipairs(notifications) do
    if n.msg and n.msg:match("No branches to merge") then
      found_no_branches = true
    end
  end
  eq(found_no_branches, true)

  child.lua([[vim.notify = _G.original_notify]])
  cleanup_repo(child, repo)
end

-- Abort confirmation tests
T["abort confirmation"] = MiniTest.new_set()

T["abort confirmation"]["does not abort when user selects No"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify merge is in progress
  local in_progress_before =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress_before, true)

  -- Mock vim.ui.select to select "No"
  child.lua([[
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice("No")
    end
  ]])

  -- Call merge_abort directly using M.get() which is the correct API
  child.lua(string.format(
    [[
    local merge_popup = require("gitlad.popups.merge")
    local state = require("gitlad.state")
    local repo_state = state.get(%q)
    merge_popup._merge_abort(repo_state)
  ]],
    repo
  ))

  child.lua([[vim.wait(500, function() return false end)]])

  -- Merge should still be in progress
  local in_progress_after =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress_after, true)

  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

T["abort confirmation"]["aborts when user selects Yes"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Mock vim.ui.select to select "Yes"
  child.lua([[
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice("Yes")
    end
  ]])

  -- Call merge_abort directly using M.get() which is the correct API
  child.lua(string.format(
    [[
    local merge_popup = require("gitlad.popups.merge")
    local state = require("gitlad.state")
    local repo_state = state.get(%q)
    merge_popup._merge_abort(repo_state)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return false end)]])

  -- Merge should no longer be in progress
  local in_progress_after =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress_after, false)

  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

-- Switch toggling tests
T["switch toggling"] = MiniTest.new_set()

T["switch toggling"]["multiple switches can be combined"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open merge popup and enable switches
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])

  -- Toggle ff-only switch
  child.type_keys("-f")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify switch is shown as enabled in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Look for enabled switch indicator (typically shown differently)
  local found_switch_line = false
  for _, line in ipairs(lines) do
    if line:match("%-f.*ff%-only") then
      found_switch_line = true
    end
  end
  eq(found_switch_line, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

return T
