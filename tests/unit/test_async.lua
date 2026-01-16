-- Tests for gitlad.state.async module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["AsyncHandler"] = MiniTest.new_set()

T["AsyncHandler"]["new creates handler"] = function()
  local async = require("gitlad.state.async")
  local results = {}

  local handler = async.new(function(result)
    table.insert(results, result)
  end)

  expect.equality(type(handler), "table")
  eq(handler.current_id, 0)
  eq(handler.last_applied_id, 0)
end

T["AsyncHandler"]["dispatch increments id"] = function()
  local async = require("gitlad.state.async")
  local handler = async.new(function() end)

  local id1 = handler:dispatch(function(done)
    done("a")
  end)
  local id2 = handler:dispatch(function(done)
    done("b")
  end)

  eq(id1, 1)
  eq(id2, 2)
end

T["AsyncHandler"]["only applies latest result"] = function()
  local async = require("gitlad.state.async")
  local results = {}

  local handler = async.new(function(result)
    table.insert(results, result)
  end)

  -- Simulate out-of-order completion
  local callbacks = {}

  handler:dispatch(function(done)
    callbacks[1] = done
  end)

  handler:dispatch(function(done)
    callbacks[2] = done
  end)

  -- Second completes first
  callbacks[2]("second")
  eq(#results, 1)
  eq(results[1], "second")

  -- First completes after - should be ignored
  callbacks[1]("first")
  eq(#results, 1) -- Still just one result
end

T["AsyncHandler"]["cancel ignores pending results"] = function()
  local async = require("gitlad.state.async")
  local results = {}

  local handler = async.new(function(result)
    table.insert(results, result)
  end)

  local callback = nil
  handler:dispatch(function(done)
    callback = done
  end)

  handler:cancel()
  callback("should be ignored")

  eq(#results, 0)
end

T["AsyncHandler"]["is_pending tracks state"] = function()
  local async = require("gitlad.state.async")
  local handler = async.new(function() end)

  eq(handler:is_pending(), false)

  local callback = nil
  handler:dispatch(function(done)
    callback = done
  end)

  eq(handler:is_pending(), true)

  callback("done")
  eq(handler:is_pending(), false)
end

T["debounce"] = MiniTest.new_set()

T["debounce"]["creates debounced function"] = function()
  local async = require("gitlad.state.async")

  local debounced = async.debounce(function() end, 100)
  expect.equality(type(debounced), "table")
  expect.equality(type(debounced.call), "function")
end

T["debounce"]["cancel stops pending call"] = function()
  local async = require("gitlad.state.async")
  local called = false

  local debounced = async.debounce(function()
    called = true
  end, 100)

  debounced:call()
  debounced:cancel()

  -- Wait a bit longer than delay
  vim.wait(150, function()
    return false
  end)

  eq(called, false)
end

T["throttle"] = MiniTest.new_set()

T["throttle"]["creates throttled function"] = function()
  local async = require("gitlad.state.async")

  local throttled = async.throttle(function() end, 100)
  expect.equality(type(throttled), "table")
  expect.equality(type(throttled.call), "function")
end

T["throttle"]["first call executes immediately"] = function()
  local async = require("gitlad.state.async")
  local call_count = 0

  local throttled = async.throttle(function()
    call_count = call_count + 1
  end, 100)

  throttled:call()
  eq(call_count, 1)
end

return T
