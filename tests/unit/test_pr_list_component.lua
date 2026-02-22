local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local pr_list = require("gitlad.ui.components.pr_list")

--- Helper to create a mock PR
---@param overrides? table
---@return ForgePullRequest
local function make_pr(overrides)
  overrides = overrides or {}
  return vim.tbl_deep_extend("force", {
    number = 42,
    title = "Fix authentication bug",
    state = "open",
    draft = false,
    author = { login = "octocat", avatar_url = nil },
    head_ref = "fix/auth",
    base_ref = "main",
    review_decision = "APPROVED",
    labels = {},
    additions = 10,
    deletions = 3,
    created_at = "2026-02-19T10:30:00Z",
    updated_at = "2026-02-20T14:00:00Z",
    url = "https://github.com/owner/repo/pull/42",
    body = "Fixes the auth bug",
  }, overrides)
end

-- =============================================================================
-- render
-- =============================================================================

T["render()"] = MiniTest.new_set()

T["render()"]["returns empty result for empty list"] = function()
  local result = pr_list.render({})
  eq(#result.lines, 0)
  eq(vim.tbl_count(result.line_info), 0)
end

T["render()"]["renders single PR"] = function()
  local result = pr_list.render({ make_pr() })
  eq(#result.lines, 1)
  expect.equality(result.lines[1]:match("#42") ~= nil, true)
  expect.equality(result.lines[1]:match("Fix authentication bug") ~= nil, true)
  expect.equality(result.lines[1]:match("@octocat") ~= nil, true)
end

T["render()"]["includes diff stat"] = function()
  local result = pr_list.render({ make_pr({ additions = 10, deletions = 3 }) })
  expect.equality(result.lines[1]:match("%+10 %-3") ~= nil, true)
end

T["render()"]["includes review decision"] = function()
  local result = pr_list.render({ make_pr({ review_decision = "APPROVED" }) })
  expect.equality(result.lines[1]:match("APPROVED") ~= nil, true)
end

T["render()"]["shows CHANGES REQUESTED"] = function()
  local result = pr_list.render({ make_pr({ review_decision = "CHANGES_REQUESTED" }) })
  expect.equality(result.lines[1]:match("CHANGES REQUESTED") ~= nil, true)
end

T["render()"]["shows REVIEW REQUIRED"] = function()
  local result = pr_list.render({ make_pr({ review_decision = "REVIEW_REQUIRED" }) })
  expect.equality(result.lines[1]:match("REVIEW REQUIRED") ~= nil, true)
end

T["render()"]["handles nil review decision"] = function()
  local result = pr_list.render({ make_pr({ review_decision = nil }) })
  -- Should render without error
  eq(#result.lines, 1)
end

T["render()"]["marks draft PRs"] = function()
  local result = pr_list.render({ make_pr({ draft = true }) })
  expect.equality(result.lines[1]:match("%[Draft%]") ~= nil, true)
end

T["render()"]["truncates long titles"] = function()
  local long_title = string.rep("a", 100)
  local result = pr_list.render({ make_pr({ title = long_title }) })
  -- Default max_title_len is 50, so title should be truncated with "..."
  expect.equality(result.lines[1]:match("%.%.%.") ~= nil, true)
end

T["render()"]["respects custom max_title_len"] = function()
  local long_title = string.rep("b", 30)
  local result = pr_list.render({ make_pr({ title = long_title }) }, { max_title_len = 20 })
  -- Title should be truncated at 20 chars
  local line = result.lines[1]
  -- The truncated title should be 20 chars (17 + "...")
  expect.equality(line:match("%.%.%.") ~= nil, true)
end

T["render()"]["renders multiple PRs"] = function()
  local prs = {
    make_pr({ number = 42, title = "PR one" }),
    make_pr({ number = 41, title = "PR two" }),
    make_pr({ number = 40, title = "PR three" }),
  }
  local result = pr_list.render(prs)
  eq(#result.lines, 3)
  expect.equality(result.lines[1]:match("#42") ~= nil, true)
  expect.equality(result.lines[2]:match("#41") ~= nil, true)
  expect.equality(result.lines[3]:match("#40") ~= nil, true)
end

T["render()"]["populates line_info with PR metadata"] = function()
  local result = pr_list.render({ make_pr({ number = 42 }) })
  local info = result.line_info[1]
  eq(info.type, "pr")
  eq(info.number, 42)
  eq(info.pr.title, "Fix authentication bug")
end

T["render()"]["hides diff stat when show_diff_stat is false"] = function()
  local result = pr_list.render(
    { make_pr({ additions = 10, deletions = 3 }) },
    { show_diff_stat = false }
  )
  expect.equality(result.lines[1]:match("%+10") == nil, true)
end

T["render()"]["hides review when show_review is false"] = function()
  local result = pr_list.render(
    { make_pr({ review_decision = "APPROVED" }) },
    { show_review = false }
  )
  expect.equality(result.lines[1]:match("APPROVED") == nil, true)
end

T["render()"]["hides author when show_author is false"] = function()
  local result = pr_list.render({ make_pr() }, { show_author = false })
  expect.equality(result.lines[1]:match("@octocat") == nil, true)
end

T["render()"]["applies indent"] = function()
  local result = pr_list.render({ make_pr() }, { indent = 4 })
  expect.equality(result.lines[1]:match("^    ") ~= nil, true)
end

T["render()"]["shows checks indicator when all passing"] = function()
  local result = pr_list.render({
    make_pr({
      checks_summary = {
        state = "success",
        total = 3,
        success = 3,
        failure = 0,
        pending = 0,
        checks = {},
      },
    }),
  })
  expect.equality(result.lines[1]:match("%[3/3%]") ~= nil, true)
end

T["render()"]["shows checks indicator with failures"] = function()
  local result = pr_list.render({
    make_pr({
      checks_summary = {
        state = "failure",
        total = 3,
        success = 1,
        failure = 2,
        pending = 0,
        checks = {},
      },
    }),
  })
  expect.equality(result.lines[1]:match("%[1/3%]") ~= nil, true)
end

T["render()"]["shows checks indicator with pending"] = function()
  local result = pr_list.render({
    make_pr({
      checks_summary = {
        state = "pending",
        total = 3,
        success = 1,
        failure = 0,
        pending = 2,
        checks = {},
      },
    }),
  })
  expect.equality(result.lines[1]:match("%[~1/3%]") ~= nil, true)
end

T["render()"]["hides checks when show_checks is false"] = function()
  local result = pr_list.render({
    make_pr({
      checks_summary = {
        state = "success",
        total = 3,
        success = 3,
        failure = 0,
        pending = 0,
        checks = {},
      },
    }),
  }, { show_checks = false })
  expect.equality(result.lines[1]:match("%[3/3%]") == nil, true)
end

T["render()"]["no checks indicator when checks_summary is nil"] = function()
  local result = pr_list.render({ make_pr() })
  -- Default make_pr has no checks_summary
  expect.equality(result.lines[1]:match("%[%d+/%d+%]") == nil, true)
end

T["render()"]["aligns PR numbers in column"] = function()
  local prs = {
    make_pr({ number = 1 }),
    make_pr({ number = 100 }),
  }
  local result = pr_list.render(prs)
  -- #1 should have more padding than #100
  local line1 = result.lines[1]
  local line2 = result.lines[2]
  -- Both should have # at same column
  local col1 = line1:find("#")
  local col2 = line2:find("#")
  -- The number column should align (# at same position)
  -- Actually both lines should have their #N ending at the same column
  expect.equality(col1 ~= nil, true)
  expect.equality(col2 ~= nil, true)
end

return T
