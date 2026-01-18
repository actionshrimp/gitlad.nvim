---@mod gitlad.constants Shared constants
---@brief [[
--- Magic string constants for consistent usage across the codebase.
---@brief ]]

local M = {}

---@enum SectionType
M.SECTION = {
  STAGED = "staged",
  UNSTAGED = "unstaged",
  UNTRACKED = "untracked",
  CONFLICTED = "conflicted",
  STASHES = "stashes",
}

return M
