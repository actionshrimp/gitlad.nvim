---@mod gitlad.config Configuration management
local M = {}

---@class GitladCommitEditorConfig
---@field split "above"|"replace" How to open the commit editor ("above" = split above status, "replace" = replace current buffer)

---@class GitladSectionConfig
---@field [1] string Section name (first array element)
---@field count? number For "recent" section - number of commits to show (default: 10)
---@field min_count? number For "worktrees" section - minimum worktrees to show section (default: 2)

---@alias GitladSection string|GitladSectionConfig

---@class GitladStatusConfig
---@field sections? GitladSection[] Section order and options. Omit sections to hide them. Options: "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent". Use table form for options: { "recent", count = 5 }

---@class GitladWorktreeConfig
---@field directory_strategy "sibling"|"prompt" How to suggest worktree paths ("sibling" = suggest sibling directory, "prompt" = always prompt for path)

---@class GitladWatcherConfig
---@field enabled boolean Whether to enable file watching for stale view detection (default: false)
---@field cooldown_ms number Cooldown period in ms after gitlad operations before events trigger stale (default: 1000)

---@class GitladConfig
---@field signs GitladSigns
---@field commit_editor GitladCommitEditorConfig
---@field status GitladStatusConfig
---@field worktree GitladWorktreeConfig
---@field watcher GitladWatcherConfig
local defaults = {
  signs = {
    staged = "●",
    unstaged = "○",
    untracked = "?",
    conflict = "!",
  },
  commit_editor = {
    split = "above", -- "above" or "replace"
  },
  status = {},
  worktree = {
    directory_strategy = "sibling", -- "sibling" or "prompt"
  },
  watcher = {
    enabled = true, -- Can disable for performance-sensitive users
    cooldown_ms = 1000, -- Ignore events for 1s after gitlad operations
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
