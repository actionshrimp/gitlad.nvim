-- E2E tests for worktrunk popup
-- Guarded: tests are skipped when `wt` is not in PATH
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Skip all tests if wt is not installed
if vim.fn.executable("wt") ~= 1 then
  T["worktrunk popup e2e"] = MiniTest.new_set()
  T["worktrunk popup e2e"]["SKIP: wt not in PATH"] = function()
    -- Guard: wt binary not found, skipping e2e worktrunk popup tests
  end
  return T
end

local helpers = require("tests.helpers")

T["worktrunk popup e2e"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
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

T["worktrunk popup e2e"]["popup opens in worktrunk mode when wt installed and auto"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Configure with worktrunk = "auto" (wt installed → worktrunk mode)
  child.lua([[require("gitlad").setup({ worktree = { worktrunk = "auto" } })]])
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Track which open function is called via monkey-patching before pressing %
  child.lua([[
    _G.worktrunk_popup_called = false
    local worktree_popup = require("gitlad.popups.worktree")
    local orig = worktree_popup._open_worktrunk_popup
    worktree_popup._open_worktrunk_popup = function(rs, ctx, cfg)
      _G.worktrunk_popup_called = true
      orig(rs, ctx, cfg)
    end
  ]])

  child.type_keys("%")
  helpers.wait_for_popup(child)

  local called = child.lua_get([[_G.worktrunk_popup_called]])
  eq(called, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["worktrunk popup e2e"]["popup opens in git mode when worktrunk = never"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua([[require("gitlad").setup({ worktree = { worktrunk = "never" } })]])
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.lua([[
    _G.git_popup_called = false
    local worktree_popup = require("gitlad.popups.worktree")
    local orig = worktree_popup._open_git_popup
    worktree_popup._open_git_popup = function(rs, ctx)
      _G.git_popup_called = true
      orig(rs, ctx)
    end
  ]])

  child.type_keys("%")
  helpers.wait_for_popup(child)

  local called = child.lua_get([[_G.git_popup_called]])
  eq(called, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["worktrunk popup e2e"]["Git Worktree escape hatch visible in worktrunk mode"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua([[require("gitlad").setup({ worktree = { worktrunk = "auto" } })]])
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("%")
  helpers.wait_for_popup(child)

  -- Check popup buffer contains "Git Worktree" heading
  child.lua([[
    local buf = vim.api.nvim_get_current_buf()
    _G.popup_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G.popup_lines]])

  local found = false
  if type(lines) == "table" then
    for _, line in ipairs(lines) do
      if type(line) == "string" and line:match("Git Worktree") then
        found = true
        break
      end
    end
  end
  eq(found, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

return T
