-- Tests for gitlad.utils module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["utils"] = MiniTest.new_set()

T["utils"]["setup_view_window_options sets options locally"] = function()
  local utils = require("gitlad.utils")

  -- Create a test window with a buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  local winnr = vim.api.nvim_get_current_win()

  -- Apply window options
  utils.setup_view_window_options(winnr)

  -- Verify options are set on the target window
  eq(vim.api.nvim_get_option_value("number", { win = winnr }), false)
  eq(vim.api.nvim_get_option_value("relativenumber", { win = winnr }), false)
  eq(vim.api.nvim_get_option_value("signcolumn", { win = winnr }), "yes:1")
  eq(vim.api.nvim_get_option_value("foldcolumn", { win = winnr }), "0")
  eq(vim.api.nvim_get_option_value("wrap", { win = winnr }), false)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["utils"]["setup_view_window_options does not affect other windows"] = function()
  local utils = require("gitlad.utils")

  -- Create two windows
  local buf1 = vim.api.nvim_create_buf(false, true)
  local buf2 = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_set_current_buf(buf1)
  local win1 = vim.api.nvim_get_current_win()

  -- Create a split with the second buffer
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(buf2)
  local win2 = vim.api.nvim_get_current_win()

  -- Enable line numbers on win2
  vim.api.nvim_set_option_value("number", true, { win = win2, scope = "local" })

  -- Apply gitlad options to win1 only
  utils.setup_view_window_options(win1)

  -- Verify win1 has gitlad options
  eq(vim.api.nvim_get_option_value("number", { win = win1 }), false)

  -- Verify win2 still has line numbers enabled
  eq(vim.api.nvim_get_option_value("number", { win = win2 }), true)

  -- Cleanup
  vim.api.nvim_win_close(win2, true)
  vim.api.nvim_buf_delete(buf1, { force = true })
  vim.api.nvim_buf_delete(buf2, { force = true })
end

return T
