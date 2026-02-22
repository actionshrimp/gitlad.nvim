local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local types = require("gitlad.forge.types")

-- =============================================================================
-- format_review_decision
-- =============================================================================

T["format_review_decision()"] = MiniTest.new_set()

T["format_review_decision()"]["returns APPROVED for APPROVED"] = function()
  eq(types.format_review_decision("APPROVED"), "APPROVED")
end

T["format_review_decision()"]["returns CHANGES REQUESTED for CHANGES_REQUESTED"] = function()
  eq(types.format_review_decision("CHANGES_REQUESTED"), "CHANGES REQUESTED")
end

T["format_review_decision()"]["returns REVIEW REQUIRED for REVIEW_REQUIRED"] = function()
  eq(types.format_review_decision("REVIEW_REQUIRED"), "REVIEW REQUIRED")
end

T["format_review_decision()"]["returns empty string for nil"] = function()
  eq(types.format_review_decision(nil), "")
end

T["format_review_decision()"]["returns unknown decision as-is"] = function()
  eq(types.format_review_decision("SOMETHING_ELSE"), "SOMETHING_ELSE")
end

-- =============================================================================
-- relative_time
-- =============================================================================

T["relative_time()"] = MiniTest.new_set()

T["relative_time()"]["returns empty string for nil"] = function()
  eq(types.relative_time(nil), "")
end

T["relative_time()"]["returns empty string for empty string"] = function()
  eq(types.relative_time(""), "")
end

T["relative_time()"]["returns original string for unparseable input"] = function()
  eq(types.relative_time("not-a-date"), "not-a-date")
end

T["relative_time()"]["returns 'just now' for recent timestamps"] = function()
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  eq(types.relative_time(now), "just now")
end

T["relative_time()"]["returns minutes ago"] = function()
  local past = os.time() - 300 -- 5 minutes ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "5 minutes ago")
end

T["relative_time()"]["returns 1 minute ago (singular)"] = function()
  local past = os.time() - 90 -- 1.5 minutes ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "1 minute ago")
end

T["relative_time()"]["returns hours ago"] = function()
  local past = os.time() - 7200 -- 2 hours ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "2 hours ago")
end

T["relative_time()"]["returns 1 hour ago (singular)"] = function()
  local past = os.time() - 3600 -- 1 hour ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "1 hour ago")
end

T["relative_time()"]["returns days ago"] = function()
  local past = os.time() - 172800 -- 2 days ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "2 days ago")
end

T["relative_time()"]["returns 1 day ago (singular)"] = function()
  local past = os.time() - 86400 -- 1 day ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "1 day ago")
end

T["relative_time()"]["returns months ago"] = function()
  local past = os.time() - (86400 * 60) -- ~2 months ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "2 months ago")
end

T["relative_time()"]["returns years ago"] = function()
  local past = os.time() - (86400 * 400) -- ~1 year ago
  local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", past)
  eq(types.relative_time(iso), "1 year ago")
end

-- =============================================================================
-- format_pr_state
-- =============================================================================

T["format_pr_state()"] = MiniTest.new_set()

T["format_pr_state()"]["returns OPEN for open non-draft"] = function()
  eq(types.format_pr_state("open", false), "OPEN")
end

T["format_pr_state()"]["returns CLOSED for closed"] = function()
  eq(types.format_pr_state("closed", false), "CLOSED")
end

T["format_pr_state()"]["returns MERGED for merged"] = function()
  eq(types.format_pr_state("merged", false), "MERGED")
end

T["format_pr_state()"]["returns DRAFT when draft is true regardless of state"] = function()
  eq(types.format_pr_state("open", true), "DRAFT")
end

T["format_pr_state()"]["uppercases unknown states"] = function()
  eq(types.format_pr_state("custom", false), "CUSTOM")
end

-- =============================================================================
-- format_diff_stat
-- =============================================================================

T["format_diff_stat()"] = MiniTest.new_set()

T["format_diff_stat()"]["formats additions and deletions"] = function()
  eq(types.format_diff_stat(10, 3), "+10 -3")
end

T["format_diff_stat()"]["handles zero additions"] = function()
  eq(types.format_diff_stat(0, 5), "+0 -5")
end

T["format_diff_stat()"]["handles zero deletions"] = function()
  eq(types.format_diff_stat(7, 0), "+7 -0")
end

T["format_diff_stat()"]["handles both zero"] = function()
  eq(types.format_diff_stat(0, 0), "+0 -0")
end

return T
