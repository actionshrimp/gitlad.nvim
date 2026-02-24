-- Demo init for asciinema recording
-- Fully self-contained: bootstraps lazy.nvim into a temp directory,
-- installs all dependencies, then runs the demo.
--
-- Prerequisites: tree-sitter CLI (brew install tree-sitter)
-- Everything else is cached in /tmp/gitlad-demo-deps/ across runs.

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local deps_dir = "/tmp/gitlad-demo-deps"
local lazy_path = deps_dir .. "/lazy.nvim"

-- ---------------------------------------------------------------------------
-- Bootstrap lazy.nvim
-- ---------------------------------------------------------------------------
if not vim.uv.fs_stat(lazy_path) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazy_path,
  })
end
vim.opt.rtp:prepend(lazy_path)
package.path = lazy_path .. "/lua/?.lua;" .. lazy_path .. "/lua/?/init.lua;" .. package.path

-- ---------------------------------------------------------------------------
-- Neovim options - clean UI for recording
-- ---------------------------------------------------------------------------
vim.opt.swapfile = false
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.cmdheight = 1
vim.opt.laststatus = 2
vim.opt.showmode = false
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.termguicolors = true
vim.g.mapleader = " "

-- ---------------------------------------------------------------------------
-- Install plugins via lazy.nvim
-- ---------------------------------------------------------------------------
require("lazy").setup({
  { dir = plugin_root }, -- gitlad.nvim itself
  { "rebelot/kanagawa.nvim" },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
  },
}, {
  root = deps_dir .. "/plugins",
  lockfile = deps_dir .. "/lazy-lock.json",
  install = { colorscheme = { "kanagawa" } },
})

-- ---------------------------------------------------------------------------
-- Colorscheme
-- ---------------------------------------------------------------------------
pcall(vim.cmd, "colorscheme kanagawa")

-- ---------------------------------------------------------------------------
-- gitlad
-- ---------------------------------------------------------------------------
require("gitlad").setup()

-- ---------------------------------------------------------------------------
-- Demo driver (skip during warmup)
-- ---------------------------------------------------------------------------
if not vim.env.GITLAD_DEMO_WARMUP then
  local driver = vim.env.GITLAD_DEMO_DRIVER or "demo-basics-driver.lua"
  dofile(plugin_root .. "/scripts/" .. driver)
end
