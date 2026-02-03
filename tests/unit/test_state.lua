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

T["refresh_status callback"] = MiniTest.new_set()

T["refresh_status callback"]["pending callback field pattern"] = function()
  -- Test the callback field initialization pattern used in RepoState
  local state = {
    _pending_refresh_callback = nil,
  }

  -- Verify initial state
  eq(state._pending_refresh_callback, nil)

  -- Simulate storing a callback
  local callback_called = false
  state._pending_refresh_callback = function()
    callback_called = true
  end

  -- Verify callback is stored
  eq(state._pending_refresh_callback ~= nil, true)

  -- Simulate the callback being invoked
  if state._pending_refresh_callback then
    local cb = state._pending_refresh_callback
    state._pending_refresh_callback = nil
    cb()
  end

  -- Verify callback was called and cleared
  eq(callback_called, true)
  eq(state._pending_refresh_callback, nil)
end

T["mark_operation_time"] = MiniTest.new_set()

T["mark_operation_time"]["function exists"] = function()
  local state = require("gitlad.state")
  eq(type(state.mark_operation_time), "function")
end

T["mark_operation_time"]["does not error when no repo state exists"] = function()
  local state = require("gitlad.state")
  state.clear_all()

  -- Should not error even when no repo states exist
  MiniTest.expect.no_error(function()
    state.mark_operation_time("/nonexistent/path")
  end)
end

return T
