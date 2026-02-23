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

--- Worktree directory strategy examples (from /code/project/main, branch feature/foo):
---   "sibling"      → /code/project/main_feature-foo  (prefixed with current worktree name)
---   "sibling-bare" → /code/project/feature-foo       (just the branch name)
---   "prompt"       → always prompts for path with no default
---@class GitladWorktreeConfig
---@field directory_strategy "sibling"|"sibling-bare"|"prompt" How to suggest default worktree paths

---@class GitladWatcherConfig
---@field enabled boolean Whether to enable file watching for git state changes (default: true)
---@field stale_indicator boolean Show stale indicator when external changes detected (default: true)
---@field auto_refresh boolean Automatically refresh when external changes detected (default: false)
---@field cooldown_ms number Cooldown period in ms after gitlad operations before events are processed (default: 1000)
---@field auto_refresh_debounce_ms number Debounce period in ms before triggering auto-refresh (default: 500)
---@field watch_worktree boolean Whether to watch working tree files for changes (default: true)

---@class GitladOutputConfig
---@field hook_output "lazy"|"always"|"never" How to show hook output ("lazy" = only when output arrives, "always" = immediately, "never" = disabled)

---@class GitladForgeConfig
---@field show_pr_in_status boolean Show PR summary line in status buffer header (default: true)
---@field pr_info_ttl number Seconds before cached PR info is re-fetched on auto-refresh (default: 30). Manual refresh (gr) always bypasses this.

---@class GitladDiffConfig
---@field viewer "native" Diff viewer to use ("native" = built-in side-by-side)

---@class GitladConfig
---@field signs GitladSigns
---@field commit_editor GitladCommitEditorConfig
---@field status GitladStatusConfig
---@field worktree GitladWorktreeConfig
---@field watcher GitladWatcherConfig
---@field output GitladOutputConfig
---@field forge GitladForgeConfig
---@field diff GitladDiffConfig
---@field show_tags_in_refs boolean Whether to show tags alongside branch names in refs (default: false)
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
    directory_strategy = "sibling", -- "sibling", "sibling-bare", or "prompt"
  },
  watcher = {
    enabled = true, -- Can disable for performance-sensitive users
    stale_indicator = true, -- Show stale indicator when external changes detected
    auto_refresh = false, -- Automatically refresh when external changes detected
    cooldown_ms = 1000, -- Ignore events for 1s after gitlad operations
    auto_refresh_debounce_ms = 500, -- Debounce for auto_refresh
    watch_worktree = true, -- Watch working tree files for changes
  },
  output = {
    hook_output = "lazy", -- "lazy", "always", or "never"
  },
  forge = {
    show_pr_in_status = true, -- Show PR summary in status header
    pr_info_ttl = 30, -- Seconds before auto-refresh re-fetches PR info (gr always bypasses)
  },
  diff = {
    viewer = "native",
  },
  show_tags_in_refs = false,
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
