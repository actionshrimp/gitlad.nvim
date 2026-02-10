-- Unit tests for log view utility functions
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- =============================================================================
-- _parse_limit tests
-- =============================================================================

T["_parse_limit"] = MiniTest.new_set()

T["_parse_limit"]["finds -256 in args"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({ "-256" }), 256)
end

T["_parse_limit"]["finds -100 among other args"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({ "--all", "-100", "--author=foo" }), 100)
end

T["_parse_limit"]["returns nil when no limit arg"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({ "--all", "--merges" }), nil)
end

T["_parse_limit"]["returns nil for empty args"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({}), nil)
end

T["_parse_limit"]["does not match --all"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({ "--all" }), nil)
end

T["_parse_limit"]["does not match --author=foo"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({ "--author=foo" }), nil)
end

T["_parse_limit"]["handles limit of 1"] = function()
  local log_view = require("gitlad.ui.views.log")
  eq(log_view._parse_limit({ "-1" }), 1)
end

-- =============================================================================
-- _update_limit tests
-- =============================================================================

T["_update_limit"] = MiniTest.new_set()

T["_update_limit"]["replaces existing limit"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "-256" }, 512)
  eq(result, { "-512" })
end

T["_update_limit"]["replaces limit among other args"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "--all", "-100", "--author=foo" }, 200)
  eq(result, { "--all", "-200", "--author=foo" })
end

T["_update_limit"]["adds limit when none exists"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "--all" }, 256)
  eq(result, { "--all", "-256" })
end

T["_update_limit"]["adds limit to empty args"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({}, 256)
  eq(result, { "-256" })
end

T["_update_limit"]["removes limit when nil passed"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "--all", "-256" }, nil)
  eq(result, { "--all" })
end

T["_update_limit"]["removes limit from single-arg list"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "-256" }, nil)
  eq(result, {})
end

T["_update_limit"]["handles limit of 1"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "-256" }, 1)
  eq(result, { "-1" })
end

T["_update_limit"]["preserves non-limit args when removing"] = function()
  local log_view = require("gitlad.ui.views.log")
  local result = log_view._update_limit({ "--all", "-100", "--merges" }, nil)
  eq(result, { "--all", "--merges" })
end

return T
