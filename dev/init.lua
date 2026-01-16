-- Development helper for testing gitlad locally
-- Usage: nvim -u dev/init.lua

-- Add plugin to runtimepath
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)

-- Minimal settings
vim.opt.swapfile = false
vim.g.mapleader = " "

-- Load and setup gitlad
require("gitlad").setup()

-- Print confirmation
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.notify("[gitlad dev] Plugin loaded. Run :Gitlad to open status.", vim.log.levels.INFO)
  end,
})
