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

-- =============================================================================
-- format_check_icon
-- =============================================================================

T["format_check_icon()"] = MiniTest.new_set()

T["format_check_icon()"]["returns pending icon for in_progress status"] = function()
  local icon, hl_group = types.format_check_icon({ name = "test", status = "in_progress" })
  eq(icon, "○")
  eq(hl_group, "GitladForgeCheckPending")
end

T["format_check_icon()"]["returns pending icon for queued status"] = function()
  local icon, hl_group = types.format_check_icon({ name = "test", status = "queued" })
  eq(icon, "○")
  eq(hl_group, "GitladForgeCheckPending")
end

T["format_check_icon()"]["returns success icon for success conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "success" })
  eq(icon, "✓")
  eq(hl_group, "GitladForgeCheckSuccess")
end

T["format_check_icon()"]["returns failure icon for failure conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "failure" })
  eq(icon, "✗")
  eq(hl_group, "GitladForgeCheckFailure")
end

T["format_check_icon()"]["returns failure icon for timed_out conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "timed_out" })
  eq(icon, "✗")
  eq(hl_group, "GitladForgeCheckFailure")
end

T["format_check_icon()"]["returns neutral icon for cancelled conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "cancelled" })
  eq(icon, "⊘")
  eq(hl_group, "GitladForgeCheckNeutral")
end

T["format_check_icon()"]["returns neutral icon for skipped conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "skipped" })
  eq(icon, "⊘")
  eq(hl_group, "GitladForgeCheckNeutral")
end

T["format_check_icon()"]["returns neutral icon for neutral conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "neutral" })
  eq(icon, "◎")
  eq(hl_group, "GitladForgeCheckNeutral")
end

T["format_check_icon()"]["returns pending icon for action_required conclusion"] = function()
  local icon, hl_group =
    types.format_check_icon({ name = "test", status = "completed", conclusion = "action_required" })
  eq(icon, "!")
  eq(hl_group, "GitladForgeCheckPending")
end

-- =============================================================================
-- format_checks_compact
-- =============================================================================

T["format_checks_compact()"] = MiniTest.new_set()

T["format_checks_compact()"]["returns empty for zero checks"] = function()
  local text, hl_group = types.format_checks_compact({
    state = "success",
    total = 0,
    success = 0,
    failure = 0,
    pending = 0,
    checks = {},
  })
  eq(text, "")
  eq(hl_group, "Comment")
end

T["format_checks_compact()"]["returns green for all passing"] = function()
  local text, hl_group = types.format_checks_compact({
    state = "success",
    total = 3,
    success = 3,
    failure = 0,
    pending = 0,
    checks = {},
  })
  eq(text, "3/3")
  eq(hl_group, "GitladForgeCheckSuccess")
end

T["format_checks_compact()"]["returns red for failures"] = function()
  local text, hl_group = types.format_checks_compact({
    state = "failure",
    total = 3,
    success = 1,
    failure = 2,
    pending = 0,
    checks = {},
  })
  eq(text, "1/3")
  eq(hl_group, "GitladForgeCheckFailure")
end

T["format_checks_compact()"]["returns yellow for pending"] = function()
  local text, hl_group = types.format_checks_compact({
    state = "pending",
    total = 3,
    success = 1,
    failure = 0,
    pending = 2,
    checks = {},
  })
  eq(text, "~1/3")
  eq(hl_group, "GitladForgeCheckPending")
end

T["format_checks_compact()"]["pending takes priority over failure in display"] = function()
  local text, hl_group = types.format_checks_compact({
    state = "pending",
    total = 4,
    success = 1,
    failure = 1,
    pending = 2,
    checks = {},
  })
  eq(text, "~2/4")
  eq(hl_group, "GitladForgeCheckPending")
end

-- =============================================================================
-- format_check_duration
-- =============================================================================

T["format_check_duration()"] = MiniTest.new_set()

T["format_check_duration()"]["returns empty for nil timestamps"] = function()
  eq(types.format_check_duration(nil, nil), "")
end

T["format_check_duration()"]["returns empty for empty timestamps"] = function()
  eq(types.format_check_duration("", ""), "")
end

T["format_check_duration()"]["returns empty for nil started_at"] = function()
  eq(types.format_check_duration(nil, "2026-02-20T10:01:00Z"), "")
end

T["format_check_duration()"]["returns empty for nil completed_at"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", nil), "")
end

T["format_check_duration()"]["formats seconds"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", "2026-02-20T10:00:30Z"), "30s")
end

T["format_check_duration()"]["formats minutes and seconds"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", "2026-02-20T10:02:30Z"), "2m 30s")
end

T["format_check_duration()"]["formats minutes only when no seconds"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", "2026-02-20T10:05:00Z"), "5m")
end

T["format_check_duration()"]["formats hours and minutes"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", "2026-02-20T11:30:00Z"), "1h 30m")
end

T["format_check_duration()"]["formats hours only when no minutes"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", "2026-02-20T12:00:00Z"), "2h")
end

T["format_check_duration()"]["formats zero duration"] = function()
  eq(types.format_check_duration("2026-02-20T10:00:00Z", "2026-02-20T10:00:00Z"), "0s")
end

T["format_check_duration()"]["returns empty for invalid timestamps"] = function()
  eq(types.format_check_duration("invalid", "also-invalid"), "")
end

T["format_check_duration()"]["returns empty for vim.NIL timestamps"] = function()
  eq(types.format_check_duration(vim.NIL, "2026-02-20T10:01:00Z"), "")
  eq(types.format_check_duration("2026-02-20T10:00:00Z", vim.NIL), "")
  eq(types.format_check_duration(vim.NIL, vim.NIL), "")
end

-- =============================================================================
-- format_merge_status()
-- =============================================================================

T["format_merge_status()"] = MiniTest.new_set()

T["format_merge_status()"]["returns ready for MERGEABLE + CLEAN"] = function()
  local text, hl = types.format_merge_status("MERGEABLE", "CLEAN")
  eq(text, "Ready to merge")
  eq(hl, "GitladForgePRApproved")
end

T["format_merge_status()"]["returns conflicts for CONFLICTING"] = function()
  local text, hl = types.format_merge_status("CONFLICTING", "DIRTY")
  eq(text, "Conflicts")
  eq(hl, "GitladForgePRChangesRequested")
end

T["format_merge_status()"]["returns blocked for BLOCKED state"] = function()
  local text, hl = types.format_merge_status("MERGEABLE", "BLOCKED")
  eq(text, "Blocked")
  eq(hl, "GitladForgePRChangesRequested")
end

T["format_merge_status()"]["returns behind for BEHIND state"] = function()
  local text, hl = types.format_merge_status("MERGEABLE", "BEHIND")
  eq(text, "Behind base branch")
  eq(hl, "GitladForgePRReviewRequired")
end

T["format_merge_status()"]["returns unstable for UNSTABLE state"] = function()
  local text, hl = types.format_merge_status("MERGEABLE", "UNSTABLE")
  eq(text, "Unstable")
  eq(hl, "GitladForgePRReviewRequired")
end

T["format_merge_status()"]["returns unknown for nil mergeable"] = function()
  local text, hl = types.format_merge_status(nil, nil)
  eq(text, "Unknown")
  eq(hl, "Comment")
end

T["format_merge_status()"]["returns draft for DRAFT state"] = function()
  local text, hl = types.format_merge_status("UNKNOWN", "DRAFT")
  eq(text, "Draft")
  eq(hl, "GitladForgePRDraft")
end

return T
