local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local comment_component = require("gitlad.ui.components.comment")

--- Build a minimal PR for testing
---@return ForgePullRequest
local function make_test_pr(overrides)
  local pr = {
    number = 42,
    title = "Fix authentication bug in login flow",
    state = "open",
    draft = false,
    author = { login = "octocat" },
    head_ref = "fix/auth-bug",
    base_ref = "main",
    review_decision = "APPROVED",
    labels = { "bug", "priority:high" },
    additions = 10,
    deletions = 3,
    created_at = "2026-02-19T10:30:00Z",
    updated_at = "2026-02-20T14:00:00Z",
    url = "https://github.com/owner/repo/pull/42",
    body = "Fixes the authentication bug that caused login failures.",
    comments = {
      {
        id = "IC_1001",
        database_id = 1001,
        author = { login = "reviewer" },
        body = "Looks good but I have a question.",
        created_at = "2026-02-19T14:00:00Z",
        updated_at = "2026-02-19T14:00:00Z",
      },
      {
        id = "IC_1002",
        database_id = 1002,
        author = { login = "octocat" },
        body = "Good point, updated.",
        created_at = "2026-02-19T16:00:00Z",
        updated_at = "2026-02-19T16:00:00Z",
      },
    },
    reviews = {
      {
        id = "PRR_3001",
        database_id = 3001,
        author = { login = "reviewer" },
        state = "APPROVED",
        body = "LGTM",
        submitted_at = "2026-02-20T10:00:00Z",
        comments = {},
      },
    },
    timeline = {},
  }
  if overrides then
    for k, v in pairs(overrides) do
      pr[k] = v
    end
  end
  return pr
end

-- =============================================================================
-- render()
-- =============================================================================

T["render()"] = MiniTest.new_set()

T["render()"]["includes PR title with number"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  -- First line should be "#42 Fix authentication bug..."
  expect.equality(result.lines[1]:match("#42") ~= nil, true)
  expect.equality(result.lines[1]:match("Fix authentication bug") ~= nil, true)
end

T["render()"]["includes author and state metadata"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  -- Should have metadata line with author and state
  local found_author = false
  local found_state = false
  for _, line in ipairs(result.lines) do
    if line:match("@octocat") then
      found_author = true
    end
    if line:match("OPEN") then
      found_state = true
    end
  end
  eq(found_author, true)
  eq(found_state, true)
end

T["render()"]["includes branch info and diff stat"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_branch = false
  for _, line in ipairs(result.lines) do
    if line:match("main") and line:match("fix/auth%-bug") and line:match("+10 %-3") then
      found_branch = true
    end
  end
  eq(found_branch, true)
end

T["render()"]["includes labels"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_labels = false
  for _, line in ipairs(result.lines) do
    if line:match("Labels:") and line:match("bug") and line:match("priority:high") then
      found_labels = true
    end
  end
  eq(found_labels, true)
end

T["render()"]["shows merge status when mergeable fields present"] = function()
  local pr = make_test_pr({ mergeable = "MERGEABLE", merge_state_status = "CLEAN" })
  local result = comment_component.render(pr)

  local found_merge = false
  for _, line in ipairs(result.lines) do
    if line:match("Merge:") and line:match("Ready to merge") then
      found_merge = true
    end
  end
  eq(found_merge, true)
end

T["render()"]["shows conflicts in merge status"] = function()
  local pr = make_test_pr({ mergeable = "CONFLICTING", merge_state_status = "DIRTY" })
  local result = comment_component.render(pr)

  local found_conflict = false
  for _, line in ipairs(result.lines) do
    if line:match("Merge:") and line:match("Conflicts") then
      found_conflict = true
    end
  end
  eq(found_conflict, true)
end

T["render()"]["shows blocked merge status"] = function()
  local pr = make_test_pr({ mergeable = "MERGEABLE", merge_state_status = "BLOCKED" })
  local result = comment_component.render(pr)

  local found_blocked = false
  for _, line in ipairs(result.lines) do
    if line:match("Merge:") and line:match("Blocked") then
      found_blocked = true
    end
  end
  eq(found_blocked, true)
end

T["render()"]["omits merge status when fields are nil"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_merge = false
  for _, line in ipairs(result.lines) do
    if line:match("^Merge:") then
      found_merge = true
    end
  end
  eq(found_merge, false)
end

T["render()"]["includes PR body"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_body = false
  for _, line in ipairs(result.lines) do
    if line:match("authentication bug") then
      found_body = true
    end
  end
  eq(found_body, true)
end

T["render()"]["includes comments section with correct count"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_section = false
  for _, line in ipairs(result.lines) do
    if line:match("Comments %(2%)") then
      found_section = true
    end
  end
  eq(found_section, true)
end

T["render()"]["includes comment content"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_reviewer_comment = false
  local found_author_comment = false
  for _, line in ipairs(result.lines) do
    if line:match("@reviewer") then
      found_reviewer_comment = true
    end
    if line:match("Good point, updated") then
      found_author_comment = true
    end
  end
  eq(found_reviewer_comment, true)
  eq(found_author_comment, true)
end

T["render()"]["includes reviews section with correct count"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_section = false
  for _, line in ipairs(result.lines) do
    if line:match("Reviews %(1%)") then
      found_section = true
    end
  end
  eq(found_section, true)
end

T["render()"]["includes review state"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  local found_approved = false
  for _, line in ipairs(result.lines) do
    if line:match("@reviewer") and line:match("APPROVED") then
      found_approved = true
    end
  end
  eq(found_approved, true)
end

T["render()"]["handles empty comments and reviews"] = function()
  local pr = make_test_pr({ comments = {}, reviews = {} })
  local result = comment_component.render(pr)

  local found_comments_0 = false
  local found_reviews_0 = false
  for _, line in ipairs(result.lines) do
    if line:match("Comments %(0%)") then
      found_comments_0 = true
    end
    if line:match("Reviews %(0%)") then
      found_reviews_0 = true
    end
  end
  eq(found_comments_0, true)
  eq(found_reviews_0, true)
end

T["render()"]["handles nil body"] = function()
  local pr = make_test_pr({ body = nil })
  local result = comment_component.render(pr)
  -- Should not crash, should have separator after header
  expect.equality(#result.lines > 0, true)
end

T["render()"]["handles empty body"] = function()
  local pr = make_test_pr({ body = "" })
  local result = comment_component.render(pr)
  expect.equality(#result.lines > 0, true)
end

T["render()"]["sets line_info types correctly"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  -- First line should be pr_header
  eq(result.line_info[1].type, "pr_header")

  -- Find a comment line
  local found_comment_info = false
  local found_review_info = false
  local found_section_header = false
  for _, info in pairs(result.line_info) do
    if info.type == "comment" then
      found_comment_info = true
    end
    if info.type == "review" then
      found_review_info = true
    end
    if info.type == "section_header" then
      found_section_header = true
    end
  end
  eq(found_comment_info, true)
  eq(found_review_info, true)
  eq(found_section_header, true)
end

T["render()"]["filters out PENDING reviews"] = function()
  local pr = make_test_pr({
    reviews = {
      {
        id = "PRR_1",
        author = { login = "bot" },
        state = "PENDING",
        body = "",
        submitted_at = "",
        comments = {},
      },
      {
        id = "PRR_2",
        author = { login = "reviewer" },
        state = "APPROVED",
        body = "LGTM",
        submitted_at = "2026-02-20T10:00:00Z",
        comments = {},
      },
    },
  })
  local result = comment_component.render(pr)

  -- Should show 1 review (PENDING filtered out)
  local found_section = false
  for _, line in ipairs(result.lines) do
    if line:match("Reviews %(1%)") then
      found_section = true
    end
  end
  eq(found_section, true)
end

T["render()"]["includes inline review comments"] = function()
  local pr = make_test_pr({
    reviews = {
      {
        id = "PRR_3001",
        author = { login = "reviewer" },
        state = "COMMENTED",
        body = "",
        submitted_at = "2026-02-20T10:00:00Z",
        comments = {
          {
            id = "PRRC_4001",
            author = { login = "reviewer" },
            body = "Nice refactor here.",
            path = "src/auth.lua",
            line = 42,
            created_at = "2026-02-20T10:00:00Z",
          },
        },
      },
    },
  })
  local result = comment_component.render(pr)

  local found_path = false
  local found_inline_body = false
  for _, line in ipairs(result.lines) do
    if line:match("src/auth%.lua:42") then
      found_path = true
    end
    if line:match("Nice refactor here") then
      found_inline_body = true
    end
  end
  eq(found_path, true)
  eq(found_inline_body, true)
end

T["render()"]["provides named ranges for navigation"] = function()
  local pr = make_test_pr()
  local result = comment_component.render(pr)

  -- Should have header range
  expect.equality(result.ranges["header"] ~= nil, true)
  expect.equality(result.ranges["header"].start >= 1, true)

  -- Should have comment ranges
  expect.equality(result.ranges["comment_IC_1001"] ~= nil, true)
  expect.equality(result.ranges["comment_IC_1002"] ~= nil, true)

  -- Should have review range
  expect.equality(result.ranges["review_PRR_3001"] ~= nil, true)
end

T["render()"]["handles no labels"] = function()
  local pr = make_test_pr({ labels = {} })
  local result = comment_component.render(pr)

  local found_labels = false
  for _, line in ipairs(result.lines) do
    if line:match("Labels:") then
      found_labels = true
    end
  end
  eq(found_labels, false)
end

T["render()"]["handles nil review_decision"] = function()
  local pr = make_test_pr()
  pr.review_decision = nil -- Can't set nil via overrides table
  local result = comment_component.render(pr)

  -- Metadata line (line 2) should not contain "Reviews:"
  -- (the section header "Reviews (1)" is separate and expected)
  local meta_line = result.lines[2]
  eq(meta_line:match("Reviews:") == nil, true)
end

T["render()"]["handles draft PR state"] = function()
  local pr = make_test_pr({ draft = true })
  local result = comment_component.render(pr)

  local found_draft = false
  for _, line in ipairs(result.lines) do
    if line:match("DRAFT") then
      found_draft = true
    end
  end
  eq(found_draft, true)
end

T["render()"]["includes checks section when checks_summary present"] = function()
  local pr = make_test_pr({
    checks_summary = {
      state = "success",
      total = 3,
      success = 3,
      failure = 0,
      pending = 0,
      checks = {
        {
          name = "CI / test",
          status = "completed",
          conclusion = "success",
          details_url = "https://example.com",
          app_name = "GitHub Actions",
          started_at = "2026-02-20T10:00:00Z",
          completed_at = "2026-02-20T10:02:30Z",
        },
      },
    },
  })
  local result = comment_component.render(pr)

  local found_checks = false
  local found_check_line = false
  for _, line in ipairs(result.lines) do
    if line:match("Checks") and line:match("3/3") then
      found_checks = true
    end
    if line:match("CI / test") then
      found_check_line = true
    end
  end
  eq(found_checks, true)
  eq(found_check_line, true)
end

T["render()"]["checks section absent when checks_summary is nil"] = function()
  local pr = make_test_pr()
  -- Default test PR has no checks_summary
  local result = comment_component.render(pr)

  local found_checks = false
  for _, line in ipairs(result.lines) do
    if line:match("Checks") then
      found_checks = true
    end
  end
  eq(found_checks, false)
end

T["render()"]["checks section absent when checks_summary has zero total"] = function()
  local pr = make_test_pr({
    checks_summary = {
      state = "success",
      total = 0,
      success = 0,
      failure = 0,
      pending = 0,
      checks = {},
    },
  })
  local result = comment_component.render(pr)

  local found_checks = false
  for _, line in ipairs(result.lines) do
    if line:match("Checks") then
      found_checks = true
    end
  end
  eq(found_checks, false)
end

T["render()"]["checks section collapsible via option"] = function()
  local pr = make_test_pr({
    checks_summary = {
      state = "success",
      total = 2,
      success = 2,
      failure = 0,
      pending = 0,
      checks = {
        {
          name = "CI / test",
          status = "completed",
          conclusion = "success",
          app_name = "GitHub Actions",
        },
        {
          name = "CI / lint",
          status = "completed",
          conclusion = "success",
          app_name = "GitHub Actions",
        },
      },
    },
  })

  -- Expanded (default)
  local result_expanded = comment_component.render(pr)
  local found_ci_test_expanded = false
  for _, line in ipairs(result_expanded.lines) do
    if line:match("CI / test") then
      found_ci_test_expanded = true
    end
  end
  eq(found_ci_test_expanded, true)

  -- Collapsed
  local result_collapsed = comment_component.render(pr, { checks_collapsed = true })
  local found_ci_test_collapsed = false
  local found_header_collapsed = false
  for _, line in ipairs(result_collapsed.lines) do
    if line:match("CI / test") then
      found_ci_test_collapsed = true
    end
    if line:match("Checks") and line:match(">") then
      found_header_collapsed = true
    end
  end
  eq(found_ci_test_collapsed, false)
  eq(found_header_collapsed, true)
end

return T
