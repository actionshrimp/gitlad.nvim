---@mod gitlad.config Configuration management
local M = {}

---@class GitladConfig
---@field refresh_on_focus boolean
---@field watch_gitdir boolean
---@field signs GitladSigns
local defaults = {
  refresh_on_focus = true,
  watch_gitdir = true,
  signs = {
    staged = "●",
    unstaged = "○",
    untracked = "?",
    conflict = "!",
  },
}

---@type GitladConfig
local current_config = nil

--- Setup configuration with user options
---@param opts? GitladSetupOptions
function M.setup(opts)
  current_config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

--- Get current configuration
---@return GitladConfig
function M.get()
  if not current_config then
    -- Return defaults if setup hasn't been called
    return vim.tbl_deep_extend("force", {}, defaults)
  end
  return current_config
end

--- Reset configuration to defaults (useful for testing)
function M.reset()
  current_config = nil
end

return M
