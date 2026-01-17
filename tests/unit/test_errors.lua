-- Tests for gitlad.utils.errors module
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["errors"] = MiniTest.new_set()

T["errors"]["result_to_callback returns success for code 0"] = function()
  local errors = require("gitlad.utils.errors")

  local result = { code = 0, stderr = {} }
  local success, err = errors.result_to_callback(result)

  eq(success, true)
  eq(err, nil)
end

T["errors"]["result_to_callback returns failure with error for non-zero code"] = function()
  local errors = require("gitlad.utils.errors")

  local result = { code = 1, stderr = { "error line 1", "error line 2" } }
  local success, err = errors.result_to_callback(result)

  eq(success, false)
  eq(err, "error line 1\nerror line 2")
end

T["errors"]["result_to_callback handles empty stderr on failure"] = function()
  local errors = require("gitlad.utils.errors")

  local result = { code = 128, stderr = {} }
  local success, err = errors.result_to_callback(result)

  eq(success, false)
  eq(err, "")
end

T["errors"]["result_to_callback ignores stderr on success"] = function()
  local errors = require("gitlad.utils.errors")

  -- Some git commands write to stderr even on success (e.g., warnings)
  local result = { code = 0, stderr = { "warning: something" } }
  local success, err = errors.result_to_callback(result)

  eq(success, true)
  eq(err, nil)
end

return T
