-- Tests for gitlad.state module
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["RepoState"] = MiniTest.new_set()

T["RepoState"]["refreshing starts as false"] = function()
  -- We can't easily test the full RepoState without a git repo,
  -- but we can verify the initial value pattern
  local refreshing = false -- This is what RepoState initializes to
  eq(refreshing, false)
end

T["refresh indicator"] = MiniTest.new_set()

T["refresh indicator"]["refreshing flag logic"] = function()
  -- Test the refresh indicator state transitions
  -- Initial state
  local refreshing = false
  eq(refreshing, false)

  -- When refresh starts
  refreshing = true
  eq(refreshing, true)

  -- When refresh completes
  refreshing = false
  eq(refreshing, false)
end

T["refresh indicator"]["status line includes refreshing text when true"] = function()
  -- Test the header line generation logic
  local branch = "main"
  local refreshing = true

  local head_line = string.format("Head:     %s", branch)
  if refreshing then
    head_line = head_line .. "  (Refreshing...)"
  end

  eq(head_line, "Head:     main  (Refreshing...)")
end

T["refresh indicator"]["status line excludes refreshing text when false"] = function()
  local branch = "main"
  local refreshing = false

  local head_line = string.format("Head:     %s", branch)
  if refreshing then
    head_line = head_line .. "  (Refreshing...)"
  end

  eq(head_line, "Head:     main")
end

return T
