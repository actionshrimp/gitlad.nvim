-- Prevent double-loading
if vim.g.loaded_gitlad then
  return
end
vim.g.loaded_gitlad = true

-- Defer setup to allow lazy loading
-- Users should call require('gitlad').setup() in their config
