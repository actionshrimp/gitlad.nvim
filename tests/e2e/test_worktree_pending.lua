-- End-to-end tests for pending worktree operation indicators
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to get status buffer lines
local function get_status_lines(child)
  return child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
end

--- Helper to get sign hl_group on a specific line
---@param child any
---@param line_num number 1-indexed line number
---@return string|userdata sign_hl_group or vim.NIL
local function get_sign_hl_on_line(child, line_num)
  child.lua(string.format(
    [[
    local ns = vim.api.nvim_get_namespaces()["gitlad_signs"]
    _G._test_sign_hl = nil
    if ns then
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, {%d, 0}, {%d, 0}, { details = true })
      for _, mark in ipairs(marks) do
        if mark[4] and mark[4].sign_hl_group then
          _G._test_sign_hl = mark[4].sign_hl_group
        end
      end
    end
  ]],
    line_num - 1,
    line_num - 1
  ))
  return child.lua_get("_G._test_sign_hl")
end

--- Helper to resolve a path in the child process (handles /tmp -> /private/tmp on macOS)
---@param child any
---@param path string
---@return string
local function resolve_path(child, path)
  return child.lua_get(string.format([[vim.uv.fs_realpath(%q) or %q]], path, path))
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
        -- Clear pending ops in child
        _G.child.lua([[
          local ok, pending_ops = pcall(require, "gitlad.state.pending_ops")
          if ok then pending_ops.clear_all() end
        ]])
        _G.child.stop()
        _G.child = nil
      end
    end,
  },
})

T["pending worktree indicators"] = MiniTest.new_set()

T["pending worktree indicators"]["spinner sign appears on worktree with pending delete"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit and second worktree
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  local worktree_path = child.lua_get("vim.fn.tempname()")
  helpers.git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Find the feature worktree line
  local lines = get_status_lines(child)
  local feature_line_num = nil
  local in_worktrees = false
  for i, line in ipairs(lines) do
    if line:match("^Worktrees") then
      in_worktrees = true
    elseif in_worktrees then
      if line == "" then
        break
      end
      if line:match("^feature") then
        feature_line_num = i
        break
      end
    end
  end
  eq(feature_line_num ~= nil, true)

  -- Verify no pending sign before registering
  local hl_before = get_sign_hl_on_line(child, feature_line_num)
  eq(hl_before ~= "GitladWorktreePending", true)

  -- Use the repo_root from the active state (already resolved by git)
  -- and get the worktree path as git knows it
  child.lua([[
    local pending_ops = require("gitlad.state.pending_ops")
    local repo_state = require("gitlad.state").get()
    -- Get the actual worktree path from git's worktree list
    local wt_path = nil
    for _, wt in ipairs(repo_state.status.worktrees) do
      if wt.branch == "feature" then
        wt_path = wt.path
        break
      end
    end
    _G._test_wt_path = wt_path
    _G._test_done = pending_ops.register(wt_path, "delete", "Deleting worktree...", repo_state.repo_root)
  ]])

  -- Wait for on_change to trigger a re-render
  helpers.wait_short(child, 400)

  -- Check sign is now GitladWorktreePending
  local hl_after = get_sign_hl_on_line(child, feature_line_num)
  eq(hl_after, "GitladWorktreePending")

  -- Clean up pending op
  child.lua([[_G._test_done()]])
  helpers.wait_short(child, 400)

  -- Sign should no longer be pending
  local hl_final = get_sign_hl_on_line(child, feature_line_num)
  eq(hl_final ~= "GitladWorktreePending", true)

  -- Cleanup
  local resolved_wt = resolve_path(child, worktree_path)
  helpers.git(child, repo, string.format("worktree remove %s", resolved_wt))
  helpers.cleanup_repo(child, repo)
end

T["pending worktree indicators"]["phantom line appears for pending add"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit and second worktree (to make section visible)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  local worktree_path = child.lua_get("vim.fn.tempname()")
  helpers.git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Verify no "(creating...)" line initially
  local lines_before = get_status_lines(child)
  local found_creating_before = false
  for _, line in ipairs(lines_before) do
    if line:match("%(creating%.%.%.%)") then
      found_creating_before = true
      break
    end
  end
  eq(found_creating_before, false)

  -- Register a pending add for a new path, using the real repo_root
  child.lua([[
    local pending_ops = require("gitlad.state.pending_ops")
    local repo_state = require("gitlad.state").get()
    _G._test_done = pending_ops.register("/tmp/test-phantom-worktree", "add", "Creating worktree...", repo_state.repo_root)
  ]])

  -- Wait for re-render
  helpers.wait_short(child, 400)

  -- Verify "(creating...)" phantom line appeared
  local lines_after = get_status_lines(child)
  local found_creating_after = false
  for _, line in ipairs(lines_after) do
    if line:match("%(creating%.%.%.%)") then
      found_creating_after = true
      break
    end
  end
  eq(found_creating_after, true)

  -- Call done() and verify phantom line disappears
  child.lua([[_G._test_done()]])
  helpers.wait_short(child, 400)

  local lines_final = get_status_lines(child)
  local found_creating_final = false
  for _, line in ipairs(lines_final) do
    if line:match("%(creating%.%.%.%)") then
      found_creating_final = true
      break
    end
  end
  eq(found_creating_final, false)

  -- Cleanup
  local resolved_wt = resolve_path(child, worktree_path)
  helpers.git(child, repo, string.format("worktree remove %s", resolved_wt))
  helpers.cleanup_repo(child, repo)
end

T["pending worktree indicators"]["phantom add makes worktree section visible with only 1 real worktree"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (only 1 worktree, section normally hidden)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Section should NOT be visible (only 1 worktree)
  local lines_before = get_status_lines(child)
  local found_worktrees_before = false
  for _, line in ipairs(lines_before) do
    if line:match("^Worktrees") then
      found_worktrees_before = true
      break
    end
  end
  eq(found_worktrees_before, false)

  -- Register a pending add using the real repo_root
  child.lua([[
      local pending_ops = require("gitlad.state.pending_ops")
      local repo_state = require("gitlad.state").get()
      _G._test_done = pending_ops.register("/tmp/phantom-wt", "add", "Creating worktree...", repo_state.repo_root)
    ]])

  -- Wait for re-render
  helpers.wait_short(child, 400)

  -- Section should now be visible
  local lines_after = get_status_lines(child)
  local found_worktrees_after = false
  for _, line in ipairs(lines_after) do
    if line:match("^Worktrees") then
      found_worktrees_after = true
      break
    end
  end
  eq(found_worktrees_after, true)

  -- Clean up
  child.lua([[_G._test_done()]])
  helpers.wait_short(child, 400)

  helpers.cleanup_repo(child, repo)
end

T["pending worktree indicators"]["spinner sign has GitladWorktreePending highlight on phantom line"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit and second worktree
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  local worktree_path = child.lua_get("vim.fn.tempname()")
  helpers.git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Register a pending add using real repo_root
  child.lua([[
      local pending_ops = require("gitlad.state.pending_ops")
      local repo_state = require("gitlad.state").get()
      _G._test_done = pending_ops.register("/tmp/phantom-wt", "add", "Creating...", repo_state.repo_root)
    ]])

  -- Wait for re-render
  helpers.wait_short(child, 400)

  -- Find the phantom line
  local lines = get_status_lines(child)
  local phantom_line_num = nil
  for i, line in ipairs(lines) do
    if line:match("%(creating%.%.%.%)") then
      phantom_line_num = i
      break
    end
  end
  eq(phantom_line_num ~= nil, true)

  -- Check it has the pending highlight
  local hl = get_sign_hl_on_line(child, phantom_line_num)
  eq(hl, "GitladWorktreePending")

  -- Clean up
  child.lua([[_G._test_done()]])
  helpers.wait_short(child, 400)

  local resolved_wt = resolve_path(child, worktree_path)
  helpers.git(child, repo, string.format("worktree remove %s", resolved_wt))
  helpers.cleanup_repo(child, repo)
end

T["pending worktree indicators"]["quit guard"] = MiniTest.new_set()

T["pending worktree indicators"]["quit guard"][":q is prevented when user declines with pending op"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Open status (this also calls setup() which registers the QuitPre autocmd)
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Register a pending op
  child.lua([[
    local pending_ops = require("gitlad.state.pending_ops")
    local repo_state = require("gitlad.state").get()
    _G._test_done = pending_ops.register("/tmp/test-wt", "delete", "Deleting worktree...", repo_state.repo_root)
  ]])

  -- Mock vim.fn.confirm to return 2 (No / don't quit)
  child.lua([[
    _G._orig_confirm = vim.fn.confirm
    vim.fn.confirm = function() return 2 end
  ]])

  -- Try to quit — should be prevented
  -- Use pcall-style since :q will raise E37 after our guard sets modified=true
  child.lua([[pcall(vim.cmd, "q")]])
  helpers.wait_short(child, 200)

  -- Neovim should still be alive — verify we can still interact
  local still_alive = child.lua_get([[type(vim.api.nvim_get_current_buf())]])
  eq(still_alive, "number")

  -- Buffer state should be restored (buftype back to nofile, not modified)
  local buftype = child.lua_get([[vim.bo.buftype]])
  eq(buftype, "nofile")
  local modified = child.lua_get([[vim.bo.modified]])
  eq(modified, false)

  -- Restore confirm and clean up
  child.lua([[
    vim.fn.confirm = _G._orig_confirm
    _G._test_done()
  ]])
  helpers.cleanup_repo(child, repo)
end

T["pending worktree indicators"]["quit guard"]["no confirm dialog when no pending ops"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Track whether confirm was called (it shouldn't be)
  child.lua([[
    _G._confirm_called = false
    _G._orig_confirm = vim.fn.confirm
    vim.fn.confirm = function(...)
      _G._confirm_called = true
      return _G._orig_confirm(...)
    end
  ]])

  -- Open a second buffer so :q doesn't try to exit Neovim entirely
  child.lua([[vim.cmd("new")]])

  -- Quit the new window — should succeed without confirm since no pending ops
  child.lua([[vim.cmd("q")]])
  helpers.wait_short(child, 100)

  local confirm_called = child.lua_get([[_G._confirm_called]])
  eq(confirm_called, false)

  -- Restore
  child.lua([[vim.fn.confirm = _G._orig_confirm]])
  helpers.cleanup_repo(child, repo)
end

T["pending worktree indicators"]["quit guard"][":q is allowed when user confirms with pending op"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Register a pending op
  child.lua([[
    local pending_ops = require("gitlad.state.pending_ops")
    local repo_state = require("gitlad.state").get()
    _G._test_done = pending_ops.register("/tmp/test-wt", "delete", "Deleting worktree...", repo_state.repo_root)
  ]])

  -- Mock vim.fn.confirm to return 1 (Yes / allow quit)
  child.lua([[
    vim.fn.confirm = function() return 1 end
  ]])

  -- Open a second window so :q closes just this window, not the whole process
  child.lua([[vim.cmd("split")]])
  local win_count_before = child.lua_get([[#vim.api.nvim_list_wins()]])

  -- Quit the current window — should be allowed since user said Yes
  child.lua([[vim.cmd("q")]])
  helpers.wait_short(child, 200)

  -- One fewer window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, win_count_before - 1)

  -- Clean up
  child.lua([[_G._test_done()]])
  helpers.cleanup_repo(child, repo)
end

return T
