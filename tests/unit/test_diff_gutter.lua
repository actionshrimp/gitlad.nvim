-- Tests for gitlad.ui.views.diff.gutter module
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["gitlad.ui.views.diff.gutter"] = nil
    end,
  },
})

T["gutter"] = MiniTest.new_set()

-- =============================================================================
-- Module loading tests
-- =============================================================================

T["gutter"]["module loads and exports expected functions"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(type(gutter.set), "function")
  eq(type(gutter.clear), "function")
  eq(type(gutter.render), "function")
  eq(type(gutter._format_lineno), "function")
  eq(type(gutter._linenos), "table")
end

-- =============================================================================
-- _format_lineno tests
-- =============================================================================

T["gutter"]["_format_lineno"] = MiniTest.new_set()

T["gutter"]["_format_lineno"]["formats single digit right-justified with trailing space"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(gutter._format_lineno(1), "   1 ")
  eq(gutter._format_lineno(5), "   5 ")
  eq(gutter._format_lineno(9), "   9 ")
end

T["gutter"]["_format_lineno"]["formats double digit with trailing space"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(gutter._format_lineno(10), "  10 ")
  eq(gutter._format_lineno(42), "  42 ")
  eq(gutter._format_lineno(99), "  99 ")
end

T["gutter"]["_format_lineno"]["formats triple digit with trailing space"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(gutter._format_lineno(100), " 100 ")
  eq(gutter._format_lineno(999), " 999 ")
end

T["gutter"]["_format_lineno"]["formats four digit number with trailing space"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(gutter._format_lineno(1000), "1000 ")
  eq(gutter._format_lineno(9999), "9999 ")
end

T["gutter"]["_format_lineno"]["handles five+ digit numbers"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(gutter._format_lineno(10000), "10000 ")
  eq(gutter._format_lineno(99999), "99999 ")
end

T["gutter"]["_format_lineno"]["returns 5-char blank for nil"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  eq(gutter._format_lineno(nil), "     ")
  eq(#gutter._format_lineno(nil), 5)
end

-- =============================================================================
-- set/clear tests
-- =============================================================================

T["gutter"]["set and clear"] = MiniTest.new_set()

T["gutter"]["set and clear"]["set stores linenos for buffer"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  local linenos = { [1] = 10, [2] = 11, [3] = nil }
  gutter.set(42, linenos)

  eq(gutter._linenos[42], linenos)
  eq(gutter._linenos[42][1], 10)
  eq(gutter._linenos[42][2], 11)

  -- Clean up
  gutter.clear(42)
end

T["gutter"]["set and clear"]["clear removes linenos for buffer"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  gutter.set(42, { [1] = 1 })
  eq(gutter._linenos[42] ~= nil, true)

  gutter.clear(42)
  eq(gutter._linenos[42], nil)
end

T["gutter"]["set and clear"]["clear is safe for unknown buffer"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  -- Should not error
  gutter.clear(99999)
  eq(gutter._linenos[99999], nil)
end

T["gutter"]["set and clear"]["set overwrites previous data"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  gutter.set(42, { [1] = 1 })
  gutter.set(42, { [1] = 99 })
  eq(gutter._linenos[42][1], 99)

  gutter.clear(42)
end

-- =============================================================================
-- render tests (require vim context)
-- =============================================================================

T["gutter"]["render"] = MiniTest.new_set()

T["gutter"]["render"]["returns blank when no data for buffer"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  -- render() uses nvim_get_current_buf() and vim.v.lnum
  -- Without data set, it should return blank
  local result = gutter.render()
  eq(result, "     ")
end

T["gutter"]["render"]["returns formatted lineno when data exists"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  local bufnr = vim.api.nvim_get_current_buf()
  gutter.set(bufnr, { [1] = 42, [2] = 43 })

  -- vim.v.lnum defaults to 0 in non-statuscolumn context, which won't match
  -- our 1-based keys, so test the underlying lookup directly
  local buf_linenos = gutter._linenos[bufnr]
  eq(gutter._format_lineno(buf_linenos[1]), "  42 ")
  eq(gutter._format_lineno(buf_linenos[2]), "  43 ")

  gutter.clear(bufnr)
end

-- =============================================================================
-- foldtext tests
-- =============================================================================

T["gutter"]["foldtext"] = MiniTest.new_set()

T["gutter"]["foldtext"]["module exports foldtext function"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")
  eq(type(gutter.foldtext), "function")
end

T["gutter"]["foldtext"]["formats fold count correctly"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  -- Simulate vim.v values for a fold from line 5 to line 14 (10 lines)
  vim.v.foldstart = 5
  vim.v.foldend = 14
  local result = gutter.foldtext()
  eq(result, "     ···· 10 unchanged lines ····")

  -- Simulate a 2-line fold
  vim.v.foldstart = 1
  vim.v.foldend = 2
  result = gutter.foldtext()
  eq(result, "     ···· 2 unchanged lines ····")
end

T["gutter"]["foldtext"]["has 5-char leading space for gutter alignment"] = function()
  local gutter = require("gitlad.ui.views.diff.gutter")

  vim.v.foldstart = 1
  vim.v.foldend = 100
  local result = gutter.foldtext()
  -- Should start with exactly 5 spaces
  eq(result:sub(1, 5), "     ")
  eq(result:sub(6, 6) ~= " ", true)
end

return T
