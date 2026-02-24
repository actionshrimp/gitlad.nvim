local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local checks_component = require("gitlad.ui.components.checks")

--- Helper to create a mock check
---@param overrides? table
---@return ForgeCheck
local function make_check(overrides)
  overrides = overrides or {}
  return vim.tbl_deep_extend("force", {
    name = "CI / test",
    status = "completed",
    conclusion = "success",
    details_url = "https://github.com/owner/repo/actions/runs/1001",
    app_name = "GitHub Actions",
    started_at = "2026-02-20T10:00:00Z",
    completed_at = "2026-02-20T10:02:30Z",
  }, overrides)
end

--- Helper to create a mock checks summary
---@param overrides? table
---@return ForgeChecksSummary
local function make_summary(overrides)
  overrides = overrides or {}
  local default = {
    state = "success",
    total = 3,
    success = 3,
    failure = 0,
    pending = 0,
    checks = {
      make_check({ name = "CI / test" }),
      make_check({ name = "CI / lint", completed_at = "2026-02-20T10:01:00Z" }),
      make_check({ name = "deploy-preview", conclusion = "success", app_name = "Vercel" }),
    },
  }
  for k, v in pairs(overrides) do
    default[k] = v
  end
  return default
end

-- =============================================================================
-- render
-- =============================================================================

T["render()"] = MiniTest.new_set()

T["render()"]["includes section header with counts"] = function()
  local result = checks_component.render(make_summary())
  expect.equality(result.lines[1]:match("Checks") ~= nil, true)
  expect.equality(result.lines[1]:match("3/3") ~= nil, true)
end

T["render()"]["renders individual check lines"] = function()
  local result = checks_component.render(make_summary())
  -- Header + 3 checks = 4 lines
  eq(#result.lines, 4)

  -- Each check line should have the check name
  expect.equality(result.lines[2]:match("CI / test") ~= nil, true)
  expect.equality(result.lines[3]:match("CI / lint") ~= nil, true)
  expect.equality(result.lines[4]:match("deploy%-preview") ~= nil, true)
end

T["render()"]["shows success icon for passing checks"] = function()
  local result = checks_component.render(make_summary())
  expect.equality(result.lines[2]:match("✓") ~= nil, true)
end

T["render()"]["shows failure icon for failing checks"] = function()
  local summary = make_summary({
    state = "failure",
    success = 2,
    failure = 1,
    checks = {
      make_check({ name = "CI / test" }),
      make_check({ name = "CI / lint", conclusion = "failure" }),
      make_check({ name = "deploy" }),
    },
  })
  local result = checks_component.render(summary)

  -- The failing check should have ✗ (find the line with CI / lint)
  local found = false
  for _, line in ipairs(result.lines) do
    if line:match("CI / lint") and line:match("✗") then
      found = true
    end
  end
  eq(found, true)
end

T["render()"]["shows pending icon for in-progress checks"] = function()
  local summary = make_summary({
    state = "pending",
    success = 1,
    pending = 1,
    total = 2,
    checks = {
      make_check({ name = "CI / test" }),
      make_check({ name = "CI / lint", status = "in_progress", conclusion = nil }),
    },
  })
  local result = checks_component.render(summary)

  -- The in-progress check should have ○ (find the line with CI / lint)
  local found = false
  for _, line in ipairs(result.lines) do
    if line:match("CI / lint") and line:match("○") then
      found = true
    end
  end
  eq(found, true)
end

T["render()"]["shows app name in parentheses"] = function()
  local result = checks_component.render(make_summary())
  expect.equality(result.lines[2]:match("%(GitHub Actions%)") ~= nil, true)
  expect.equality(result.lines[4]:match("%(Vercel%)") ~= nil, true)
end

T["render()"]["shows duration when timestamps available"] = function()
  local result = checks_component.render(make_summary())
  -- CI / test: 2m 30s (10:00:00 to 10:02:30)
  expect.equality(result.lines[2]:match("2m 30s") ~= nil, true)
  -- CI / lint: 1m (10:00:00 to 10:01:00)
  expect.equality(result.lines[3]:match("1m") ~= nil, true)
end

T["render()"]["sets line_info types correctly"] = function()
  local result = checks_component.render(make_summary())

  -- First line is header
  eq(result.line_info[1].type, "checks_header")

  -- Remaining lines are check lines
  eq(result.line_info[2].type, "check")
  eq(result.line_info[2].check.name, "CI / test")
  eq(result.line_info[3].type, "check")
  eq(result.line_info[4].type, "check")
end

T["render()"]["collapsed mode shows only header"] = function()
  local result = checks_component.render(make_summary(), { collapsed = true })
  eq(#result.lines, 1)
  expect.equality(result.lines[1]:match("Checks") ~= nil, true)
  expect.equality(result.lines[1]:match(">") ~= nil, true)
end

T["render()"]["expanded mode shows v indicator"] = function()
  local result = checks_component.render(make_summary(), { collapsed = false })
  expect.equality(result.lines[1]:match("v") ~= nil, true)
end

T["render()"]["handles empty checks list"] = function()
  local summary = make_summary({ total = 0, success = 0, checks = {} })
  local result = checks_component.render(summary)
  -- Just the header
  eq(#result.lines, 1)
end

T["render()"]["provides named ranges"] = function()
  local result = checks_component.render(make_summary())
  expect.equality(result.ranges["checks_header"] ~= nil, true)
  expect.equality(result.ranges["checks"] ~= nil, true)
end

T["render()"]["omits app name when nil"] = function()
  local summary = make_summary({
    checks = {
      make_check({ name = "CI / test", app_name = nil }),
    },
    total = 1,
    success = 1,
  })
  local result = checks_component.render(summary)
  -- Should not have empty parentheses
  expect.equality(result.lines[2]:match("%(%)") == nil, true)
end

T["render()"]["omits duration when timestamps missing"] = function()
  -- Build check without timestamps directly (vim.tbl_deep_extend can't set nil)
  local check = {
    name = "CI / test",
    status = "completed",
    conclusion = "success",
    details_url = "https://example.com",
    app_name = "GitHub Actions",
  }
  local summary = make_summary({
    checks = { check },
    total = 1,
    success = 1,
  })
  local result = checks_component.render(summary)
  -- Should not have time suffix like "2m 30s"
  expect.equality(result.lines[2]:match("%d+[smh]") == nil, true)
end

-- =============================================================================
-- classify_check
-- =============================================================================

T["classify_check()"] = MiniTest.new_set()

T["classify_check()"]["classifies successful checks"] = function()
  eq(
    checks_component.classify_check(make_check({ status = "completed", conclusion = "success" })),
    "successful"
  )
end

T["classify_check()"]["classifies failed checks"] = function()
  eq(
    checks_component.classify_check(make_check({ status = "completed", conclusion = "failure" })),
    "failed"
  )
  eq(
    checks_component.classify_check(make_check({ status = "completed", conclusion = "timed_out" })),
    "failed"
  )
  eq(
    checks_component.classify_check(
      make_check({ status = "completed", conclusion = "startup_failure" })
    ),
    "failed"
  )
end

T["classify_check()"]["classifies in-progress checks"] = function()
  eq(
    checks_component.classify_check(make_check({ status = "in_progress", conclusion = nil })),
    "in_progress"
  )
end

T["classify_check()"]["classifies pending checks"] = function()
  eq(
    checks_component.classify_check(make_check({ status = "queued", conclusion = nil })),
    "pending"
  )
  eq(
    checks_component.classify_check(
      make_check({ status = "completed", conclusion = "action_required" })
    ),
    "pending"
  )
end

T["classify_check()"]["classifies skipped checks"] = function()
  eq(
    checks_component.classify_check(make_check({ status = "completed", conclusion = "cancelled" })),
    "skipped"
  )
  eq(
    checks_component.classify_check(make_check({ status = "completed", conclusion = "skipped" })),
    "skipped"
  )
  eq(
    checks_component.classify_check(make_check({ status = "completed", conclusion = "neutral" })),
    "skipped"
  )
end

-- =============================================================================
-- sub-sections
-- =============================================================================

T["sub-sections"] = MiniTest.new_set()

--- Helper: make N checks of a given category
---@param n number
---@param category_overrides table Fields to put on each check
---@return ForgeCheck[]
local function make_n_checks(n, category_overrides)
  local checks = {}
  for i = 1, n do
    local name = (category_overrides.name or "check") .. "-" .. i
    local c = make_check(vim.tbl_extend("force", category_overrides, { name = name }))
    table.insert(checks, c)
  end
  return checks
end

T["sub-sections"]["no sub-sections when category has <= 5 checks"] = function()
  -- 5 successful checks (at threshold, not above)
  local checks = make_n_checks(5, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 5, success = 5 })
  local result = checks_component.render(summary)

  -- No sub-section headers should appear
  for _, info in pairs(result.line_info) do
    expect.equality(info.type ~= "checks_sub_header", true)
  end

  -- All checks rendered flat (2-space indent)
  for i = 2, #result.lines do
    if result.line_info[i] and result.line_info[i].type == "check" then
      expect.equality(result.lines[i]:match("^  ") ~= nil, true)
    end
  end
end

T["sub-sections"]["sub-section header when category has > 5 checks"] = function()
  -- 6 successful checks (above threshold)
  local checks = make_n_checks(6, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 6, success = 6 })
  local result = checks_component.render(summary)

  -- Should have a sub-section header for "successful"
  local found_sub_header = false
  for _, info in pairs(result.line_info) do
    if info.type == "checks_sub_header" and info.sub_category == "successful" then
      found_sub_header = true
    end
  end
  eq(found_sub_header, true)

  -- Sub-section header should show category label and count
  local sub_header_line = nil
  for i, info in pairs(result.line_info) do
    if info.type == "checks_sub_header" then
      sub_header_line = result.lines[i]
    end
  end
  expect.equality(sub_header_line:match("Successful") ~= nil, true)
  expect.equality(sub_header_line:match("%(6%)") ~= nil, true)
end

T["sub-sections"]["sub-section checks have 4-space indent"] = function()
  local checks = make_n_checks(6, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 6, success = 6 })
  local result = checks_component.render(summary)

  for i, info in pairs(result.line_info) do
    if info.type == "check" then
      -- Should have 4-space indent (inside sub-section)
      expect.equality(result.lines[i]:match("^    ") ~= nil, true)
    end
  end
end

T["sub-sections"]["collapsed sub-section shows only header"] = function()
  local checks = make_n_checks(6, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 6, success = 6 })
  local result = checks_component.render(summary, { sub_collapsed = { successful = true } })

  -- Header + sub-section header only = 2 lines
  eq(#result.lines, 2)

  -- Sub-section header should have > indicator
  expect.equality(result.lines[2]:match(">") ~= nil, true)
end

T["sub-sections"]["expanded sub-section shows v indicator"] = function()
  local checks = make_n_checks(6, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 6, success = 6 })
  local result = checks_component.render(summary, { sub_collapsed = { successful = false } })

  -- Sub-section header should have v indicator
  expect.equality(result.lines[2]:match("v") ~= nil, true)
end

T["sub-sections"]["mixed categories with some grouped some flat"] = function()
  -- 2 failed (flat) + 7 successful (grouped)
  local failed = make_n_checks(2, { conclusion = "failure" })
  local successful = make_n_checks(7, { conclusion = "success" })
  local all_checks = {}
  for _, c in ipairs(failed) do
    table.insert(all_checks, c)
  end
  for _, c in ipairs(successful) do
    table.insert(all_checks, c)
  end
  local summary = make_summary({ checks = all_checks, total = 9, success = 7, failure = 2 })
  local result = checks_component.render(summary)

  -- Failed checks should be flat (2-space indent, no sub-header for failed)
  local failed_sub_header = false
  local successful_sub_header = false
  for _, info in pairs(result.line_info) do
    if info.type == "checks_sub_header" then
      if info.sub_category == "failed" then
        failed_sub_header = true
      end
      if info.sub_category == "successful" then
        successful_sub_header = true
      end
    end
  end
  eq(failed_sub_header, false)
  eq(successful_sub_header, true)

  -- Total lines: 1 header + 2 flat failed + 1 sub-header + 7 indented = 11
  eq(#result.lines, 11)
end

T["sub-sections"]["categories render in correct order (failed first)"] = function()
  -- Mix of failed, in_progress, successful
  local checks = {}
  -- 6 successful
  for _, c in ipairs(make_n_checks(6, { conclusion = "success" })) do
    table.insert(checks, c)
  end
  -- 6 failed
  for _, c in ipairs(make_n_checks(6, { conclusion = "failure" })) do
    table.insert(checks, c)
  end
  -- 2 in_progress
  for _, c in ipairs(make_n_checks(2, { status = "in_progress", conclusion = nil })) do
    table.insert(checks, c)
  end
  local summary =
    make_summary({ checks = checks, total = 14, success = 6, failure = 6, pending = 2 })
  local result = checks_component.render(summary)

  -- Collect sub-header categories in order
  local sub_header_order = {}
  -- Also track first check per category
  local first_check_category = nil
  for i = 2, #result.lines do
    local info = result.line_info[i]
    if info then
      if info.type == "checks_sub_header" then
        table.insert(sub_header_order, info.sub_category)
      elseif info.type == "check" and not first_check_category then
        -- First check line tells us which category rendered first
        first_check_category = checks_component.classify_check(info.check)
      end
    end
  end

  -- Failed should be first sub-header, successful second
  eq(sub_header_order[1], "failed")
  eq(sub_header_order[2], "successful")

  -- First check should be from failed category (since it renders first)
  eq(first_check_category, "failed")
end

T["sub-sections"]["checks_sub_header line_info has correct type and sub_category"] = function()
  local checks = make_n_checks(6, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 6, success = 6 })
  local result = checks_component.render(summary)

  for _, info in pairs(result.line_info) do
    if info.type == "checks_sub_header" then
      eq(info.sub_category, "successful")
      return
    end
  end
  -- Should have found one
  eq(true, false)
end

T["sub-sections"]["named ranges include sub-section ranges"] = function()
  local checks = make_n_checks(6, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 6, success = 6 })
  local result = checks_component.render(summary)

  expect.equality(result.ranges["checks_sub_successful"] ~= nil, true)
end

T["sub-sections"]["custom threshold via sub_threshold option"] = function()
  -- 4 checks with threshold of 3 → should get sub-section
  local checks = make_n_checks(4, { conclusion = "success" })
  local summary = make_summary({ checks = checks, total = 4, success = 4 })
  local result = checks_component.render(summary, { sub_threshold = 3 })

  local found_sub_header = false
  for _, info in pairs(result.line_info) do
    if info.type == "checks_sub_header" then
      found_sub_header = true
    end
  end
  eq(found_sub_header, true)
end

return T
