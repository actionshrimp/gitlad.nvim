local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Submodule popup builder tests
T["submodule popup"] = MiniTest.new_set()

T["submodule popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as submodule.lua
  local data = popup
    .builder()
    :name("Submodule")
    :switch("f", "force", "Force")
    :switch("r", "recursive", "Recursive")
    :switch("N", "no-fetch", "Don't fetch (for update)")
    :switch("C", "checkout", "Checkout")
    :switch("R", "rebase", "Rebase onto")
    :switch("M", "merge", "Merge")
    :build()

  eq(data.name, "Submodule")
  eq(#data.switches, 6)
  eq(data.switches[1].key, "f")
  eq(data.switches[1].cli, "force")
  eq(data.switches[2].key, "r")
  eq(data.switches[2].cli, "recursive")
  eq(data.switches[3].key, "N")
  eq(data.switches[3].cli, "no-fetch")
  eq(data.switches[4].key, "C")
  eq(data.switches[4].cli, "checkout")
end

T["submodule popup"]["get_arguments returns enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("f", "force", "Force", { enabled = true })
    :switch("r", "recursive", "Recursive", { enabled = true })
    :switch("N", "no-fetch", "Don't fetch")
    :build()

  local args = data:get_arguments()
  eq(#args, 2)
  eq(args[1], "--force")
  eq(args[2], "--recursive")
end

T["submodule popup"]["creates actions with correct structure"] = function()
  local popup = require("gitlad.ui.popup")

  local add_called = false
  local init_called = false
  local populate_called = false
  local update_called = false
  local sync_called = false
  local deinit_called = false
  local remove_called = false

  local data = popup
    .builder()
    :name("Submodule")
    :group_heading("One module")
    :action("a", "Add", function()
      add_called = true
    end)
    :action("r", "Register (init)", function()
      init_called = true
    end)
    :action("p", "Populate (update --init)", function()
      populate_called = true
    end)
    :action("u", "Update", function()
      update_called = true
    end)
    :action("s", "Synchronize", function()
      sync_called = true
    end)
    :action("d", "Unpopulate (deinit)", function()
      deinit_called = true
    end)
    :action("k", "Remove", function()
      remove_called = true
    end)
    :group_heading("All modules")
    :action("l", "List", function() end)
    :action("F", "Fetch all", function() end)
    :build()

  -- 2 headings + 9 actions
  eq(#data.actions, 11)
  -- First heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "One module")
  -- Add action
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "a")
  eq(data.actions[2].description, "Add")
  -- Update action
  eq(data.actions[5].key, "u")
  eq(data.actions[5].description, "Update")
  -- Second heading
  eq(data.actions[9].type, "heading")
  eq(data.actions[9].text, "All modules")
end

T["submodule popup"]["get_arguments with mutually exclusive switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Only checkout is enabled
  local data = popup
    .builder()
    :switch("C", "checkout", "Checkout", { enabled = true })
    :switch("R", "rebase", "Rebase onto")
    :switch("M", "merge", "Merge")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--checkout")
end

return T
