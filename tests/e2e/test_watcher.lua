-- E2E tests for file watcher and stale indicator
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to clean up test repo
local function cleanup_test_repo(child_nvim, repo)
  child_nvim.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

-- Helper to create a file in the test repo
local function create_file(child_nvim, repo, filename, content)
  child_nvim.lua(string.format(
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

-- Helper to run git command in repo
local function git(child_nvim, repo, args)
  return child_nvim.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
end

-- Helper to change directory
local function cd(child_nvim, dir)
  child_nvim.lua(string.format([[vim.cmd("cd %s")]], dir))
end

-- Helper to wait
local function wait(child_nvim, ms)
  child_nvim.lua(string.format("vim.wait(%d, function() end)", ms))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

-- =============================================================================
-- Watcher config tests
-- =============================================================================

T["watcher config"] = MiniTest.new_set()

T["watcher config"]["is enabled by default"] = function()
  child.lua([[require("gitlad").setup({})]])

  local enabled = child.lua_get([[require("gitlad.config").get().watcher.enabled]])
  eq(enabled, true)
end

T["watcher config"]["can be disabled via setup"] = function()
  child.lua([[require("gitlad").setup({ watcher = { enabled = false } })]])

  local enabled = child.lua_get([[require("gitlad.config").get().watcher.enabled]])
  eq(enabled, false)
end

T["watcher config"]["stale_indicator enabled by default"] = function()
  child.lua([[require("gitlad").setup({})]])

  local stale_indicator = child.lua_get([[require("gitlad.config").get().watcher.stale_indicator]])
  eq(stale_indicator, true)
end

T["watcher config"]["auto_refresh disabled by default"] = function()
  child.lua([[require("gitlad").setup({})]])

  local auto_refresh = child.lua_get([[require("gitlad.config").get().watcher.auto_refresh]])
  eq(auto_refresh, false)
end

T["watcher config"]["can enable auto_refresh"] = function()
  child.lua([[require("gitlad").setup({ watcher = { auto_refresh = true } })]])

  local auto_refresh = child.lua_get([[require("gitlad.config").get().watcher.auto_refresh]])
  eq(auto_refresh, true)
end

T["watcher config"]["can disable stale_indicator"] = function()
  child.lua([[require("gitlad").setup({ watcher = { stale_indicator = false } })]])

  local stale_indicator = child.lua_get([[require("gitlad.config").get().watcher.stale_indicator]])
  eq(stale_indicator, false)
end

T["watcher config"]["can enable both stale_indicator and auto_refresh"] = function()
  child.lua(
    [[require("gitlad").setup({ watcher = { stale_indicator = true, auto_refresh = true } })]]
  )

  local stale_indicator = child.lua_get([[require("gitlad.config").get().watcher.stale_indicator]])
  local auto_refresh = child.lua_get([[require("gitlad.config").get().watcher.auto_refresh]])
  eq(stale_indicator, true)
  eq(auto_refresh, true)
end

T["watcher config"]["has default auto_refresh_debounce_ms"] = function()
  child.lua([[require("gitlad").setup({})]])

  local debounce =
    child.lua_get([[require("gitlad.config").get().watcher.auto_refresh_debounce_ms]])
  eq(debounce, 500)
end

T["watcher config"]["can configure auto_refresh_debounce_ms"] = function()
  child.lua([[require("gitlad").setup({ watcher = { auto_refresh_debounce_ms = 1000 } })]])

  local debounce =
    child.lua_get([[require("gitlad.config").get().watcher.auto_refresh_debounce_ms]])
  eq(debounce, 1000)
end

-- =============================================================================
-- Spinner stale state tests (UI level)
-- =============================================================================

T["stale indicator"] = MiniTest.new_set()

T["stale indicator"]["spinner shows idle by default"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup without watcher
  child.lua([[require("gitlad").setup({})]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Get first line (status indicator)
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, 1, false)")
  local first_line = lines[1]

  -- Should show "Idle"
  eq(first_line:match("Idle") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["stale indicator"]["shows stale message when set_stale is called"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup without watcher (we'll manually trigger stale)
  child.lua([[require("gitlad").setup({})]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Manually trigger stale through the spinner
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    if buf then
      buf.spinner:set_stale()
      buf:_update_status_line()
    end
  ]])
  wait(child, 100)

  -- Get first line (status indicator)
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, 1, false)")
  local first_line = lines[1]

  -- Should show "Stale"
  eq(first_line:match("Stale") ~= nil, true)
  eq(first_line:match("gr to refresh") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["stale indicator"]["clears when spinner clear_stale is called"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup without watcher
  child.lua([[require("gitlad").setup({})]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Manually set stale
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    if buf then
      buf.spinner:set_stale()
      buf:_update_status_line()
    end
  ]])
  wait(child, 100)

  -- Verify stale is set
  local lines_before = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, 1, false)")
  eq(lines_before[1]:match("Stale") ~= nil, true)

  -- Clear stale manually (simulating what happens during refresh)
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    if buf then
      buf.spinner:clear_stale()
      buf:_update_status_line()
    end
  ]])
  wait(child, 100)

  -- Should show "Idle" again
  local lines_after = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, 1, false)")
  eq(lines_after[1]:match("Idle") ~= nil, true)
  eq(lines_after[1]:match("Stale") == nil, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- RepoState stale tracking tests
-- =============================================================================

T["repo state stale"] = MiniTest.new_set()

T["repo state stale"]["mark_stale sets stale flag"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.lua([[require("gitlad").setup({})]])

  -- Get repo state
  child.lua([[
    local state = require("gitlad.state")
    _G.test_repo_state = state.get()
  ]])

  -- Check initial state
  local initial_stale = child.lua_get([[_G.test_repo_state.stale]])
  eq(initial_stale, false)

  -- Mark stale
  child.lua([[_G.test_repo_state:mark_stale()]])

  local after_stale = child.lua_get([[_G.test_repo_state.stale]])
  eq(after_stale, true)

  cleanup_test_repo(child, repo)
end

T["repo state stale"]["clear_stale clears stale flag"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.lua([[require("gitlad").setup({})]])

  child.lua([[
    local state = require("gitlad.state")
    _G.test_repo_state = state.get()
    _G.test_repo_state:mark_stale()
  ]])

  local marked_stale = child.lua_get([[_G.test_repo_state.stale]])
  eq(marked_stale, true)

  child.lua([[_G.test_repo_state:clear_stale()]])

  local cleared_stale = child.lua_get([[_G.test_repo_state.stale]])
  eq(cleared_stale, false)

  cleanup_test_repo(child, repo)
end

T["repo state stale"]["emits stale event when marked stale"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.lua([[require("gitlad").setup({})]])

  -- Set up event listener
  child.lua([[
    local state = require("gitlad.state")
    _G.test_repo_state = state.get()
    _G.stale_event_count = 0
    _G.test_repo_state:on("stale", function()
      _G.stale_event_count = _G.stale_event_count + 1
    end)
  ]])

  -- Mark stale
  child.lua([[_G.test_repo_state:mark_stale()]])

  local event_count = child.lua_get([[_G.stale_event_count]])
  eq(event_count, 1)

  -- Mark stale again (should not emit again since already stale)
  child.lua([[_G.test_repo_state:mark_stale()]])

  local event_count_2 = child.lua_get([[_G.stale_event_count]])
  eq(event_count_2, 1) -- Still 1, not incremented

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Watcher integration tests
-- =============================================================================

T["watcher integration"] = MiniTest.new_set()

T["watcher integration"]["creates watcher when enabled"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with watcher enabled
  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check if watcher was created
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_has_watcher = buf and buf.watcher ~= nil
  ]])
  local has_watcher = child.lua_get("_G.test_has_watcher")
  eq(has_watcher, true)

  cleanup_test_repo(child, repo)
end

T["watcher integration"]["does not create watcher when disabled"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with watcher explicitly disabled
  child.lua([[require("gitlad").setup({ watcher = { enabled = false } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check if watcher was NOT created
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_has_watcher = buf and buf.watcher ~= nil
  ]])
  local has_watcher = child.lua_get("_G.test_has_watcher")
  eq(has_watcher, false)

  cleanup_test_repo(child, repo)
end

T["watcher integration"]["watcher is running after open"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with watcher enabled
  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check if watcher is running
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_is_running = buf and buf.watcher and buf.watcher:is_running()
  ]])
  local is_running = child.lua_get("_G.test_is_running")
  eq(is_running, true)

  cleanup_test_repo(child, repo)
end

T["watcher integration"]["creates watcher in indicator mode by default"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with watcher enabled (defaults to stale_indicator=true, auto_refresh=false)
  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check watcher settings
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_stale_indicator = buf and buf.watcher and buf.watcher._stale_indicator
    _G.test_auto_refresh = buf and buf.watcher and buf.watcher._auto_refresh
  ]])
  local stale_indicator = child.lua_get("_G.test_stale_indicator")
  local auto_refresh = child.lua_get("_G.test_auto_refresh")
  eq(stale_indicator, true)
  eq(auto_refresh, false)

  cleanup_test_repo(child, repo)
end

T["watcher integration"]["creates watcher with auto_refresh when configured"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with auto_refresh enabled
  child.lua([[require("gitlad").setup({ watcher = { enabled = true, auto_refresh = true } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check watcher settings and that auto_refresh debouncer was created
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_stale_indicator = buf and buf.watcher and buf.watcher._stale_indicator
    _G.test_auto_refresh = buf and buf.watcher and buf.watcher._auto_refresh
    _G.test_has_auto_refresh_debounced = buf and buf.watcher and buf.watcher._auto_refresh_debounced ~= nil
  ]])
  local stale_indicator = child.lua_get("_G.test_stale_indicator")
  local auto_refresh = child.lua_get("_G.test_auto_refresh")
  local has_auto_refresh_debounced = child.lua_get("_G.test_has_auto_refresh_debounced")
  eq(stale_indicator, true) -- still enabled by default
  eq(auto_refresh, true)
  eq(has_auto_refresh_debounced, true)

  cleanup_test_repo(child, repo)
end

T["watcher integration"]["creates watcher with both features enabled"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with both stale_indicator and auto_refresh enabled
  child.lua(
    [[require("gitlad").setup({ watcher = { enabled = true, stale_indicator = true, auto_refresh = true } })]]
  )

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check both debouncers were created
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_has_stale_debounced = buf and buf.watcher and buf.watcher._stale_indicator_debounced ~= nil
    _G.test_has_auto_refresh_debounced = buf and buf.watcher and buf.watcher._auto_refresh_debounced ~= nil
  ]])
  local has_stale_debounced = child.lua_get("_G.test_has_stale_debounced")
  local has_auto_refresh_debounced = child.lua_get("_G.test_has_auto_refresh_debounced")
  eq(has_stale_debounced, true)
  eq(has_auto_refresh_debounced, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Git command cooldown tests
-- =============================================================================

T["git command cooldown"] = MiniTest.new_set()

T["git command cooldown"]["git commands set last_operation_time"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer to initialize repo_state
  child.cmd("Gitlad")
  wait(child, 500)

  -- Record initial last_operation_time
  child.lua([[_G.test_initial_time = require("gitlad.state").get().last_operation_time]])
  local initial_time = child.lua_get("_G.test_initial_time")

  -- Wait a bit to ensure time difference
  wait(child, 100)

  -- Run a git command through gitlad's CLI module
  child.lua([[
    local cli = require("gitlad.git.cli")
    cli.run_async({ "status" }, { cwd = vim.fn.getcwd() }, function() end)
  ]])
  wait(child, 200)

  -- Check that last_operation_time was updated
  child.lua([[_G.test_new_time = require("gitlad.state").get().last_operation_time]])
  local new_time = child.lua_get("_G.test_new_time")

  -- The new time should be greater than the initial time
  eq(new_time > initial_time, true)

  cleanup_test_repo(child, repo)
end

T["git command cooldown"]["watcher is in cooldown after git command"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.lua([[require("gitlad").setup({ watcher = { enabled = true, cooldown_ms = 2000 } })]])

  -- Open status buffer to initialize repo_state and watcher
  child.cmd("Gitlad")
  wait(child, 500)

  -- Run a git command through gitlad's CLI module
  child.lua([[
    local cli = require("gitlad.git.cli")
    cli.run_async({ "status" }, { cwd = vim.fn.getcwd() }, function() end)
  ]])
  wait(child, 100)

  -- Check that watcher is in cooldown
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_in_cooldown = buf and buf.watcher and buf.watcher:is_in_cooldown()
  ]])
  local in_cooldown = child.lua_get("_G.test_in_cooldown")

  eq(in_cooldown, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Worktree watcher tests
-- =============================================================================

T["worktree watcher"] = MiniTest.new_set()

T["worktree watcher"]["uses correct git_dir for worktree"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit (required for worktrees)
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create a worktree
  local worktree_path = child.lua_get("vim.fn.tempname()")
  git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Change to worktree directory
  child.lua(string.format([[vim.cmd("cd %s")]], worktree_path))

  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer in the worktree
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check that the git_dir points to the main repo's .git/worktrees/<name>/ directory
  child.lua([[
    local state = require("gitlad.state")
    local repo_state = state.get()
    _G.test_git_dir = repo_state.git_dir
    _G.test_repo_root = repo_state.repo_root
  ]])

  local git_dir = child.lua_get("_G.test_git_dir")

  -- git_dir should contain "worktrees" for a worktree
  eq(git_dir:match("worktrees") ~= nil, true)

  -- Cleanup worktree
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  git(child, repo, string.format("worktree remove %s", worktree_path))
  cleanup_test_repo(child, repo)
end

T["worktree watcher"]["watcher watches correct directory for worktree"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit (required for worktrees)
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create a worktree
  local worktree_path = child.lua_get("vim.fn.tempname()")
  git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Change to worktree directory
  child.lua(string.format([[vim.cmd("cd %s")]], worktree_path))

  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer in the worktree
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check that the watcher is watching the correct git_dir
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_watcher_git_dir = buf and buf.watcher and buf.watcher.git_dir
    _G.test_watcher_running = buf and buf.watcher and buf.watcher:is_running()
  ]])

  local watcher_git_dir = child.lua_get("_G.test_watcher_git_dir")
  local watcher_running = child.lua_get("_G.test_watcher_running")

  -- Watcher should be running
  eq(watcher_running, true)

  -- Watcher git_dir should contain "worktrees"
  eq(watcher_git_dir:match("worktrees") ~= nil, true)

  -- Cleanup worktree
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  git(child, repo, string.format("worktree remove %s", worktree_path))
  cleanup_test_repo(child, repo)
end

return T
