---@mod gitlad.utils Utility modules
---@brief [[
--- Index for utility modules and common utilities.
---@brief ]]

local M = {}

M.errors = require("gitlad.utils.errors")
M.keymap = require("gitlad.utils.keymap")

--- Set up standard window-local options for gitlad buffer views
--- Used by status, log, and other buffer views for consistent display
---@param winnr number Window number
function M.setup_view_window_options(winnr)
  vim.wo[winnr].number = false
  vim.wo[winnr].relativenumber = false
  vim.wo[winnr].signcolumn = "yes:1"
  vim.wo[winnr].foldcolumn = "0"
  vim.wo[winnr].wrap = false
end

return M
