---@mod gitlad.utils.keymap Keymap utilities
---@brief [[
--- Simplify buffer-local keymap setup.
---@brief ]]

local M = {}

--- Set a buffer-local keymap
---@param bufnr number
---@param mode string|string[]
---@param key string
---@param fn function
---@param desc string
---@param opts? {nowait?: boolean} Additional options
function M.set(bufnr, mode, key, fn, desc, opts)
  local keymap_opts = { buffer = bufnr, silent = true, desc = desc }
  if opts and opts.nowait then
    keymap_opts.nowait = true
  end
  vim.keymap.set(mode, key, fn, keymap_opts)
end

return M
