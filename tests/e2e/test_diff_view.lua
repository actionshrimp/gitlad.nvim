local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

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
-- Helpers
-- =============================================================================

--- Create a test repo with staged changes (one modified file)
---@return string repo_path
local function create_repo_with_staged_changes(child)
  local repo = helpers.create_test_repo(child)

  -- Create initial file and commit
  helpers.create_file(child, repo, "hello.lua", "local M = {}\nreturn M\n")
  helpers.git(child, repo, "add hello.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  -- Modify and stage
  helpers.create_file(
    child,
    repo,
    "hello.lua",
    "local M = {}\n\nfunction M.greet()\n  return 'hi'\nend\n\nreturn M\n"
  )
  helpers.git(child, repo, "add hello.lua")

  return repo
end

--- Create a test repo with staged changes across multiple files
---@return string repo_path
local function create_repo_with_multiple_staged(child)
  local repo = helpers.create_test_repo(child)

  -- Create initial files and commit
  helpers.create_file(child, repo, "alpha.lua", "-- alpha\nlocal M = {}\nreturn M\n")
  helpers.create_file(child, repo, "beta.lua", "-- beta\nlocal M = {}\nreturn M\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'initial'")

  -- Modify both files and stage
  helpers.create_file(
    child,
    repo,
    "alpha.lua",
    "-- alpha v2\nlocal M = {}\nM.version = 2\nreturn M\n"
  )
  helpers.create_file(
    child,
    repo,
    "beta.lua",
    "-- beta v2\nlocal M = {}\nM.version = 2\nreturn M\n"
  )
  helpers.git(child, repo, "add .")

  return repo
end

--- Wait for tab page count to reach a target value
---@param target number Expected tab count
---@param timeout? number Timeout in ms (default 3000)
local function wait_for_tab_count(target, timeout)
  timeout = timeout or 3000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      return vim.fn.tabpagenr('$') == %d
    end, 10)
  ]],
    timeout,
    target
  ))
end

--- Open the diff viewer with staged changes from a repo
---@param repo string repo path
local function open_staged_diff(repo)
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_staged(%q, function(spec, err)
      if spec then
        vim.schedule(function()
          local diff_view = require("gitlad.ui.views.diff")
          diff_view.open(spec)
        end)
      end
    end)
  ]],
    repo
  ))
  -- Wait for tab to open
  wait_for_tab_count(2)
end

--- Open a commit diff
---@param repo string repo path
---@param ref string commit ref (e.g. "HEAD")
local function open_commit_diff(repo, ref)
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_commit(%q, %q, function(spec, err)
      if spec then
        vim.schedule(function()
          require("gitlad.ui.views.diff").open(spec)
        end)
      end
    end)
  ]],
    repo,
    ref
  ))
  wait_for_tab_count(2)
end

--- Open a stash diff
---@param repo string repo path
---@param stash_ref string stash ref (e.g. "stash@{0}")
local function open_stash_diff(repo, stash_ref)
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_stash(%q, %q, function(spec, err)
      if spec then
        vim.schedule(function()
          require("gitlad.ui.views.diff").open(spec)
        end)
      end
    end)
  ]],
    repo,
    stash_ref
  ))
  wait_for_tab_count(2)
end

--- Create a test repo with two commits (for commit diff testing)
---@return string repo_path
local function create_repo_with_two_commits(child)
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "hello.lua", "local M = {}\nreturn M\n")
  helpers.git(child, repo, "add hello.lua")
  helpers.git(child, repo, "commit -m 'initial'")
  helpers.create_file(child, repo, "hello.lua", "local M = {}\nM.version = 2\nreturn M\n")
  helpers.git(child, repo, "add hello.lua")
  helpers.git(child, repo, "commit -m 'add version field'")
  return repo
end

--- Create a test repo with stashed changes
---@return string repo_path
local function create_repo_with_stash(child)
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "hello.lua", "local M = {}\nreturn M\n")
  helpers.git(child, repo, "add hello.lua")
  helpers.git(child, repo, "commit -m 'initial'")
  helpers.create_file(child, repo, "hello.lua", "local M = {}\nM.stashed = true\nreturn M\n")
  helpers.git(child, repo, "stash")
  return repo
end

--- Create a test repo with staged changes producing two separate hunks
---@return string repo_path
local function create_repo_with_multi_hunk(child)
  local repo = helpers.create_test_repo(child)
  -- Create a 20-line file
  local lines = {}
  for i = 1, 20 do
    lines[i] = "line" .. i
  end
  helpers.create_file(child, repo, "big.lua", table.concat(lines, "\n") .. "\n")
  helpers.git(child, repo, "add big.lua")
  helpers.git(child, repo, "commit -m 'initial'")
  -- Change line 3 and line 18 to get 2 separate hunks
  lines[3] = "CHANGED3"
  lines[18] = "CHANGED18"
  helpers.create_file(child, repo, "big.lua", table.concat(lines, "\n") .. "\n")
  helpers.git(child, repo, "add big.lua")
  return repo
end

--- Create a test repo with staged changes in a subdirectory
---@return string repo_path
local function create_repo_with_subdir_staged(child)
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "src/alpha.lua", "-- alpha\n")
  helpers.create_file(child, repo, "src/beta.lua", "-- beta\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'initial'")
  helpers.create_file(child, repo, "src/alpha.lua", "-- alpha v2\n")
  helpers.create_file(child, repo, "src/beta.lua", "-- beta v2\n")
  helpers.git(child, repo, "add .")
  return repo
end

--- Focus the left diff buffer window
local function focus_left_buffer()
  child.lua([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if view and view.buffer_pair and vim.api.nvim_win_is_valid(view.buffer_pair.left_winnr) then
      vim.api.nvim_set_current_win(view.buffer_pair.left_winnr)
    end
  end)()]])
  helpers.wait_short(child, 100)
end

--- Focus the panel window
local function focus_panel()
  child.lua([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if view and view.panel and vim.api.nvim_win_is_valid(view.panel.winnr) then
      vim.api.nvim_set_current_win(view.panel.winnr)
    end
  end)()]])
  helpers.wait_short(child, 100)
end

-- =============================================================================
-- Tests
-- =============================================================================

T["diff view"] = MiniTest.new_set()

T["diff view"]["opens in a new tab page"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  -- Should start with 1 tab
  local initial_tabs = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(initial_tabs, 1)

  open_staged_diff(repo)

  -- Should now have 2 tabs
  local tabs_after = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs_after, 2)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["creates 3 windows in the tab"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)

  -- The diff tab should have 3 windows: panel + left + right
  local win_count = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count, 3)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["shows file in panel buffer"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)

  -- Find the panel buffer and check it contains the filename
  local has_filename = child.lua_get([[(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "gitlad-diff-panel" then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:find("hello.lua", 1, true) then
            return true
          end
        end
      end
    end
    return false
  end)()]])
  eq(has_filename, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["shows diff content in side-by-side buffers"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Check that the diff buffers have content
  -- The left buffer should have the old content, right should have new content
  local left_has_content = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    local left_bufnr = view.buffer_pair.left_bufnr
    if not vim.api.nvim_buf_is_valid(left_bufnr) then return false end
    local lines = vim.api.nvim_buf_get_lines(left_bufnr, 0, -1, false)
    return #lines > 0
  end)()]])
  eq(left_has_content, true)

  local right_has_content = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    local right_bufnr = view.buffer_pair.right_bufnr
    if not vim.api.nvim_buf_is_valid(right_bufnr) then return false end
    local lines = vim.api.nvim_buf_get_lines(right_bufnr, 0, -1, false)
    return #lines > 0
  end)()]])
  eq(right_has_content, true)

  -- Right buffer should contain the new function
  local right_has_greet = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    local right_bufnr = view.buffer_pair.right_bufnr
    if not vim.api.nvim_buf_is_valid(right_bufnr) then return false end
    local lines = vim.api.nvim_buf_get_lines(right_bufnr, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("greet", 1, true) then
        return true
      end
    end
    return false
  end)()]])
  eq(right_has_greet, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["q closes the diff tab"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)

  -- Verify 2 tabs
  local tabs = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs, 2)

  -- Focus one of the diff buffers and press q
  child.lua([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view and view.buffer_pair and vim.api.nvim_win_is_valid(view.buffer_pair.left_winnr) then
      vim.api.nvim_set_current_win(view.buffer_pair.left_winnr)
    end
  end)()]])
  helpers.wait_short(child, 100)

  child.type_keys("q")
  helpers.wait_short(child, 500)

  -- Should be back to 1 tab
  local tabs_after = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs_after, 1)

  -- Active view should be nil
  local has_active = child.lua_get([[require("gitlad.ui.views.diff").get_active() ~= nil]])
  eq(has_active, false)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["gj/gk navigates between files"] = function()
  local repo = create_repo_with_multiple_staged(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Should start on file 1
  local initial_file = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view then return view.selected_file end
    return 0
  end)()]])
  eq(initial_file, 1)

  -- Focus a diff buffer and press gj to go to next file
  child.lua([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view and view.buffer_pair and vim.api.nvim_win_is_valid(view.buffer_pair.left_winnr) then
      vim.api.nvim_set_current_win(view.buffer_pair.left_winnr)
    end
  end)()]])
  helpers.wait_short(child, 100)

  child.type_keys("gj")
  helpers.wait_short(child, 200)

  -- Should be on file 2
  local after_gj = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view then return view.selected_file end
    return 0
  end)()]])
  eq(after_gj, 2)

  -- Press gk to go back to file 1
  child.type_keys("gk")
  helpers.wait_short(child, 200)

  local after_gk = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view then return view.selected_file end
    return 0
  end)()]])
  eq(after_gk, 1)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["gj wraps around at last file"] = function()
  local repo = create_repo_with_multiple_staged(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Navigate to last file, then press gj again
  child.lua([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view and view.buffer_pair and vim.api.nvim_win_is_valid(view.buffer_pair.left_winnr) then
      vim.api.nvim_set_current_win(view.buffer_pair.left_winnr)
    end
  end)()]])
  helpers.wait_short(child, 100)

  -- Go to file 2
  child.type_keys("gj")
  helpers.wait_short(child, 200)

  -- Go past last file - should wrap to file 1
  child.type_keys("gj")
  helpers.wait_short(child, 200)

  local wrapped = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view then return view.selected_file end
    return 0
  end)()]])
  eq(wrapped, 1)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["empty diff shows 'No changes' message"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.cd(child, repo)

  -- Create initial commit with no staged changes
  helpers.create_file(child, repo, "file.txt", "hello\n")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, "commit -m 'initial'")

  -- Open staged diff (no staged changes)
  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Check that a buffer contains "No changes"
  local has_message = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    local left_bufnr = view.buffer_pair.left_bufnr
    if not vim.api.nvim_buf_is_valid(left_bufnr) then return false end
    local lines = vim.api.nvim_buf_get_lines(left_bufnr, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("No changes", 1, true) then
        return true
      end
    end
    return false
  end)()]])
  eq(has_message, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["opening a new diff view closes the previous one"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  -- Open first diff view
  open_staged_diff(repo)

  -- Should have 2 tabs
  local tabs_first = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs_first, 2)

  -- Open another diff view (unstaged this time, but staged also works)
  -- We'll modify a file without staging to create an unstaged diff
  helpers.create_file(
    child,
    repo,
    "hello.lua",
    "local M = {}\n\nfunction M.greet()\n  return 'hello world'\nend\n\nreturn M\n"
  )

  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_unstaged(%q, function(spec, err)
      if spec then
        vim.schedule(function()
          local diff_view = require("gitlad.ui.views.diff")
          diff_view.open(spec)
        end)
      end
    end)
  ]],
    repo
  ))
  -- Wait for new tab to appear (old should be closed, new opens)
  helpers.wait_short(child, 1000)

  -- Should still have 2 tabs (old closed, new opened)
  local tabs_second = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs_second, 2)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["has line_map metadata in buffer pair"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Check that line_map has entries with proper metadata
  local line_map_size = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return 0 end
    return #view.buffer_pair.line_map
  end)()]])
  eq(line_map_size > 0, true)

  -- Check that at least one entry has hunk boundary
  local has_boundary = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    for _, info in ipairs(view.buffer_pair.line_map) do
      if info.is_hunk_boundary then return true end
    end
    return false
  end)()]])
  eq(has_boundary, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["panel q keymap closes the view"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)

  -- Focus the panel window and press q
  child.lua([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view and view.panel and vim.api.nvim_win_is_valid(view.panel.winnr) then
      vim.api.nvim_set_current_win(view.panel.winnr)
    end
  end)()]])
  helpers.wait_short(child, 100)

  child.type_keys("q")
  helpers.wait_short(child, 500)

  -- Should be back to 1 tab
  local tabs = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs, 1)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Tab label tests
-- =============================================================================

T["diff view"]["sets tab label to diff spec title"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Check that the tab page variable gitlad_label is set
  local label = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.tab_page then return "" end
    local ok, val = pcall(vim.api.nvim_tabpage_get_var, view.tab_page, "gitlad_label")
    if ok then return val end
    return ""
  end)()]])

  -- The label should start with "Diff staged"
  eq(label:find("Diff staged") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Auto-select file tests
-- =============================================================================

T["diff view"]["initial_file option selects matching file"] = function()
  local repo = create_repo_with_multiple_staged(child)
  helpers.cd(child, repo)

  -- Open with initial_file pointing to beta.lua (the second file)
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_staged(%q, function(spec, err)
      if spec then
        vim.schedule(function()
          local diff_view = require("gitlad.ui.views.diff")
          diff_view.open(spec, { initial_file = "beta.lua" })
        end)
      end
    end)
  ]],
    repo
  ))
  wait_for_tab_count(2)
  helpers.wait_short(child, 200)

  -- Should have selected file 2 (beta.lua)
  local selected = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view then return view.selected_file end
    return 0
  end)()]])
  eq(selected, 2)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["initial_file falls back to first file if not found"] = function()
  local repo = create_repo_with_multiple_staged(child)
  helpers.cd(child, repo)

  -- Open with initial_file pointing to a non-existent file
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_staged(%q, function(spec, err)
      if spec then
        vim.schedule(function()
          local diff_view = require("gitlad.ui.views.diff")
          diff_view.open(spec, { initial_file = "nonexistent.lua" })
        end)
      end
    end)
  ]],
    repo
  ))
  wait_for_tab_count(2)
  helpers.wait_short(child, 200)

  -- Should have fallen back to file 1
  local selected = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view then return view.selected_file end
    return 0
  end)()]])
  eq(selected, 1)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Hunk jumping tests
-- =============================================================================

T["diff view"]["]c moves cursor to next hunk boundary"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Focus the left diff buffer and place cursor at line 1
  child.lua([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if view and view.buffer_pair and vim.api.nvim_win_is_valid(view.buffer_pair.left_winnr) then
      vim.api.nvim_set_current_win(view.buffer_pair.left_winnr)
      vim.api.nvim_win_set_cursor(view.buffer_pair.left_winnr, {1, 0})
    end
  end)()]])
  helpers.wait_short(child, 100)

  -- Check there are hunk boundaries in the line_map
  local has_boundaries = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    local count = 0
    for _, info in ipairs(view.buffer_pair.line_map) do
      if info.is_hunk_boundary then count = count + 1 end
    end
    return count > 0
  end)()]])
  eq(has_boundaries, true)

  -- Get the first hunk boundary line (should be line 1 since it's always the first hunk start)
  local first_boundary = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return 0 end
    for i, info in ipairs(view.buffer_pair.line_map) do
      if info.is_hunk_boundary then return i end
    end
    return 0
  end)()]])
  eq(first_boundary > 0, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Filler line rendering tests
-- =============================================================================

T["diff view"]["filler lines render as tilde in buffers"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Check if any line in the left buffer has "~" (filler lines)
  -- The diff has additions, so left side should have filler lines
  local has_tilde = child.lua_get([[(function()
    local diff_view = require("gitlad.ui.views.diff")
    local view = diff_view.get_active()
    if not view or not view.buffer_pair then return false end
    local left_bufnr = view.buffer_pair.left_bufnr
    if not vim.api.nvim_buf_is_valid(left_bufnr) then return false end
    local lines = vim.api.nvim_buf_get_lines(left_bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      if line == "~" then
        -- Verify the corresponding line_map entry is a filler type
        local info = view.buffer_pair.line_map[i]
        if info and info.left_type == "filler" then
          return true
        end
      end
    end
    return false
  end)()]])
  eq(has_tilde, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Commit diff tests
-- =============================================================================

T["diff view"]["commit diff opens and shows content"] = function()
  local repo = create_repo_with_two_commits(child)
  helpers.cd(child, repo)

  open_commit_diff(repo, "HEAD")
  helpers.wait_short(child, 200)

  -- Should have 2 tabs
  local tabs = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs, 2)

  -- Right buffer should contain the new content from the commit
  local has_version = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.buffer_pair then return false end
    local right = view.buffer_pair.right_bufnr
    if not vim.api.nvim_buf_is_valid(right) then return false end
    local lines = vim.api.nvim_buf_get_lines(right, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("version", 1, true) then return true end
    end
    return false
  end)()]])
  eq(has_version, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["commit diff shows file in panel"] = function()
  local repo = create_repo_with_two_commits(child)
  helpers.cd(child, repo)

  open_commit_diff(repo, "HEAD")
  helpers.wait_short(child, 200)

  local has_filename = child.lua_get([[(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "gitlad-diff-panel" then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:find("hello.lua", 1, true) then return true end
        end
      end
    end
    return false
  end)()]])
  eq(has_filename, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Stash diff tests
-- =============================================================================

T["diff view"]["stash diff opens and shows stashed changes"] = function()
  local repo = create_repo_with_stash(child)
  helpers.cd(child, repo)

  open_stash_diff(repo, "stash@{0}")
  helpers.wait_short(child, 200)

  local tabs = child.lua_get([[vim.fn.tabpagenr('$')]])
  eq(tabs, 2)

  -- Right buffer should contain the stashed content
  local has_stashed = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.buffer_pair then return false end
    local right = view.buffer_pair.right_bufnr
    if not vim.api.nvim_buf_is_valid(right) then return false end
    local lines = vim.api.nvim_buf_get_lines(right, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("stashed", 1, true) then return true end
    end
    return false
  end)()]])
  eq(has_stashed, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Full file content tests (-U999999)
-- =============================================================================

T["diff view"]["commit diff shows full file content not just hunk context"] = function()
  -- Regression: without -U999999, only 3 lines of context were shown per hunk,
  -- so changes far apart in a long file would only show fragments.
  local repo = helpers.create_test_repo(child)
  -- Create a 20-line file
  local lines = {}
  for i = 1, 20 do
    lines[i] = "line" .. i
  end
  helpers.create_file(child, repo, "big.lua", table.concat(lines, "\n") .. "\n")
  helpers.git(child, repo, "add big.lua")
  helpers.git(child, repo, "commit -m 'initial'")
  -- Change line 2 and line 19 (far apart, would be separate hunks with default context)
  lines[2] = "CHANGED2"
  lines[19] = "CHANGED19"
  helpers.create_file(child, repo, "big.lua", table.concat(lines, "\n") .. "\n")
  helpers.git(child, repo, "add big.lua")
  helpers.git(child, repo, "commit -m 'change lines 2 and 19'")

  helpers.cd(child, repo)
  open_commit_diff(repo, "HEAD")
  helpers.wait_short(child, 200)

  -- Both buffers should contain the full file (all 20 lines, not just context around hunks)
  local result = child.lua_get([=[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.buffer_pair then return { left = 0, right = 0, has_line10 = false } end
    local left = view.buffer_pair.left_bufnr
    local right = view.buffer_pair.right_bufnr
    if not vim.api.nvim_buf_is_valid(left) or not vim.api.nvim_buf_is_valid(right) then
      return { left = 0, right = 0, has_line10 = false }
    end
    local left_lines = vim.api.nvim_buf_get_lines(left, 0, -1, false)
    local right_lines = vim.api.nvim_buf_get_lines(right, 0, -1, false)
    -- Check that a middle line (line10) exists — it would be missing without -U999999
    local has_line10 = false
    for _, line in ipairs(right_lines) do
      if line:find("line10", 1, true) then has_line10 = true; break end
    end
    return { left = #left_lines, right = #right_lines, has_line10 = has_line10 }
  end)()]=])
  -- Should have all 20 lines (same count since only modifications, no adds/deletes)
  eq(result.left >= 20, true)
  eq(result.right >= 20, true)
  eq(result.has_line10, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Deleted comment line tests (--- prefix parsing)
-- =============================================================================

T["diff view"]["deleted Lua comment lines appear in commit diff"] = function()
  -- Regression: deleted lines starting with "-- " (Lua comments) produced diff lines
  -- like "--- comment" that matched the file header pattern and got silently dropped.
  local repo = helpers.create_test_repo(child)
  local content = table.concat({
    "local M = {}",
    "-- This is a comment",
    "-- Another comment",
    "function M.hello() end",
    "return M",
  }, "\n") .. "\n"
  helpers.create_file(child, repo, "init.lua", content)
  helpers.git(child, repo, "add init.lua")
  helpers.git(child, repo, "commit -m 'initial with comments'")
  -- Remove the comment lines
  local new_content = table.concat({
    "local M = {}",
    "function M.hello() end",
    "return M",
  }, "\n") .. "\n"
  helpers.create_file(child, repo, "init.lua", new_content)
  helpers.git(child, repo, "add init.lua")
  helpers.git(child, repo, "commit -m 'remove comments'")

  helpers.cd(child, repo)
  open_commit_diff(repo, "HEAD")
  helpers.wait_short(child, 200)

  -- Left buffer (old) should contain the deleted comment lines
  local result = child.lua_get([=[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.buffer_pair then return { has_comment1 = false, has_comment2 = false } end
    local left = view.buffer_pair.left_bufnr
    if not vim.api.nvim_buf_is_valid(left) then return { has_comment1 = false, has_comment2 = false } end
    local lines = vim.api.nvim_buf_get_lines(left, 0, -1, false)
    local has_comment1 = false
    local has_comment2 = false
    for _, line in ipairs(lines) do
      if line:find("This is a comment", 1, true) then has_comment1 = true end
      if line:find("Another comment", 1, true) then has_comment2 = true end
    end
    return { has_comment1 = has_comment1, has_comment2 = has_comment2 }
  end)()]=])
  eq(result.has_comment1, true)
  eq(result.has_comment2, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["deleted Lua comment lines appear in staged diff"] = function()
  -- Same regression but for staged diffs
  local repo = helpers.create_test_repo(child)
  local content = table.concat({
    "local M = {}",
    "-- Helper function",
    "-- Does something useful",
    "function M.run() end",
    "return M",
  }, "\n") .. "\n"
  helpers.create_file(child, repo, "mod.lua", content)
  helpers.git(child, repo, "add mod.lua")
  helpers.git(child, repo, "commit -m 'initial'")
  -- Remove the comment lines and stage
  local new_content = table.concat({
    "local M = {}",
    "function M.run() end",
    "return M",
  }, "\n") .. "\n"
  helpers.create_file(child, repo, "mod.lua", new_content)
  helpers.git(child, repo, "add mod.lua")

  helpers.cd(child, repo)
  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Left buffer (old/index before staging) should contain the deleted comment lines
  local result = child.lua_get([=[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.buffer_pair then return { has_helper = false, has_useful = false } end
    local left = view.buffer_pair.left_bufnr
    if not vim.api.nvim_buf_is_valid(left) then return { has_helper = false, has_useful = false } end
    local lines = vim.api.nvim_buf_get_lines(left, 0, -1, false)
    local has_helper = false
    local has_useful = false
    for _, line in ipairs(lines) do
      if line:find("Helper function", 1, true) then has_helper = true end
      if line:find("something useful", 1, true) then has_useful = true end
    end
    return { has_helper = has_helper, has_useful = has_useful }
  end)()]=])
  eq(result.has_helper, true)
  eq(result.has_useful, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Hunk navigation tests (cursor movement)
-- =============================================================================

T["diff view"]["]c moves cursor forward from line 1"] = function()
  local repo = create_repo_with_multi_hunk(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Focus left buffer and place cursor at line 1
  focus_left_buffer()
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])
  helpers.wait_short(child, 50)

  local before = child.lua_get([==[vim.api.nvim_win_get_cursor(0)[1]]==])
  eq(before, 1)

  child.type_keys("]c")
  helpers.wait_short(child, 100)

  local after = child.lua_get([==[vim.api.nvim_win_get_cursor(0)[1]]==])
  -- Cursor should have moved forward to a hunk boundary
  expect.equality(after > 1, true)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["[c moves cursor backward from later position"] = function()
  local repo = create_repo_with_multi_hunk(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  focus_left_buffer()

  -- Jump forward twice to get past the first hunk
  child.type_keys("]c")
  helpers.wait_short(child, 100)
  child.type_keys("]c")
  helpers.wait_short(child, 100)

  local at_second = child.lua_get([==[vim.api.nvim_win_get_cursor(0)[1]]==])

  -- Now go back
  child.type_keys("[c")
  helpers.wait_short(child, 100)

  local after_prev = child.lua_get([==[vim.api.nvim_win_get_cursor(0)[1]]==])
  -- Cursor should have moved backward
  expect.equality(after_prev < at_second, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Directory tree collapse tests
-- =============================================================================

T["diff view"]["Tab toggles directory collapse in panel"] = function()
  local repo = create_repo_with_subdir_staged(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  focus_panel()

  -- Count panel lines before collapse: header + sep + dir(src) + alpha.lua + beta.lua = 5
  local lines_before = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.panel then return 0 end
    return vim.api.nvim_buf_line_count(view.panel.bufnr)
  end)()]])
  eq(lines_before, 5)

  -- Navigate to dir line (line 3) and press Tab
  child.lua([[vim.api.nvim_win_set_cursor(0, {3, 0})]])
  child.type_keys("<Tab>")
  helpers.wait_short(child, 200)

  -- After collapse: header + sep + dir(src, collapsed) = 3
  local lines_after = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.panel then return 0 end
    return vim.api.nvim_buf_line_count(view.panel.bufnr)
  end)()]])
  eq(lines_after, 3)

  -- Press Tab again to expand
  child.type_keys("<Tab>")
  helpers.wait_short(child, 200)

  local lines_expanded = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.panel then return 0 end
    return vim.api.nvim_buf_line_count(view.panel.bufnr)
  end)()]])
  eq(lines_expanded, 5)

  helpers.cleanup_repo(child, repo)
end

T["diff view"]["CR on dir line toggles collapse in panel"] = function()
  local repo = create_repo_with_subdir_staged(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  focus_panel()

  -- Navigate to dir line and press CR
  child.lua([[vim.api.nvim_win_set_cursor(0, {3, 0})]])
  child.type_keys("<CR>")
  helpers.wait_short(child, 200)

  -- Should be collapsed
  local lines_collapsed = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.panel then return 0 end
    return vim.api.nvim_buf_line_count(view.panel.bufnr)
  end)()]])
  eq(lines_collapsed, 3)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Refresh tests
-- =============================================================================

T["diff view"]["gr refreshes diff view with new changes"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  -- Should have 1 file initially
  local initial_count = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view then return 0 end
    return #view.diff_spec.file_pairs
  end)()]])
  eq(initial_count, 1)

  -- Stage a new file
  helpers.create_file(child, repo, "extra.lua", "-- extra\n")
  helpers.git(child, repo, "add extra.lua")

  -- Trigger refresh and wait for async completion
  child.lua([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if view then view:refresh() end
  end)()]])
  helpers.wait_short(child, 1500)

  -- Should now have 2 files
  local refreshed_count = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view then return 0 end
    return #view.diff_spec.file_pairs
  end)()]])
  eq(refreshed_count, 2)

  -- Panel should show the new file
  local has_extra = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.panel then return false end
    local lines = vim.api.nvim_buf_get_lines(view.panel.bufnr, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("extra", 1, true) then return true end
    end
    return false
  end)()]])
  eq(has_extra, true)

  helpers.cleanup_repo(child, repo)
end

-- =============================================================================
-- Panel window option tests
-- =============================================================================

T["diff view"]["panel window has wrap disabled"] = function()
  local repo = create_repo_with_staged_changes(child)
  helpers.cd(child, repo)

  open_staged_diff(repo)
  helpers.wait_short(child, 200)

  local wrap = child.lua_get([[(function()
    local view = require("gitlad.ui.views.diff").get_active()
    if not view or not view.panel or not vim.api.nvim_win_is_valid(view.panel.winnr) then
      return true
    end
    return vim.wo[view.panel.winnr].wrap
  end)()]])
  eq(wrap, false)

  helpers.cleanup_repo(child, repo)
end

return T
