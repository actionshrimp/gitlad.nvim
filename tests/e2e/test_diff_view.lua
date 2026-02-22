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

return T
