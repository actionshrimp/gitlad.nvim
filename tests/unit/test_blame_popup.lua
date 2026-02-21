local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["blame popup"] = MiniTest.new_set()

T["blame popup"]["builds with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  local blame_popup = popup
    .builder()
    :name("Blame")
    :switch("w", "w", "Ignore whitespace", { cli_prefix = "-" })
    :switch("M", "M", "Detect moved lines", { cli_prefix = "-" })
    :switch("C", "C", "Detect copied lines", { cli_prefix = "-" })
    :action("b", "Blame current file", function() end)
    :build()

  eq(#blame_popup.switches, 3)
  eq(blame_popup.switches[1].cli, "w")
  eq(blame_popup.switches[1].cli_prefix, "-")
  eq(blame_popup.switches[2].cli, "M")
  eq(blame_popup.switches[3].cli, "C")
end

T["blame popup"]["get_arguments returns enabled switch flags"] = function()
  local popup = require("gitlad.ui.popup")

  local blame_popup = popup
    .builder()
    :name("Blame")
    :switch("w", "w", "Ignore whitespace", { cli_prefix = "-" })
    :switch("M", "M", "Detect moved lines", { cli_prefix = "-" })
    :switch("C", "C", "Detect copied lines", { cli_prefix = "-" })
    :action("b", "Blame", function() end)
    :build()

  -- No switches enabled by default
  local args = blame_popup:get_arguments()
  eq(#args, 0)

  -- Enable -w switch
  blame_popup.switches[1].enabled = true
  args = blame_popup:get_arguments()
  eq(#args, 1)
  eq(args[1], "-w")

  -- Enable all switches
  blame_popup.switches[2].enabled = true
  blame_popup.switches[3].enabled = true
  args = blame_popup:get_arguments()
  eq(#args, 3)
  eq(args[1], "-w")
  eq(args[2], "-M")
  eq(args[3], "-C")
end

T["blame popup"]["has correct action count"] = function()
  local popup = require("gitlad.ui.popup")

  local blame_popup = popup
    .builder()
    :name("Blame")
    :switch("w", "w", "Ignore whitespace", { cli_prefix = "-" })
    :group_heading("Blame")
    :action("b", "Blame current file", function() end)
    :action("r", "Blame at revision", function() end)
    :build()

  -- Actions include headings
  local action_count = 0
  for _, action in ipairs(blame_popup.actions) do
    if action.type == "action" then
      action_count = action_count + 1
    end
  end
  eq(action_count, 2)
end

return T
