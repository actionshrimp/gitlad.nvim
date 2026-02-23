-- Tests for gitlad.ui.views.diff.buffer_triple module
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["gitlad.ui.views.diff.buffer_triple"] = nil
    end,
  },
})

T["buffer_triple"] = MiniTest.new_set()

-- =============================================================================
-- Module loading tests
-- =============================================================================

T["buffer_triple"]["module loads and exports expected functions"] = function()
  local buffer_triple = require("gitlad.ui.views.diff.buffer_triple")

  eq(type(buffer_triple.new), "function")
  eq(type(buffer_triple._hl_for_type), "table")
  eq(type(buffer_triple._apply_filler_content), "function")
end

-- =============================================================================
-- Highlight group mapping tests
-- =============================================================================

T["buffer_triple"]["_hl_for_type"] = MiniTest.new_set()

T["buffer_triple"]["_hl_for_type"]["maps left-side types correctly"] = function()
  local bt = require("gitlad.ui.views.diff.buffer_triple")
  local hl = bt._hl_for_type

  eq(hl.left.context, nil)
  eq(hl.left.change, "GitladDiffChangeOld")
  eq(hl.left.delete, "GitladDiffDelete")
  eq(hl.left.add, nil)
  eq(hl.left.filler, "GitladDiffFiller")
end

T["buffer_triple"]["_hl_for_type"]["maps mid-side types correctly"] = function()
  local bt = require("gitlad.ui.views.diff.buffer_triple")
  local hl = bt._hl_for_type

  eq(hl.mid.context, nil)
  eq(hl.mid.change, "GitladDiffChangeNew")
  eq(hl.mid.add, "GitladDiffAdd")
  eq(hl.mid.delete, nil)
  eq(hl.mid.filler, "GitladDiffFiller")
end

T["buffer_triple"]["_hl_for_type"]["maps right-side types correctly"] = function()
  local bt = require("gitlad.ui.views.diff.buffer_triple")
  local hl = bt._hl_for_type

  eq(hl.right.context, nil)
  eq(hl.right.change, "GitladDiffChangeNew")
  eq(hl.right.add, "GitladDiffAdd")
  eq(hl.right.delete, nil)
  eq(hl.right.filler, "GitladDiffFiller")
end

-- =============================================================================
-- Filler content tests
-- =============================================================================

T["buffer_triple"]["_apply_filler_content"] = MiniTest.new_set()

T["buffer_triple"]["_apply_filler_content"]["replaces filler lines with tilde"] = function()
  local bt = require("gitlad.ui.views.diff.buffer_triple")

  local left = { "hello", "world", "" }
  local mid = { "hello", "", "world" }
  local right = { "", "world", "world" }
  local line_map = {
    { left_type = "context", mid_type = "context", right_type = "filler" },
    { left_type = "context", mid_type = "filler", right_type = "context" },
    { left_type = "filler", mid_type = "context", right_type = "context" },
  }

  bt._apply_filler_content(left, mid, right, line_map)
  eq(left[1], "hello")
  eq(left[3], "~") -- filler
  eq(mid[2], "~") -- filler
  eq(right[1], "~") -- filler
end

T["buffer_triple"]["_apply_filler_content"]["does not modify non-filler lines"] = function()
  local bt = require("gitlad.ui.views.diff.buffer_triple")

  local left = { "line1" }
  local mid = { "line1" }
  local right = { "line1" }
  local line_map = {
    { left_type = "context", mid_type = "context", right_type = "context" },
  }

  bt._apply_filler_content(left, mid, right, line_map)
  eq(left[1], "line1")
  eq(mid[1], "line1")
  eq(right[1], "line1")
end

T["buffer_triple"]["_apply_filler_content"]["handles all three as filler"] = function()
  local bt = require("gitlad.ui.views.diff.buffer_triple")

  local left = { "" }
  local mid = { "" }
  local right = { "" }
  local line_map = {
    { left_type = "filler", mid_type = "filler", right_type = "filler" },
  }

  bt._apply_filler_content(left, mid, right, line_map)
  eq(left[1], "~")
  eq(mid[1], "~")
  eq(right[1], "~")
end

return T
