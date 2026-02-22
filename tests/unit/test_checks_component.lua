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

  -- The failing check should have ✗
  expect.equality(result.lines[3]:match("✗") ~= nil, true)
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

  -- The pending check should have ○
  expect.equality(result.lines[3]:match("○") ~= nil, true)
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

return T
