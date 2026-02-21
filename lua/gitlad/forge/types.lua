---@mod gitlad.forge.types Forge type definitions and helpers
---@brief [[
--- LuaCATS type definitions for forge integration (GitHub, etc.)
--- and small pure helper functions for display formatting.
---@brief ]]

local M = {}

-- =============================================================================
-- Type Definitions
-- =============================================================================

---@class ForgeUser
---@field login string Username
---@field avatar_url? string Avatar URL

---@class ForgePullRequest
---@field number number PR number
---@field title string PR title
---@field state string "open"|"closed"|"merged"
---@field draft boolean Whether this is a draft PR
---@field author ForgeUser PR author
---@field head_ref string Head branch name
---@field base_ref string Base branch name
---@field review_decision? string "APPROVED"|"CHANGES_REQUESTED"|"REVIEW_REQUIRED"|nil
---@field labels string[] Label names
---@field additions number Lines added
---@field deletions number Lines deleted
---@field created_at string ISO 8601 timestamp
---@field updated_at string ISO 8601 timestamp
---@field url string Web URL for the PR
---@field body? string PR description/body

---@class ForgeComment
---@field id string Comment ID
---@field author ForgeUser Comment author
---@field body string Comment body (markdown)
---@field created_at string ISO 8601 timestamp
---@field updated_at string ISO 8601 timestamp

---@class ForgeReview
---@field id string Review ID
---@field author ForgeUser Reviewer
---@field state string "APPROVED"|"CHANGES_REQUESTED"|"COMMENTED"|"PENDING"|"DISMISSED"
---@field body? string Review body
---@field submitted_at string ISO 8601 timestamp
---@field comments ForgeReviewComment[] Review comments

---@class ForgeReviewComment
---@field id string Comment ID
---@field author ForgeUser Comment author
---@field body string Comment body
---@field path string File path
---@field line? number Line number in the diff
---@field side? string "LEFT"|"RIGHT"
---@field created_at string ISO 8601 timestamp

---@class ForgeFile
---@field path string File path
---@field status string "added"|"modified"|"deleted"|"renamed"
---@field additions number Lines added
---@field deletions number Lines deleted
---@field patch? string Unified diff patch

---@class ForgeListPRsOpts
---@field state? string "open"|"closed"|"merged"|"all" (default: "open")
---@field limit? number Max PRs to fetch (default: 30)
---@field author? string Filter by author login

---@class ForgeProvider
---@field owner string Repository owner
---@field repo string Repository name
---@field host string API host (e.g. "github.com")
---@field provider_type string "github"|"gitlab"|"gitea"
---@field list_prs fun(self: ForgeProvider, opts: ForgeListPRsOpts, callback: fun(prs: ForgePullRequest[]|nil, err: string|nil))
---@field get_pr fun(self: ForgeProvider, number: number, callback: fun(pr: ForgePullRequest|nil, err: string|nil))

---@class ForgeRemoteInfo
---@field provider string "github"
---@field owner string Repository owner
---@field repo string Repository name
---@field host string Hostname (e.g. "github.com")

-- =============================================================================
-- Helper Functions
-- =============================================================================

--- Format a review decision for display
---@param decision string|nil "APPROVED"|"CHANGES_REQUESTED"|"REVIEW_REQUIRED"|nil
---@return string display_text Human-readable review status
function M.format_review_decision(decision)
  if not decision then
    return ""
  end
  local map = {
    APPROVED = "APPROVED",
    CHANGES_REQUESTED = "CHANGES REQUESTED",
    REVIEW_REQUIRED = "REVIEW REQUIRED",
  }
  return map[decision] or decision
end

--- Format an ISO 8601 timestamp as relative time (e.g. "2 days ago")
---@param iso_string string ISO 8601 timestamp (e.g. "2026-02-19T10:30:00Z")
---@return string relative_time Human-readable relative time
function M.relative_time(iso_string)
  if not iso_string or iso_string == "" then
    return ""
  end

  -- Parse ISO 8601: "2026-02-19T10:30:00Z"
  local year, month, day, hour, min, sec = iso_string:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return iso_string
  end

  local timestamp = os.time({
    year = tonumber(year) --[[@as integer]],
    month = tonumber(month) --[[@as integer]],
    day = tonumber(day) --[[@as integer]],
    hour = tonumber(hour) --[[@as integer]],
    min = tonumber(min) --[[@as integer]],
    sec = tonumber(sec) --[[@as integer]],
  })

  local now = os.time()
  local diff = now - timestamp

  if diff < 0 then
    return "in the future"
  elseif diff < 60 then
    return "just now"
  elseif diff < 3600 then
    local minutes = math.floor(diff / 60)
    return minutes == 1 and "1 minute ago" or minutes .. " minutes ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours == 1 and "1 hour ago" or hours .. " hours ago"
  elseif diff < 2592000 then -- ~30 days
    local days = math.floor(diff / 86400)
    return days == 1 and "1 day ago" or days .. " days ago"
  elseif diff < 31536000 then -- ~365 days
    local months = math.floor(diff / 2592000)
    return months == 1 and "1 month ago" or months .. " months ago"
  else
    local years = math.floor(diff / 31536000)
    return years == 1 and "1 year ago" or years .. " years ago"
  end
end

--- Format a PR state for display
---@param state string "open"|"closed"|"merged"
---@param draft boolean Whether the PR is a draft
---@return string display_text
function M.format_pr_state(state, draft)
  if draft then
    return "DRAFT"
  end
  local map = {
    open = "OPEN",
    closed = "CLOSED",
    merged = "MERGED",
  }
  return map[state] or state:upper()
end

--- Format additions/deletions as a compact diff stat
---@param additions number Lines added
---@param deletions number Lines deleted
---@return string stat_text e.g. "+10 -3"
function M.format_diff_stat(additions, deletions)
  return "+" .. additions .. " -" .. deletions
end

return M
