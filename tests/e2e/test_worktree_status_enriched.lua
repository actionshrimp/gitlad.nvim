-- E2E tests for enriched worktrees section (wt list data merged into status)
-- Guarded: tests are skipped when `wt` is not in PATH
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

if vim.fn.executable("wt") ~= 1 then
  T["worktree status enriched e2e"] = MiniTest.new_set()
  T["worktree status enriched e2e"]["SKIP: wt not in PATH"] = function()
    -- Guard: wt binary not found, skipping e2e enriched worktree status tests
  end
  return T
end

local helpers = require("tests.helpers")

T["worktree status enriched e2e"] = MiniTest.new_set({
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

T["worktree status enriched e2e"]["wt list is called during status refresh when worktrunk active"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Enable worktrunk mode
  child.lua([[require("gitlad").setup({ worktree = { worktrunk = "auto" } })]])
  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Monkey-patch wt.list to track if it's called
  child.lua([[
    local wt = require("gitlad.worktrunk")
    local orig = wt.list
    _G.wt_list_called = false
    wt.list = function(opts, callback)
      _G.wt_list_called = true
      orig(opts, callback)
    end
  ]])

  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  local called = child.lua_get([[_G.wt_list_called]])
  eq(called, true)

  helpers.cleanup_repo(child, repo)
end

T["worktree status enriched e2e"]["wt list is NOT called when worktrunk = never"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua([[require("gitlad").setup({ worktree = { worktrunk = "never" } })]])
  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  child.lua([[
    local wt = require("gitlad.worktrunk")
    local orig = wt.list
    _G.wt_list_called_never = false
    wt.list = function(opts, callback)
      _G.wt_list_called_never = true
      orig(opts, callback)
    end
  ]])

  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Give it extra time to ensure wt.list would have fired if it were going to
  helpers.wait_short(child, 500)

  local called = child.lua_get([[_G.wt_list_called_never]])
  -- Should be false (not called) or vim.NIL (never set)
  local not_called = (called == false or called == vim.NIL)
  eq(not_called, true)

  helpers.cleanup_repo(child, repo)
end

return T
