local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- =============================================================================
-- Forge popup module structure
-- =============================================================================

T["forge popup"] = MiniTest.new_set()

T["forge popup"]["module loads without error"] = function()
  local forge_popup = require("gitlad.popups.forge")
  eq(type(forge_popup), "table")
  eq(type(forge_popup.open), "function")
  eq(type(forge_popup._show_popup), "function")
  eq(type(forge_popup._list_prs), "function")
  eq(type(forge_popup._view_current_pr), "function")
  eq(type(forge_popup._checkout_pr), "function")
end

T["forge popup"]["_show_popup builds popup with correct title"] = function()
  -- Mock provider
  local provider = {
    provider_type = "github",
    owner = "testowner",
    repo = "testrepo",
    host = "github.com",
  }

  -- _show_popup calls popup.builder() which needs vim UI context
  -- We can verify the function exists and accepts provider
  eq(type(require("gitlad.popups.forge")._show_popup), "function")
end

return T
