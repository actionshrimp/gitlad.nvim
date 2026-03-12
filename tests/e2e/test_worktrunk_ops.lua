-- E2E tests for worktrunk operations (wt switch, wt list, wt remove)
-- Guarded: tests are skipped when `wt` is not in PATH
-- Note: these tests verify the async wt CLI wrappers work end-to-end.
-- Full workflow tests (switch+list+remove) depend on a properly configured
-- worktrunk repo, so we test the async wiring and error handling here.
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Skip all tests if wt is not installed
if vim.fn.executable("wt") ~= 1 then
  T["worktrunk ops e2e"] = MiniTest.new_set()
  T["worktrunk ops e2e"]["SKIP: wt not in PATH"] = function()
    -- Guard: wt binary not found, skipping e2e worktrunk ops tests
  end
  return T
end

local helpers = require("tests.helpers")

T["worktrunk ops e2e"] = MiniTest.new_set({
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

T["worktrunk ops e2e"]["wt list callback is invoked (completes without crash)"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Run wt list — it may fail for a non-worktrunk repo but callback must be called
  -- Note: do NOT pre-initialize the var to false — wait_for_var checks ~= nil
  child.lua(string.format(
    [[
      local wt = require("gitlad.worktrunk")
      wt.list({ cwd = %q }, function(infos, err)
        _G.wt_list_done = true
        _G.wt_list_infos = infos
        _G.wt_list_err = err
      end)
    ]],
    repo
  ))

  -- The callback must always be invoked (success or error)
  helpers.wait_for_var(child, "_G.wt_list_done", 5000)
  local done = child.lua_get([[_G.wt_list_done]])
  eq(done, true)
end

T["worktrunk ops e2e"]["wt remove callback is invoked for unknown branch (error path)"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Remove a non-existent branch — should fail gracefully with callback invoked
  -- Note: do NOT pre-initialize vars to false — wait_for_var checks ~= nil
  child.lua(string.format(
    [[
      local wt = require("gitlad.worktrunk")
      wt.remove("nonexistent-branch-xyz", { cwd = %q }, function(ok, err)
        _G.wt_remove_done = true
        _G.wt_remove_ok = ok
        _G.wt_remove_err = err
      end)
    ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.wt_remove_done", 5000)
  local done = child.lua_get([[_G.wt_remove_done]])
  local ok = child.lua_get([[_G.wt_remove_ok]])
  eq(done, true)
  -- Should fail for unknown branch
  eq(ok, false)

  helpers.cleanup_repo(child, repo)
end

return T
