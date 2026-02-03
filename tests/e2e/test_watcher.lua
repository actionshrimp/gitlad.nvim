-- E2E tests for file watcher and stale indicator
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to create a test git repository
local function create_test_repo(child_nvim)
  local repo = child_nvim.lua_get("vim.fn.tempname()")
  child_nvim.lua(string.format(
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

T["watcher config"]["defaults to indicator mode"] = function()
  child.lua([[require("gitlad").setup({})]])

  local mode = child.lua_get([[require("gitlad.config").get().watcher.mode]])
  eq(mode, "indicator")
end

T["watcher config"]["can be set to auto_refresh mode"] = function()
  child.lua([[require("gitlad").setup({ watcher = { mode = "auto_refresh" } })]])

  local mode = child.lua_get([[require("gitlad.config").get().watcher.mode]])
  eq(mode, "auto_refresh")
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
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
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with watcher enabled (defaults to indicator mode)
  child.lua([[require("gitlad").setup({ watcher = { enabled = true } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check watcher mode
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_watcher_mode = buf and buf.watcher and buf.watcher._mode
  ]])
  local mode = child.lua_get("_G.test_watcher_mode")
  eq(mode, "indicator")

  cleanup_test_repo(child, repo)
end

T["watcher integration"]["creates watcher in auto_refresh mode when configured"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Setup with auto_refresh mode
  child.lua([[require("gitlad").setup({ watcher = { enabled = true, mode = "auto_refresh" } })]])

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Check watcher mode and that auto_refresh debouncer was created
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local state = require("gitlad.state")
    local repo_state = state.get()
    local buf = status_view.get_buffer(repo_state)
    _G.test_watcher_mode = buf and buf.watcher and buf.watcher._mode
    _G.test_has_auto_refresh = buf and buf.watcher and buf.watcher._auto_refresh_debounced ~= nil
  ]])
  local mode = child.lua_get("_G.test_watcher_mode")
  local has_auto_refresh = child.lua_get("_G.test_has_auto_refresh")
  eq(mode, "auto_refresh")
  eq(has_auto_refresh, true)

  cleanup_test_repo(child, repo)
end

return T
