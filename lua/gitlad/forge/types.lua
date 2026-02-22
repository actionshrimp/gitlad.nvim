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
---@field comments? ForgeComment[] Issue comments
---@field reviews? ForgeReview[] Reviews
---@field timeline? ForgeTimelineItem[] Chronologically sorted timeline
---@field checks_summary? ForgeChecksSummary CI check rollup summary

---@class ForgeTimelineItem
---@field type "comment"|"review" Discriminator
---@field comment? ForgeComment Present when type == "comment"
---@field review? ForgeReview Present when type == "review"
---@field timestamp string ISO 8601 timestamp for sorting

---@class ForgeComment
---@field id string Comment ID
---@field database_id? number Numeric database ID (for REST API)
---@field author ForgeUser Comment author
---@field body string Comment body (markdown)
---@field created_at string ISO 8601 timestamp
---@field updated_at string ISO 8601 timestamp

---@class ForgeReview
---@field id string Review ID
---@field database_id? number Numeric database ID (for REST API)
---@field author ForgeUser Reviewer
---@field state string "APPROVED"|"CHANGES_REQUESTED"|"COMMENTED"|"PENDING"|"DISMISSED"
---@field body? string Review body
---@field submitted_at string ISO 8601 timestamp
---@field comments ForgeReviewComment[] Review comments

---@class ForgeReviewComment
---@field id string Comment ID
---@field database_id? number Numeric database ID (for REST API)
---@field author ForgeUser Comment author
---@field body string Comment body
---@field path string File path
---@field line? number Line number in the diff
---@field side? string "LEFT"|"RIGHT"
---@field created_at string ISO 8601 timestamp

---@class ForgeReviewThread
---@field id string GraphQL node ID
---@field is_resolved boolean
---@field is_outdated boolean
---@field path string File path
---@field line number|nil Current line in the diff
---@field original_line number|nil Original line number
---@field start_line number|nil Multi-line comment start
---@field diff_side string "LEFT"|"RIGHT"
---@field comments ForgeThreadComment[]

---@class ForgeThreadComment
---@field id string GraphQL node ID
---@field database_id number|nil Numeric database ID (for REST API)
---@field author ForgeUser Comment author
---@field body string Comment body (markdown)
---@field created_at string ISO 8601 timestamp
---@field updated_at string ISO 8601 timestamp

---@class ForgeCheck
---@field name string Check name (e.g. "CI / test")
---@field status string "queued"|"in_progress"|"completed"
---@field conclusion? string "success"|"failure"|"neutral"|"cancelled"|"skipped"|"timed_out"|"action_required"|"startup_failure"|nil
---@field details_url? string URL to the check details page
---@field app_name? string App name (e.g. "GitHub Actions")
---@field started_at? string ISO 8601 timestamp
---@field completed_at? string ISO 8601 timestamp

---@class ForgeChecksSummary
---@field state string "success"|"failure"|"pending" Overall rollup state
---@field total number Total number of checks
---@field success number Number of successful checks
---@field failure number Number of failed checks
---@field pending number Number of pending/in-progress checks
---@field checks ForgeCheck[] Individual check details

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
---@field get_review_threads? fun(self: ForgeProvider, pr_number: number, callback: fun(threads: ForgeReviewThread[]|nil, pr_node_id: string|nil, err: string|nil))
---@field create_review_comment? fun(self: ForgeProvider, pr_number: number, opts: table, callback: fun(comment: table|nil, err: string|nil))
---@field reply_to_review_comment? fun(self: ForgeProvider, pr_number: number, comment_id: number, body: string, callback: fun(comment: table|nil, err: string|nil))
---@field submit_review? fun(self: ForgeProvider, pr_node_id: string, event: string, body: string|nil, callback: fun(result: table|nil, err: string|nil))
---@field submit_review_with_comments? fun(self: ForgeProvider, pr_node_id: string, event: string, body: string|nil, threads: PendingComment[], callback: fun(result: table|nil, err: string|nil))

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

--- Format a check icon based on status/conclusion
---@param check ForgeCheck
---@return string icon Single character icon
---@return string hl_group Highlight group name
function M.format_check_icon(check)
  if check.status ~= "completed" then
    return "○", "GitladForgeCheckPending"
  end
  local conclusion = check.conclusion
  if conclusion == "success" then
    return "✓", "GitladForgeCheckSuccess"
  elseif
    conclusion == "failure"
    or conclusion == "timed_out"
    or conclusion == "startup_failure"
  then
    return "✗", "GitladForgeCheckFailure"
  elseif conclusion == "cancelled" then
    return "⊘", "GitladForgeCheckNeutral"
  elseif conclusion == "skipped" then
    return "⊘", "GitladForgeCheckNeutral"
  elseif conclusion == "neutral" then
    return "◎", "GitladForgeCheckNeutral"
  elseif conclusion == "action_required" then
    return "!", "GitladForgeCheckPending"
  end
  return "?", "GitladForgeCheckNeutral"
end

--- Format a compact checks summary for PR list / status line
--- Returns e.g. "3/3" (all pass), "1/3" (failures), "~2/3" (pending)
---@param summary ForgeChecksSummary
---@return string text
---@return string hl_group
function M.format_checks_compact(summary)
  if summary.total == 0 then
    return "", "Comment"
  end
  if summary.pending > 0 then
    return "~" .. (summary.total - summary.pending) .. "/" .. summary.total,
      "GitladForgeCheckPending"
  elseif summary.failure > 0 then
    return summary.success .. "/" .. summary.total, "GitladForgeCheckFailure"
  else
    return summary.success .. "/" .. summary.total, "GitladForgeCheckSuccess"
  end
end

--- Format duration between two ISO 8601 timestamps
---@param started_at? string ISO 8601 timestamp
---@param completed_at? string ISO 8601 timestamp
---@return string duration e.g. "2m 30s", "" if timestamps missing
function M.format_check_duration(started_at, completed_at)
  if not started_at or started_at == "" or started_at == vim.NIL then
    return ""
  end
  if not completed_at or completed_at == "" or completed_at == vim.NIL then
    return ""
  end

  local function parse_iso(iso)
    local year, month, day, hour, min, sec = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not year then
      return nil
    end
    return os.time({
      year = tonumber(year) --[[@as integer]],
      month = tonumber(month) --[[@as integer]],
      day = tonumber(day) --[[@as integer]],
      hour = tonumber(hour) --[[@as integer]],
      min = tonumber(min) --[[@as integer]],
      sec = tonumber(sec) --[[@as integer]],
    })
  end

  local start_ts = parse_iso(started_at)
  local end_ts = parse_iso(completed_at)
  if not start_ts or not end_ts then
    return ""
  end

  local diff = end_ts - start_ts
  if diff < 0 then
    return ""
  end

  if diff < 60 then
    return diff .. "s"
  elseif diff < 3600 then
    local minutes = math.floor(diff / 60)
    local seconds = diff % 60
    if seconds > 0 then
      return minutes .. "m " .. seconds .. "s"
    end
    return minutes .. "m"
  else
    local hours = math.floor(diff / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    if minutes > 0 then
      return hours .. "h " .. minutes .. "m"
    end
    return hours .. "h"
  end
end

return M
