-- Tests for DiffBufferPair editable mode
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["gitlad.ui.views.diff.buffer"] = nil
    end,
  },
})

T["editable buffer"] = MiniTest.new_set()

-- Helper to create a split and return two window handles
local function create_split()
  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  local right_winnr = vim.api.nvim_get_current_win()
  return left_winnr, right_winnr
end

-- Helper to clean up after test
local function cleanup(pair, left_winnr, right_winnr)
  pair:destroy()
  if vim.api.nvim_win_is_valid(left_winnr) and left_winnr ~= right_winnr then
    vim.api.nvim_win_close(left_winnr, true)
  end
end

-- =============================================================================
-- Buffer setup with editable flag
-- =============================================================================

T["editable buffer"]["right buffer uses acwrite when editable"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  eq(vim.bo[pair.left_bufnr].buftype, "nofile")
  eq(vim.bo[pair.right_bufnr].buftype, "acwrite")
  eq(vim.bo[pair.left_bufnr].modifiable, false)
  eq(vim.bo[pair.right_bufnr].modifiable, true)
  eq(pair._editable, true)

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["without editable flag both are nofile"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr)

  eq(vim.bo[pair.left_bufnr].buftype, "nofile")
  eq(vim.bo[pair.right_bufnr].buftype, "nofile")
  eq(pair._editable, false)

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["left buffer is always read-only after set_content"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "line 1" },
    right_lines = { "line 1" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  eq(vim.bo[pair.left_bufnr].modifiable, false)
  eq(vim.bo[pair.right_bufnr].modifiable, true)

  cleanup(pair, left_winnr, right_winnr)
end

-- =============================================================================
-- Filler extmark tracking
-- =============================================================================

T["editable buffer"]["places filler extmarks on right buffer"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "hello", "deleted", "" },
    right_lines = { "hello", "", "added" },
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

  -- Should have exactly 1 filler extmark on line 1 (0-indexed)
  local marks = vim.api.nvim_buf_get_extmarks(pair.right_bufnr, pair._filler_ns, 0, -1, {})
  eq(#marks, 1)
  eq(marks[1][2], 1) -- 0-indexed line 1

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["no filler extmarks when not editable"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

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

  local marks = vim.api.nvim_buf_get_extmarks(pair.right_bufnr, pair._filler_ns, 0, -1, {})
  eq(#marks, 0)

  cleanup(pair, left_winnr, right_winnr)
end

-- =============================================================================
-- get_real_lines tests
-- =============================================================================

T["editable buffer"]["get_real_lines strips filler lines"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "hello", "deleted", "" },
    right_lines = { "hello", "", "added" },
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

  -- Right buffer has 3 lines: "hello", "~" (filler), "added"
  -- get_real_lines should strip the filler → "hello", "added"
  local real = pair:get_real_lines(pair.right_bufnr)
  eq(real, { "hello", "added" })

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["get_real_lines returns all lines when not editable"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

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

  local real = pair:get_real_lines(pair.right_bufnr)
  eq(real, { "hello", "world" })

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["get_real_lines works with multiple filler lines"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "a", "b", "c", "" },
    right_lines = { "a", "", "", "d" },
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
        left_type = "delete",
        right_type = "filler",
        left_lineno = 3,
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

  local real = pair:get_real_lines(pair.right_bufnr)
  eq(real, { "a", "d" })

  cleanup(pair, left_winnr, right_winnr)
end

-- =============================================================================
-- has_unsaved_changes tests
-- =============================================================================

T["editable buffer"]["has_unsaved_changes returns false initially"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "hello" },
    right_lines = { "hello" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  eq(pair:has_unsaved_changes(), false)

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["has_unsaved_changes returns true after edit"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "hello" },
    right_lines = { "hello" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
    },
  }

  pair:set_content(aligned, "test.lua")

  -- Simulate editing
  vim.api.nvim_buf_set_lines(pair.right_bufnr, 0, -1, false, { "modified" })
  vim.bo[pair.right_bufnr].modified = true

  eq(pair:has_unsaved_changes(), true)

  cleanup(pair, left_winnr, right_winnr)
end

T["editable buffer"]["has_unsaved_changes returns false when not editable"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr)

  eq(pair:has_unsaved_changes(), false)

  cleanup(pair, left_winnr, right_winnr)
end

-- =============================================================================
-- Buffer name tests
-- =============================================================================

T["editable buffer"]["sets buffer name on set_content when editable"] = function()
  local buffer = require("gitlad.ui.views.diff.buffer")
  local left_winnr, right_winnr = create_split()

  local pair = buffer.new(left_winnr, right_winnr, { editable = true })

  local aligned = {
    left_lines = { "hello" },
    right_lines = { "hello" },
    line_map = {
      {
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
        hunk_index = 1,
        is_hunk_boundary = true,
      },
    },
  }

  pair:set_content(aligned, "src/foo.lua")

  local name = vim.api.nvim_buf_get_name(pair.right_bufnr)
  expect.equality(name:match("gitlad://diff/src/foo.lua$") ~= nil, true)

  cleanup(pair, left_winnr, right_winnr)
end

return T
