-- E2E tests for worktrunk operations (wt switch, wt remove, copy-ignored)
-- Guarded: tests are skipped when `wt` is not in PATH
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

T["worktrunk ops e2e"]["wt switch -c creates a worktree and wt remove removes it"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a worktree via wt switch -c
  local branch = "test-wt-branch"
  child.lua(string.format(
    [[
      local wt = require("gitlad.worktrunk")
      _G.wt_switch_ok = nil
      _G.wt_switch_err = nil
      wt.switch(%q, { cwd = %q, create = true }, function(ok, err)
        _G.wt_switch_ok = ok
        _G.wt_switch_err = err
      end)
    ]],
    branch,
    repo
  ))

  helpers.wait_for_var(child, "_G.wt_switch_ok", 5000)

  local ok = child.lua_get([[_G.wt_switch_ok]])
  eq(ok, true)

  -- Verify the branch shows up in wt list
  child.lua(string.format(
    [[
      local wt = require("gitlad.worktrunk")
      _G.wt_list_infos = nil
      wt.list({ cwd = %q }, function(infos, err)
        _G.wt_list_infos = infos
        _G.wt_list_err = err
      end)
    ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.wt_list_infos", 5000)

  local infos = child.lua_get([[_G.wt_list_infos]])
  local found = false
  if type(infos) == "table" then
    for _, info in ipairs(infos) do
      if type(info) == "table" and info.branch == branch then
        found = true
        break
      end
    end
  end
  eq(found, true)

  -- Remove the worktree via wt remove
  child.lua(string.format(
    [[
      local wt = require("gitlad.worktrunk")
      _G.wt_remove_ok = nil
      wt.remove(%q, { cwd = %q }, function(ok, err)
        _G.wt_remove_ok = ok
        _G.wt_remove_err = err
      end)
    ]],
    branch,
    repo
  ))

  helpers.wait_for_var(child, "_G.wt_remove_ok", 5000)

  local remove_ok = child.lua_get([[_G.wt_remove_ok]])
  eq(remove_ok, true)
end

return T
