-- E2E tests for log functionality
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local helpers = require("tests.helpers")

local child = MiniTest.new_child_neovim()

-- Helper to clean up test repo
local function cleanup_test_repo(child_nvim, repo)
  child_nvim.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

-- Helper to create a file in the test repo
-- Helper to run git command in repo
-- Helper to change directory
local function cd(child_nvim, dir)
  child_nvim.lua(string.format([[vim.cmd("cd %s")]], dir))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[require("gitlad").setup({})]])
    end,
    post_once = child.stop,
  },
})

-- =============================================================================
-- Log popup tests
-- =============================================================================

T["log popup"] = MiniTest.new_set()

T["log popup"]["opens from status buffer with l key"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create initial commit so status works
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Press l to open log popup
  child.type_keys("l")
  helpers.wait_for_popup(child)

  -- Should have a popup window
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count > 1, true)

  -- Buffer should contain "Log" (popup title)
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_log = false
  for _, line in ipairs(lines) do
    if line:match("Log") then
      found_log = true
      break
    end
  end
  eq(found_log, true)

  cleanup_test_repo(child, repo)
end

T["log popup"]["has switches and options"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  child.type_keys("l")
  helpers.wait_for_popup(child)

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have switches
  expect.equality(content:match("All branches") ~= nil, true)

  -- Should have options
  expect.equality(content:match("Limit") ~= nil, true)

  -- Should have actions
  expect.equality(content:match("Log current") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log popup"]["closes with q"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  child.type_keys("l")
  helpers.wait_for_popup(child)

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  child.type_keys("q")
  helpers.wait_for_popup_closed(child)

  local win_count_after = child.lua_get("vim.fn.winnr('$')")

  -- Window should have closed
  eq(win_count_after < win_count_before, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Log view tests
-- =============================================================================

T["log view"] = MiniTest.new_set()

T["log view"]["opens when action is triggered"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create some commits to show
  helpers.create_file(child, repo, "file1.txt", "content 1")
  helpers.git(child, repo, "add file1.txt")
  helpers.git(child, repo, "commit -m 'Add file1'")

  helpers.create_file(child, repo, "file2.txt", "content 2")
  helpers.git(child, repo, "add file2.txt")
  helpers.git(child, repo, "commit -m 'Add file2'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log popup
  child.type_keys("l")
  helpers.wait_for_popup(child)

  -- Trigger "log current branch" action
  child.type_keys("l")
  helpers.wait_for_buffer(child, "gitlad://log")

  -- Should now be in log buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name:match("gitlad://log") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["displays commits"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  helpers.create_file(child, repo, "file1.txt", "content")
  helpers.git(child, repo, "add file1.txt")
  helpers.git(child, repo, "commit -m 'First commit'")

  helpers.create_file(child, repo, "file2.txt", "content")
  helpers.git(child, repo, "add file2.txt")
  helpers.git(child, repo, "commit -m 'Second commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "First commit")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should show commit messages
  expect.equality(content:match("First commit") ~= nil, true)
  expect.equality(content:match("Second commit") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["winbar shows commit info"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  local winbar = child.lua_get("vim.wo.winbar")
  expect.equality(winbar:match("Commits in main") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["commits start at line 1"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  -- First line should be a commit (hash pattern)
  local first_line = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]")
  expect.equality(first_line:match("^%x%x%x%x%x%x%x ") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["commit lines have no leading indent"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create a commit
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Find the commit line (contains 7-char hash followed by subject)
  local commit_line_found = false
  for _, line in ipairs(lines) do
    if line:match("Test commit") then
      commit_line_found = true
      -- Line should start directly with hash (no leading spaces)
      expect.equality(line:match("^%x%x%x%x%x%x%x ") ~= nil, true)
      break
    end
  end
  expect.equality(commit_line_found, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["can yank commit hash with y"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create a commit
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  -- Yank the hash (cursor starts on first commit at line 1)
  child.type_keys("y")
  helpers.wait_short(child, 100)

  -- Check clipboard has a hash-like value
  local reg = child.lua_get("vim.fn.getreg('\"')")
  -- Should be a hex string (commit hash)
  expect.equality(reg:match("^%x+$") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["closes with q"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test")

  -- Verify in log buffer
  local buf_name_before = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name_before:match("gitlad://log") ~= nil, true)

  -- Close with q
  child.type_keys("q")
  helpers.wait_short(child, 100)

  -- Should be back in status or previous buffer
  local buf_name_after = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name_after:match("gitlad://log") == nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["gj/gk keymaps are set up"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  helpers.create_file(child, repo, "file1.txt", "content 1")
  helpers.git(child, repo, "add file1.txt")
  helpers.git(child, repo, "commit -m 'Commit 1'")

  helpers.create_file(child, repo, "file2.txt", "content 2")
  helpers.git(child, repo, "add file2.txt")
  helpers.git(child, repo, "commit -m 'Commit 2'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Commit")

  -- Verify we're in the log buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name:match("gitlad://log") ~= nil, true)

  -- Check that gj and gk keymaps exist by checking if they have mappings
  child.lua([[
    _G.has_gj = false
    _G.has_gk = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "gj" then _G.has_gj = true end
      if km.lhs == "gk" then _G.has_gk = true end
    end
  ]])
  local has_gj = child.lua_get("_G.has_gj")
  local has_gk = child.lua_get("_G.has_gk")
  eq(has_gj, true)
  eq(has_gk, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["buffer is not modifiable"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create a commit
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  -- Check that buffer is not modifiable
  local modifiable = child.lua_get("vim.bo.modifiable")
  eq(modifiable, false)

  cleanup_test_repo(child, repo)
end

T["log view"]["has sign column with expand indicators"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  helpers.create_file(child, repo, "file1.txt", "content 1")
  helpers.git(child, repo, "add file1.txt")
  helpers.git(child, repo, "commit -m 'First commit'")

  helpers.create_file(child, repo, "file2.txt", "content 2")
  helpers.git(child, repo, "add file2.txt")
  helpers.git(child, repo, "commit -m 'Second commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "First commit")

  -- Check sign column is enabled
  local signcolumn = child.lua_get("vim.wo.signcolumn")
  eq(signcolumn, "yes:1")

  -- Check that extmarks exist in the sign namespace
  child.lua([[
    _G.test_has_signs = false
    local log_view = require("gitlad.ui.views.log")
    local buf = log_view.get_buffer()
    if buf then
      local ns = vim.api.nvim_get_namespaces()["gitlad_log_signs"]
      if ns then
        local marks = vim.api.nvim_buf_get_extmarks(buf.bufnr, ns, 0, -1, {})
        _G.test_has_signs = #marks > 0
      end
    end
  ]])
  local has_signs = child.lua_get("_G.test_has_signs")
  eq(has_signs, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["sign indicator changes when commit is expanded"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create a commit with a body
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Test commit" -m "This is the body of the commit"')

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  -- Get sign text before expansion
  child.lua([[
    _G.test_sign_text = nil
    local log_view = require("gitlad.ui.views.log")
    local buf = log_view.get_buffer()
    if buf then
      local ns = vim.api.nvim_get_namespaces()["gitlad_log_signs"]
      if ns then
        local marks = vim.api.nvim_buf_get_extmarks(buf.bufnr, ns, 0, -1, { details = true })
        if #marks > 0 then
          _G.test_sign_text = marks[1][4].sign_text
        end
      end
    end
  ]])
  local sign_text_before = child.lua_get("_G.test_sign_text")
  -- Sign text may include trailing space for alignment
  expect.equality(sign_text_before:match("^>") ~= nil, true)

  -- Navigate to commit line and expand it
  child.type_keys("gj") -- Go to first commit
  child.type_keys("<Tab>")
  helpers.wait_short(child, 200)

  -- Get sign text after expansion
  child.lua([[
    _G.test_sign_text = nil
    local log_view = require("gitlad.ui.views.log")
    local buf = log_view.get_buffer()
    if buf then
      local ns = vim.api.nvim_get_namespaces()["gitlad_log_signs"]
      if ns then
        local marks = vim.api.nvim_buf_get_extmarks(buf.bufnr, ns, 0, -1, { details = true })
        if #marks > 0 then
          _G.test_sign_text = marks[1][4].sign_text
        end
      end
    end
  ]])
  local sign_text_after = child.lua_get("_G.test_sign_text")
  -- Sign text may include trailing space for alignment
  expect.equality(sign_text_after:match("^v") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["has popup keymaps (b, r, A, _, X)"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create a commit
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  -- Check that popup keymaps exist
  child.lua([[
    _G.popup_keymaps = {}
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "b" then _G.popup_keymaps.branch = true end
      if km.lhs == "r" then _G.popup_keymaps.rebase = true end
      if km.lhs == "A" then _G.popup_keymaps.cherrypick = true end
      if km.lhs == "_" then _G.popup_keymaps.revert = true end
      if km.lhs == "X" then _G.popup_keymaps.reset = true end
    end
  ]])

  local has_branch = child.lua_get("_G.popup_keymaps.branch")
  local has_rebase = child.lua_get("_G.popup_keymaps.rebase")
  local has_cherrypick = child.lua_get("_G.popup_keymaps.cherrypick")
  local has_revert = child.lua_get("_G.popup_keymaps.revert")
  local has_reset = child.lua_get("_G.popup_keymaps.reset")

  eq(has_branch, true)
  eq(has_rebase, true)
  eq(has_cherrypick, true)
  eq(has_revert, true)
  eq(has_reset, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["branch popup opens from log view"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create a commit
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'Test commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "Test commit")

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  -- Open branch popup
  child.type_keys("b")
  helpers.wait_for_popup(child)

  -- Should have opened a popup window
  local win_count_after = child.lua_get("vim.fn.winnr('$')")
  eq(win_count_after > win_count_before, true)

  cleanup_test_repo(child, repo)
end

T["log view"]["reset popup opens with commit context"] = function()
  local repo = helpers.create_test_repo(child)
  cd(child, repo)

  -- Create commits
  helpers.create_file(child, repo, "file1.txt", "content 1")
  helpers.git(child, repo, "add file1.txt")
  helpers.git(child, repo, "commit -m 'First commit'")

  helpers.create_file(child, repo, "file2.txt", "content 2")
  helpers.git(child, repo, "add file2.txt")
  helpers.git(child, repo, "commit -m 'Second commit'")

  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open log view
  child.type_keys("ll")
  helpers.wait_for_buffer(child, "gitlad://log")
  helpers.wait_for_buffer_content(child, "First commit")

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  -- Navigate to first commit and open reset popup
  child.type_keys("gj")
  helpers.wait_short(child)
  child.type_keys("X")
  helpers.wait_for_popup(child)

  -- Should have opened a popup window
  local win_count_after = child.lua_get("vim.fn.winnr('$')")
  eq(win_count_after > win_count_before, true)

  cleanup_test_repo(child, repo)
end

return T
