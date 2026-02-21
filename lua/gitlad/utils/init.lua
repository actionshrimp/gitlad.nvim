---@mod gitlad.utils Utility modules
---@brief [[
--- Index for utility modules and common utilities.
---@brief ]]

local M = {}

M.errors = require("gitlad.utils.errors")
M.keymap = require("gitlad.utils.keymap")
M.path = require("gitlad.utils.path")
M.prompt = require("gitlad.utils.prompt")
M.remote = require("gitlad.utils.remote")

--- Close a view buffer by switching back to the previous buffer
--- Used by log, refs, and other views that take over the current window
---@param obj table Object with a `winnr` field to clear
function M.close_view_buffer(obj)
  if not obj.winnr or not vim.api.nvim_win_is_valid(obj.winnr) then
    obj.winnr = nil
    return
  end

  -- Go back to previous buffer or close window
  local prev_buf = vim.fn.bufnr("#")
  if prev_buf ~= -1 and vim.api.nvim_buf_is_valid(prev_buf) then
    vim.api.nvim_set_current_buf(prev_buf)
  else
    vim.cmd("quit")
  end
  obj.winnr = nil
end

--- Set up standard window-local options for gitlad buffer views
--- Used by status, log, and other buffer views for consistent display
--- Uses nvim_set_option_value with explicit scope to prevent global leakage
---@param winnr number Window number
function M.setup_view_window_options(winnr)
  local opts = { win = winnr, scope = "local" }
  vim.api.nvim_set_option_value("number", false, opts)
  vim.api.nvim_set_option_value("relativenumber", false, opts)
  vim.api.nvim_set_option_value("signcolumn", "yes:1", opts)
  vim.api.nvim_set_option_value("foldcolumn", "0", opts)
  vim.api.nvim_set_option_value("wrap", false, opts)
end

return M
