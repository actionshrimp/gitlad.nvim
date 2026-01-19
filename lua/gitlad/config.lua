---@mod gitlad.config Configuration management
local M = {}

---@class GitladCommitEditorConfig
---@field split "above"|"replace" How to open the commit editor ("above" = split above status, "replace" = replace current buffer)

---@class GitladStatusConfig
---@field show_submodules_section boolean Whether to show the dedicated Submodules section (default: false, like magit)

---@class GitladConfig
---@field refresh_on_focus boolean
---@field watch_gitdir boolean
---@field signs GitladSigns
---@field commit_editor GitladCommitEditorConfig
---@field status GitladStatusConfig
local defaults = {
  refresh_on_focus = true,
  watch_gitdir = true,
  signs = {
    staged = "●",
    unstaged = "○",
    untracked = "?",
    conflict = "!",
  },
  commit_editor = {
    split = "above", -- "above" or "replace"
  },
  status = {
    show_submodules_section = false, -- Off by default, like magit
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
