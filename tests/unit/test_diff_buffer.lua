-- Tests for gitlad.ui.views.diff.buffer module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["gitlad.ui.views.diff.buffer"] = nil
    end,
  },
})

T["diff_buffer"] = MiniTest.new_set()

-- =============================================================================
-- Module loading tests
-- =============================================================================

T["diff_buffer"]["module loads and exports expected functions"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(type(buffer.new), "function")
  eq(type(buffer._hl_for_type), "table")
  eq(type(buffer._format_lineno), "function")
  eq(type(buffer._apply_filler_content), "function")
end

-- =============================================================================
-- Highlight group mapping tests
-- =============================================================================

T["diff_buffer"]["_hl_for_type"] = MiniTest.new_set()

T["diff_buffer"]["_hl_for_type"]["maps left-side types correctly"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local hl = buffer._hl_for_type

  eq(hl.left.context, nil)
  eq(hl.left.change, "GitladDiffChangeOld")
  eq(hl.left.delete, "GitladDiffDelete")
  eq(hl.left.add, nil)
  eq(hl.left.filler, "GitladDiffFiller")
end

T["diff_buffer"]["_hl_for_type"]["maps right-side types correctly"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local hl = buffer._hl_for_type

  eq(hl.right.context, nil)
  eq(hl.right.change, "GitladDiffChangeNew")
  eq(hl.right.add, "GitladDiffAdd")
  eq(hl.right.delete, nil)
  eq(hl.right.filler, "GitladDiffFiller")
end

-- =============================================================================
-- Line number formatting tests
-- =============================================================================

T["diff_buffer"]["_format_lineno"] = MiniTest.new_set()

T["diff_buffer"]["_format_lineno"]["formats single digit right-justified to 4 chars"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(buffer._format_lineno(1), "   1")
  eq(buffer._format_lineno(5), "   5")
  eq(buffer._format_lineno(9), "   9")
end

T["diff_buffer"]["_format_lineno"]["formats double digit right-justified to 4 chars"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(buffer._format_lineno(10), "  10")
  eq(buffer._format_lineno(42), "  42")
  eq(buffer._format_lineno(99), "  99")
end

T["diff_buffer"]["_format_lineno"]["formats triple digit right-justified to 4 chars"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(buffer._format_lineno(100), " 100")
  eq(buffer._format_lineno(999), " 999")
end

T["diff_buffer"]["_format_lineno"]["formats four digit number with no padding"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(buffer._format_lineno(1000), "1000")
  eq(buffer._format_lineno(9999), "9999")
end

T["diff_buffer"]["_format_lineno"]["handles five+ digit numbers (no truncation)"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(buffer._format_lineno(10000), "10000")
  eq(buffer._format_lineno(99999), "99999")
end

T["diff_buffer"]["_format_lineno"]["returns empty string for nil"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  eq(buffer._format_lineno(nil), "    ")
end

-- =============================================================================
-- DiffBufferPair creation tests (require vim windows)
-- =============================================================================

T["diff_buffer"]["new creates a DiffBufferPair with valid buffers"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  -- Create two windows by splitting
  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  -- Should have valid buffers
  eq(vim.api.nvim_buf_is_valid(pair.left_bufnr), true)
  eq(vim.api.nvim_buf_is_valid(pair.right_bufnr), true)

  -- Buffers should be scratch buffers
  eq(vim.bo[pair.left_bufnr].buftype, "nofile")
  eq(vim.bo[pair.right_bufnr].buftype, "nofile")
  eq(vim.bo[pair.left_bufnr].swapfile, false)
  eq(vim.bo[pair.right_bufnr].swapfile, false)
  eq(vim.bo[pair.left_bufnr].modifiable, false)
  eq(vim.bo[pair.right_bufnr].modifiable, false)

  -- Window options should be set
  for _, winnr in ipairs({ left_winnr, right_winnr }) do
    local opts = { win = winnr, scope = "local" }
    eq(vim.api.nvim_get_option_value("scrollbind", opts), true)
    eq(vim.api.nvim_get_option_value("cursorbind", opts), true)
    eq(vim.api.nvim_get_option_value("wrap", opts), false)
    eq(vim.api.nvim_get_option_value("number", opts), false)
    eq(vim.api.nvim_get_option_value("signcolumn", opts), "no")
    eq(vim.api.nvim_get_option_value("foldmethod", opts), "manual")
    eq(vim.api.nvim_get_option_value("foldenable", opts), false)
  end

  -- Clean up
  pair:destroy()
  -- Close the split window if it's still valid
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

T["diff_buffer"]["new stores window numbers"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  eq(pair.left_winnr, left_winnr)
  eq(pair.right_winnr, right_winnr)

  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

-- =============================================================================
-- set_content tests
-- =============================================================================

T["diff_buffer"]["set_content populates both buffers"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  local aligned = {
    left_lines = { "line 1", "line 2", "" },
    right_lines = { "line 1", "LINE 2", "line 3" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
      {
        left_type = "change",
        right_type = "change",
        left_lineno = 2,
        right_lineno = 2,
        hunk_index = 1,
        is_hunk_boundary = false,
      },
      {
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 3,
        hunk_index = 1,
        is_hunk_boundary = false,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  -- Check buffer contents (filler lines show "~")
  local left_lines = vim.api.nvim_buf_get_lines(pair.left_bufnr, 0, -1, false)
  local right_lines = vim.api.nvim_buf_get_lines(pair.right_bufnr, 0, -1, false)

  eq(left_lines, { "line 1", "line 2", "~" })
  eq(right_lines, { "line 1", "LINE 2", "line 3" })

  -- Check line_map is stored
  eq(#pair.line_map, 3)
  eq(pair.file_path, "test.lua")

  -- Buffers should be locked again
  eq(vim.bo[pair.left_bufnr].modifiable, false)
  eq(vim.bo[pair.right_bufnr].modifiable, false)

  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

T["diff_buffer"]["set_content applies diff highlights"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local hl = require("gitlad.ui.hl")
  hl.setup()

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  local aligned = {
    left_lines = { "context", "deleted", "" },
    right_lines = { "context", "", "added" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
      {
        left_type = "delete",
        right_type = "filler",
        left_lineno = 2,
        right_lineno = nil,
        hunk_index = 1,
        is_hunk_boundary = false,
      },
      {
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 2,
        hunk_index = 1,
        is_hunk_boundary = false,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  -- Check extmarks on left buffer
  local left_marks =
    vim.api.nvim_buf_get_extmarks(pair.left_bufnr, pair._ns, 0, -1, { details = true })
  -- Line 0 (context) should have a lineno extmark only (no line_hl_group for context)
  -- Line 1 (delete) should have GitladDiffDelete
  -- Line 2 (filler) should have GitladDiffFiller

  local left_line_hls = {}
  for _, mark in ipairs(left_marks) do
    if mark[4].line_hl_group then
      left_line_hls[mark[2]] = mark[4].line_hl_group
    end
  end

  eq(left_line_hls[0], nil) -- context: no line highlight
  eq(left_line_hls[1], "GitladDiffDelete")
  eq(left_line_hls[2], "GitladDiffFiller")

  -- Check extmarks on right buffer
  local right_marks =
    vim.api.nvim_buf_get_extmarks(pair.right_bufnr, pair._ns, 0, -1, { details = true })
  local right_line_hls = {}
  for _, mark in ipairs(right_marks) do
    if mark[4].line_hl_group then
      right_line_hls[mark[2]] = mark[4].line_hl_group
    end
  end

  eq(right_line_hls[0], nil) -- context: no line highlight
  eq(right_line_hls[1], "GitladDiffFiller")
  eq(right_line_hls[2], "GitladDiffAdd")

  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

T["diff_buffer"]["set_content adds line number virtual text"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local hl = require("gitlad.ui.hl")
  hl.setup()

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  local aligned = {
    left_lines = { "hello", "" },
    right_lines = { "hello", "world" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
      {
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 2,
        hunk_index = 1,
        is_hunk_boundary = false,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  -- Check left buffer has line number virtual text
  local left_marks =
    vim.api.nvim_buf_get_extmarks(pair.left_bufnr, pair._ns, 0, -1, { details = true })
  local left_virt_texts = {}
  for _, mark in ipairs(left_marks) do
    if mark[4].virt_text then
      left_virt_texts[mark[2]] = mark[4].virt_text[1][1]
    end
  end

  -- Line 0 should have lineno "   1"
  eq(left_virt_texts[0], "   1")
  -- Line 1 is filler, should have "    " (blank)
  eq(left_virt_texts[1], "    ")

  -- Check right buffer has line number virtual text
  local right_marks =
    vim.api.nvim_buf_get_extmarks(pair.right_bufnr, pair._ns, 0, -1, { details = true })
  local right_virt_texts = {}
  for _, mark in ipairs(right_marks) do
    if mark[4].virt_text then
      right_virt_texts[mark[2]] = mark[4].virt_text[1][1]
    end
  end

  eq(right_virt_texts[0], "   1")
  eq(right_virt_texts[1], "   2")

  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

-- =============================================================================
-- destroy tests
-- =============================================================================

T["diff_buffer"]["destroy deletes both buffers"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)
  local left_bufnr = pair.left_bufnr
  local right_bufnr = pair.right_bufnr

  pair:destroy()

  eq(vim.api.nvim_buf_is_valid(left_bufnr), false)
  eq(vim.api.nvim_buf_is_valid(right_bufnr), false)

  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

T["diff_buffer"]["destroy is safe to call twice"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  pair:destroy()
  pair:destroy() -- Should not error

  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

-- =============================================================================
-- set_content with change type highlights
-- =============================================================================

T["diff_buffer"]["set_content highlights change type on both sides"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local hl = require("gitlad.ui.hl")
  hl.setup()

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  local aligned = {
    left_lines = { "old line" },
    right_lines = { "new line" },
    line_map = {
      {
        left_type = "change",
        right_type = "change",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  -- Left side should have GitladDiffChangeOld
  local left_marks =
    vim.api.nvim_buf_get_extmarks(pair.left_bufnr, pair._ns, 0, -1, { details = true })
  local left_line_hl = nil
  for _, mark in ipairs(left_marks) do
    if mark[4].line_hl_group then
      left_line_hl = mark[4].line_hl_group
    end
  end
  eq(left_line_hl, "GitladDiffChangeOld")

  -- Right side should have GitladDiffChangeNew
  local right_marks =
    vim.api.nvim_buf_get_extmarks(pair.right_bufnr, pair._ns, 0, -1, { details = true })
  local right_line_hl = nil
  for _, mark in ipairs(right_marks) do
    if mark[4].line_hl_group then
      right_line_hl = mark[4].line_hl_group
    end
  end
  eq(right_line_hl, "GitladDiffChangeNew")

  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

-- =============================================================================
-- Filler line content tests
-- =============================================================================

T["diff_buffer"]["_apply_filler_content"] = MiniTest.new_set()

T["diff_buffer"]["_apply_filler_content"]["replaces filler lines with tilde on left"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  local left = { "hello", "" }
  local right = { "hello", "world" }
  local line_map = {
    { left_type = "context", right_type = "context" },
    { left_type = "filler", right_type = "add" },
  }

  buffer._apply_filler_content(left, right, line_map)

  eq(left, { "hello", "~" })
  eq(right, { "hello", "world" })
end

T["diff_buffer"]["_apply_filler_content"]["replaces filler lines with tilde on right"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  local left = { "hello", "world" }
  local right = { "hello", "" }
  local line_map = {
    { left_type = "context", right_type = "context" },
    { left_type = "delete", right_type = "filler" },
  }

  buffer._apply_filler_content(left, right, line_map)

  eq(left, { "hello", "world" })
  eq(right, { "hello", "~" })
end

T["diff_buffer"]["_apply_filler_content"]["handles both sides filler"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  local left = { "" }
  local right = { "" }
  local line_map = {
    { left_type = "filler", right_type = "filler" },
  }

  buffer._apply_filler_content(left, right, line_map)

  eq(left, { "~" })
  eq(right, { "~" })
end

T["diff_buffer"]["_apply_filler_content"]["does not modify non-filler lines"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")

  local left = { "context", "old line", "" }
  local right = { "context", "new line", "added" }
  local line_map = {
    { left_type = "context", right_type = "context" },
    { left_type = "change", right_type = "change" },
    { left_type = "filler", right_type = "add" },
  }

  buffer._apply_filler_content(left, right, line_map)

  eq(left, { "context", "old line", "~" })
  eq(right, { "context", "new line", "added" })
end

T["diff_buffer"]["set_content renders filler lines as tilde in buffers"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local hl = require("gitlad.ui.hl")
  hl.setup()

  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()

  local pair = buffer.new(left_winnr, right_winnr)

  local aligned = {
    left_lines = { "hello", "" },
    right_lines = { "hello", "world" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
      {
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 2,
        hunk_index = 1,
        is_hunk_boundary = false,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  -- Left filler line should be "~"
  local left_lines = vim.api.nvim_buf_get_lines(pair.left_bufnr, 0, -1, false)
  eq(left_lines[2], "~")

  -- Right non-filler line should remain as "world"
  local right_lines = vim.api.nvim_buf_get_lines(pair.right_bufnr, 0, -1, false)
  eq(right_lines[2], "world")

  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

-- =============================================================================
-- _find_file_index tests (from init.lua)
-- =============================================================================

T["diff_buffer"]["_find_file_index"] = MiniTest.new_set()

T["diff_buffer"]["_find_file_index"]["finds matching file by new_path"] = function()
  local diff_view = require("gitlad.ui.views.diff")

  local file_pairs = {
    { old_path = "alpha.lua", new_path = "alpha.lua", status = "M" },
    { old_path = "beta.lua", new_path = "beta.lua", status = "M" },
    { old_path = "gamma.lua", new_path = "gamma.lua", status = "A" },
  }

  eq(diff_view._find_file_index(file_pairs, "alpha.lua"), 1)
  eq(diff_view._find_file_index(file_pairs, "beta.lua"), 2)
  eq(diff_view._find_file_index(file_pairs, "gamma.lua"), 3)
end

T["diff_buffer"]["_find_file_index"]["returns nil for non-matching path"] = function()
  local diff_view = require("gitlad.ui.views.diff")

  local file_pairs = {
    { old_path = "alpha.lua", new_path = "alpha.lua", status = "M" },
  }

  eq(diff_view._find_file_index(file_pairs, "missing.lua"), nil)
end

T["diff_buffer"]["_find_file_index"]["returns nil for nil or empty path"] = function()
  local diff_view = require("gitlad.ui.views.diff")

  local file_pairs = {
    { old_path = "alpha.lua", new_path = "alpha.lua", status = "M" },
  }

  eq(diff_view._find_file_index(file_pairs, nil), nil)
  eq(diff_view._find_file_index(file_pairs, ""), nil)
end

T["diff_buffer"]["_find_file_index"]["matches old_path for renamed files"] = function()
  local diff_view = require("gitlad.ui.views.diff")

  local file_pairs = {
    { old_path = "old_name.lua", new_path = "new_name.lua", status = "R" },
  }

  eq(diff_view._find_file_index(file_pairs, "old_name.lua"), 1)
  eq(diff_view._find_file_index(file_pairs, "new_name.lua"), 1)
end

return T
