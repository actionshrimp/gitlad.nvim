-- E2E tests for git command history view
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to clean up test repo
local function cleanup_test_repo(child_nvim, repo)
  child_nvim.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[require("gitlad").setup({})]])
      -- Clear history before each test
      child.lua([[require("gitlad.git.history").clear()]])
    end,
    post_once = child.stop,
  },
})

-- =============================================================================
-- History view tests
-- =============================================================================

T["history view"] = MiniTest.new_set()

T["history view"]["opens from status buffer with $ key"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create initial commit so status works
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Verify status buffer is open
  local ft = child.lua_get("vim.bo.filetype")
  eq(ft, "gitlad")

  -- Press $ to open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")

  -- Should have history window open
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count, 2)

  -- Buffer should be history buffer
  local history_ft = child.lua_get("vim.bo.filetype")
  eq(history_ft, "gitlad-history")

  cleanup_test_repo(child, repo)
end

T["history view"]["displays git command history entries"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create initial commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Create an untracked file so we can stage it (user-facing operation)
  helpers.create_file(child, repo, "new.txt", "new content")

  -- Open status buffer
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Stage the file (creates a git add history entry)
  helpers.wait_for_buffer_content(child, "new.txt")
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("new.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.type_keys("s")
  helpers.wait_for_buffer_content(child, "Staged")

  -- Open history view
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")
  -- Wait for content to be rendered
  helpers.wait_for_buffer_content(child, "git add")

  -- Get buffer content
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- First line should be a command entry (no header)
  expect.equality(lines[1]:match("[✓✗]") ~= nil, true)

  -- Should show git add command (from staging)
  local has_add_cmd = false
  for _, line in ipairs(lines) do
    if line:match("git add") then
      has_add_cmd = true
      break
    end
  end
  eq(has_add_cmd, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["expands entry with <Tab>"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Create an untracked file so we can stage it
  helpers.create_file(child, repo, "new.txt", "new content")

  -- Open status
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Stage the file to create history entry
  helpers.wait_for_buffer_content(child, "new.txt")
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("new.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.type_keys("s")
  helpers.wait_for_buffer_content(child, "Staged")

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")
  helpers.wait_for_buffer_content(child, "git add")

  -- Get initial line count
  local initial_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Cursor is already on first entry (no header)
  -- Press Tab to expand
  child.type_keys("<Tab>")
  helpers.wait_for_buffer_content(child, "cwd:")

  -- Line count should increase (expanded entry has more lines)
  local expanded_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  expect.no_equality(expanded_lines, initial_lines)

  -- Should show "cwd:" in expanded details
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local has_cwd = false
  for _, line in ipairs(lines) do
    if line:match("cwd:") then
      has_cwd = true
      break
    end
  end
  eq(has_cwd, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["collapses entry with <Tab> again"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Create an untracked file so we can stage it
  helpers.create_file(child, repo, "new.txt", "new content")

  -- Open status
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Stage the file to create history entry
  helpers.wait_for_buffer_content(child, "new.txt")
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("new.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.type_keys("s")
  helpers.wait_for_buffer_content(child, "Staged")

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")
  helpers.wait_for_buffer_content(child, "git add")

  -- Cursor is already on first entry (no header)
  -- Expand
  child.type_keys("<Tab>")
  helpers.wait_for_buffer_content(child, "cwd:")

  local expanded_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Collapse
  child.type_keys("<Tab>")
  helpers.wait_short(child)

  local collapsed_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should be back to fewer lines
  expect.equality(collapsed_lines < expanded_lines, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["expands entry with <CR>"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Create an untracked file so we can stage it
  helpers.create_file(child, repo, "new.txt", "new content")

  -- Open status
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Stage the file to create history entry
  helpers.wait_for_buffer_content(child, "new.txt")
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("new.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.type_keys("s")
  helpers.wait_for_buffer_content(child, "Staged")

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")
  helpers.wait_for_buffer_content(child, "git add")

  -- Get initial line count
  local initial_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Cursor is already on first entry (no header)
  -- Press Enter to expand
  child.type_keys("<CR>")
  helpers.wait_for_buffer_content(child, "cwd:")

  -- Line count should increase
  local expanded_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  expect.no_equality(expanded_lines, initial_lines)

  cleanup_test_repo(child, repo)
end

T["history view"]["closes with q key"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")

  -- Verify history is open
  local history_open = child.lua_get("vim.fn.winnr('$')")
  eq(history_open, 2)

  -- Press q to close
  child.type_keys("q")
  helpers.wait_for_win_count(child, 1)

  -- Should only have one window now
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count, 1)

  cleanup_test_repo(child, repo)
end

T["history view"]["closes with $ key (toggle behavior)"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")

  eq(child.lua_get("vim.fn.winnr('$')"), 2)

  -- Press $ again to close
  child.type_keys("$")
  helpers.wait_for_win_count(child, 1)

  eq(child.lua_get("vim.fn.winnr('$')"), 1)

  cleanup_test_repo(child, repo)
end

T["history view"]["shows success indicator for successful commands"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit (successful commands)
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Create an untracked file so we can stage it
  helpers.create_file(child, repo, "new.txt", "new content")

  -- Open status (successful git status)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Stage the file to create history entry
  helpers.wait_for_buffer_content(child, "new.txt")
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("new.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.type_keys("s")
  helpers.wait_for_buffer_content(child, "Staged")

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")
  helpers.wait_for_buffer_content(child, "git add")

  -- Get lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should have checkmark for successful commands
  local has_success = false
  for _, line in ipairs(lines) do
    if line:match("✓") then
      has_success = true
      break
    end
  end
  eq(has_success, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["shows duration in milliseconds"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Create an untracked file so we can stage it
  helpers.create_file(child, repo, "new.txt", "new content")

  -- Open status
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Stage the file to create history entry
  helpers.wait_for_buffer_content(child, "new.txt")
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("new.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.type_keys("s")
  helpers.wait_for_buffer_content(child, "Staged")

  -- Open history
  child.type_keys("$")
  helpers.wait_for_filetype(child, "gitlad-history")
  helpers.wait_for_buffer_content(child, "git add")

  -- Get lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should have duration in format "123ms"
  local has_duration = false
  for _, line in ipairs(lines) do
    if line:match("%d+ms") then
      has_duration = true
      break
    end
  end
  eq(has_duration, true)

  cleanup_test_repo(child, repo)
end

-- Note: The `g` keymap for refresh in history view conflicts with vim's `g` operator
-- (waiting for `gg`, `gj`, etc.) which makes it hard to test in e2e.
-- The refresh functionality is tested implicitly through re-opening the view.

T["history view"]["empty history shows helpful message"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create commit manually without going through plugin
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Manually clear history to test empty state
  child.lua([[require("gitlad.git.history").clear()]])

  -- Open history view directly (not through status)
  child.lua([[require("gitlad.ui.views.history").open()]])
  helpers.wait_for_filetype(child, "gitlad-history")
  helpers.wait_for_buffer_content(child, "No commands recorded")

  -- Get lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should show "No commands recorded" message on first line
  eq(lines[1]:match("No commands recorded") ~= nil, true)

  cleanup_test_repo(child, repo)
end

return T
