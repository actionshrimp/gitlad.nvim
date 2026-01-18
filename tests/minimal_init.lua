-- Minimal init for testing gitlad.nvim
-- This file sets up the test environment

-- Add plugin to runtimepath
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)

-- Add mini.nvim to runtimepath if available (for mini.test)
local mini_path = vim.fn.stdpath("data") .. "/site/pack/deps/start/mini.nvim"
if vim.fn.isdirectory(mini_path) == 1 then
  vim.opt.runtimepath:prepend(mini_path)
end

-- Alternatively, check for mini.test directly
local mini_test_path = vim.fn.stdpath("data") .. "/site/pack/deps/start/mini.test"
if vim.fn.isdirectory(mini_test_path) == 1 then
  vim.opt.runtimepath:prepend(mini_test_path)
end

-- Disable swap files, shada, and other noise for parallel test execution
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shadafile = "NONE"

-- Set up leader key (common requirement)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load the plugin
require("gitlad").setup()
