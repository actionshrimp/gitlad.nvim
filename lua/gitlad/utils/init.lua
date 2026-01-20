---@mod gitlad.utils Utility modules
---@brief [[
--- Index for utility modules and common utilities.
---@brief ]]

local M = {}

M.errors = require("gitlad.utils.errors")
M.keymap = require("gitlad.utils.keymap")

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
