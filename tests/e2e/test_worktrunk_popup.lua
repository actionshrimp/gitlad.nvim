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

  -- Ensure worktrunk = "auto" and wt is detected
  child.lua([[
    require("gitlad").setup({ worktree = { worktrunk = "auto" } })
    local wt = require("gitlad.worktrunk")
    -- Mock _executable to return true for "wt" regardless of actual PATH
    wt._executable = function(name) return name == "wt" end
  ]])

  -- Open the worktree popup
  child.lua(string.format(
    [[
      local state = require("gitlad.state")
      local repo_state = state.get_or_create(%q)
      local worktree_popup = require("gitlad.popups.worktree")

      -- Track which open function is called
      _G.worktrunk_popup_called = false
      local orig = worktree_popup._open_worktrunk_popup
      worktree_popup._open_worktrunk_popup = function(rs, ctx, cfg)
        _G.worktrunk_popup_called = true
        orig(rs, ctx, cfg)
      end

      worktree_popup.open(repo_state, nil)
    ]],
    repo
  ))

  local called = child.lua_get([[_G.worktrunk_popup_called]])
  eq(called, true)

  child.type_keys("q")
end

T["worktrunk popup e2e"]["popup opens in git mode when worktrunk = never"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua([[
    require("gitlad").setup({ worktree = { worktrunk = "never" } })
  ]])

  child.lua(string.format(
    [[
      local state = require("gitlad.state")
      local repo_state = state.get_or_create(%q)
      local worktree_popup = require("gitlad.popups.worktree")

      _G.git_popup_called = false
      local orig = worktree_popup._open_git_popup
      worktree_popup._open_git_popup = function(rs, ctx)
        _G.git_popup_called = true
        orig(rs, ctx)
      end

      worktree_popup.open(repo_state, nil)
    ]],
    repo
  ))

  local called = child.lua_get([[_G.git_popup_called]])
  eq(called, true)

  child.type_keys("q")
end

T["worktrunk popup e2e"]["Git Worktree escape hatch visible in worktrunk mode"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua([[
    require("gitlad").setup({ worktree = { worktrunk = "auto" } })
    local wt = require("gitlad.worktrunk")
    wt._executable = function(name) return name == "wt" end
  ]])

  child.lua(string.format(
    [[
      local state = require("gitlad.state")
      local repo_state = state.get_or_create(%q)
      local worktree_popup = require("gitlad.popups.worktree")
      worktree_popup.open(repo_state, nil)
    ]],
    repo
  ))

  -- Check popup buffer contains "Git Worktree" heading
  local lines = child.lua_get([[
    local buf = vim.api.nvim_get_current_buf()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ]])

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
end

return T
