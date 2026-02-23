-- Tests for gitlad.ui.views.diff.save module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["gitlad.ui.views.diff.save"] = nil
    end,
  },
})

T["diff_save"] = MiniTest.new_set()

-- =============================================================================
-- Module loading tests
-- =============================================================================

T["diff_save"]["module loads and exports expected functions"] = function()
  local save = require("gitlad.ui.views.diff.save")

  eq(type(save.save_worktree), "function")
  eq(type(save.save_index), "function")
end

-- =============================================================================
-- save_worktree tests
-- =============================================================================

T["diff_save"]["save_worktree"] = MiniTest.new_set()

T["diff_save"]["save_worktree"]["writes lines to disk"] = function()
  local save = require("gitlad.ui.views.diff.save")

  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  local err_result
  save.save_worktree(tmp_dir, "test.lua", { "line1", "line2", "line3" }, function(err)
    err_result = err
  end)

  eq(err_result, nil)

  -- Verify file was written
  local lines = vim.fn.readfile(tmp_dir .. "/test.lua")
  eq(lines, { "line1", "line2", "line3" })

  vim.fn.delete(tmp_dir, "rf")
end

T["diff_save"]["save_worktree"]["overwrites existing file"] = function()
  local save = require("gitlad.ui.views.diff.save")

  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  -- Create existing file
  vim.fn.writefile({ "old content" }, tmp_dir .. "/test.lua")

  local err_result
  save.save_worktree(tmp_dir, "test.lua", { "new content" }, function(err)
    err_result = err
  end)

  eq(err_result, nil)

  local lines = vim.fn.readfile(tmp_dir .. "/test.lua")
  eq(lines, { "new content" })

  vim.fn.delete(tmp_dir, "rf")
end

T["diff_save"]["save_worktree"]["handles empty lines"] = function()
  local save = require("gitlad.ui.views.diff.save")

  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  local err_result
  save.save_worktree(tmp_dir, "empty.lua", {}, function(err)
    err_result = err
  end)

  eq(err_result, nil)

  local lines = vim.fn.readfile(tmp_dir .. "/empty.lua")
  eq(lines, {})

  vim.fn.delete(tmp_dir, "rf")
end

T["diff_save"]["save_worktree"]["reports error for invalid path"] = function()
  local save = require("gitlad.ui.views.diff.save")

  local err_result
  save.save_worktree("/nonexistent/path/xxx", "sub/test.lua", { "content" }, function(err)
    err_result = err
  end)

  expect.no_equality(err_result, nil)
end

return T
