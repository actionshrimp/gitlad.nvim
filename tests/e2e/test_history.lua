-- E2E tests for git command history view
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
    vim.fn.system("git -C " .. repo .. " config commit.gpgsign false")
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
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit so status works
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Verify status buffer is open
  local ft = child.lua_get("vim.bo.filetype")
  eq(ft, "gitlad")

  -- Press $ to open history
  child.type_keys("$")
  wait(child, 200)

  -- Should have history window open
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count, 2)

  -- Buffer should be history buffer
  local history_ft = child.lua_get("vim.bo.filetype")
  eq(history_ft, "gitlad-history")

  cleanup_test_repo(child, repo)
end

T["history view"]["displays git command history entries"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer (this triggers git status command via plugin)
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history view
  child.type_keys("$")
  wait(child, 200)

  -- Get buffer content
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should have header
  local has_header = false
  for _, line in ipairs(lines) do
    if line:match("Git Command History") then
      has_header = true
      break
    end
  end
  eq(has_header, true)

  -- Should show git status command (from opening Gitlad)
  local has_status_cmd = false
  for _, line in ipairs(lines) do
    if line:match("git status") then
      has_status_cmd = true
      break
    end
  end
  eq(has_status_cmd, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["shows command count in header"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status (triggers at least one git command)
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

  -- Get lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should show count in format "(N commands)"
  local has_count = false
  for _, line in ipairs(lines) do
    if line:match("%(%d+ commands?%)") then
      has_count = true
      break
    end
  end
  eq(has_count, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["expands entry with <Tab>"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

  -- Get initial line count
  local initial_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Move to first entry (past header lines)
  child.type_keys("5j")
  wait(child, 100)

  -- Press Tab to expand
  child.type_keys("<Tab>")
  wait(child, 100)

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
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

  -- Move to first entry
  child.type_keys("5j")
  wait(child, 100)

  -- Expand
  child.type_keys("<Tab>")
  wait(child, 100)

  local expanded_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Collapse
  child.type_keys("<Tab>")
  wait(child, 100)

  local collapsed_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should be back to fewer lines
  expect.equality(collapsed_lines < expanded_lines, true)

  cleanup_test_repo(child, repo)
end

T["history view"]["expands entry with <CR>"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

  -- Get initial line count
  local initial_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Move to first entry
  child.type_keys("5j")
  wait(child, 100)

  -- Press Enter to expand
  child.type_keys("<CR>")
  wait(child, 100)

  -- Line count should increase
  local expanded_lines = child.lua_get("#vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  expect.no_equality(expanded_lines, initial_lines)

  cleanup_test_repo(child, repo)
end

T["history view"]["closes with q key"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

  -- Verify history is open
  local history_open = child.lua_get("vim.fn.winnr('$')")
  eq(history_open, 2)

  -- Press q to close
  child.type_keys("q")
  wait(child, 100)

  -- Should only have one window now
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count, 1)

  cleanup_test_repo(child, repo)
end

T["history view"]["closes with $ key (toggle behavior)"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

  eq(child.lua_get("vim.fn.winnr('$')"), 2)

  -- Press $ again to close
  child.type_keys("$")
  wait(child, 100)

  eq(child.lua_get("vim.fn.winnr('$')"), 1)

  cleanup_test_repo(child, repo)
end

T["history view"]["shows success indicator for successful commands"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit (successful commands)
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status (successful git status)
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

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
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status
  child.cmd("Gitlad")
  wait(child, 500)

  -- Open history
  child.type_keys("$")
  wait(child, 200)

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
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create commit manually without going through plugin
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Manually clear history to test empty state
  child.lua([[require("gitlad.git.history").clear()]])

  -- Open history view directly (not through status)
  child.lua([[require("gitlad.ui.views.history").open()]])
  wait(child, 200)

  -- Get lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Should show "No commands recorded" message
  local has_empty_msg = false
  for _, line in ipairs(lines) do
    if line:match("No commands recorded") then
      has_empty_msg = true
      break
    end
  end
  eq(has_empty_msg, true)

  cleanup_test_repo(child, repo)
end

return T
