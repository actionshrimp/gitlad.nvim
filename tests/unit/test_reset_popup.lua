local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Reset popup builder tests
T["reset popup"] = MiniTest.new_set()

T["reset popup"]["creates popup with correct action structure"] = function()
  local popup = require("gitlad.ui.popup")

  local mixed_called = false
  local soft_called = false
  local hard_called = false
  local keep_called = false
  local index_called = false
  local worktree_called = false

  -- Build a popup structure matching reset.lua (without context)
  local data = popup
    .builder()
    :name("Reset")
    :group_heading("Reset this")
    :action("m", "mixed    (HEAD and index)", function()
      mixed_called = true
    end)
    :action("s", "soft     (HEAD only)", function()
      soft_called = true
    end)
    :action("h", "hard     (HEAD, index and worktree)", function()
      hard_called = true
    end)
    :action("k", "keep     (HEAD and index, keeping uncommitted)", function()
      keep_called = true
    end)
    :action("i", "index    (only)", function()
      index_called = true
    end)
    :action("w", "worktree (only)", function()
      worktree_called = true
    end)
    :build()

  eq(data.name, "Reset")
  -- 1 heading + 6 actions
  eq(#data.actions, 7)

  -- Heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Reset this")

  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "m")
  eq(data.actions[2].description:match("mixed"), "mixed")

  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "s")
  eq(data.actions[3].description:match("soft"), "soft")

  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "h")
  eq(data.actions[4].description:match("hard"), "hard")

  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "k")
  eq(data.actions[5].description:match("keep"), "keep")

  eq(data.actions[6].type, "action")
  eq(data.actions[6].key, "i")
  eq(data.actions[6].description:match("index"), "index")

  eq(data.actions[7].type, "action")
  eq(data.actions[7].key, "w")
  eq(data.actions[7].description:match("worktree"), "worktree")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(mixed_called, true)

  data.actions[3].callback(data)
  eq(soft_called, true)

  data.actions[4].callback(data)
  eq(hard_called, true)

  data.actions[5].callback(data)
  eq(keep_called, true)

  data.actions[6].callback(data)
  eq(index_called, true)

  data.actions[7].callback(data)
  eq(worktree_called, true)
end

T["reset popup"]["has no switches (actions only)"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Reset")
    :group_heading("Reset this")
    :action("m", "mixed    (HEAD and index)", function() end)
    :action("s", "soft     (HEAD only)", function() end)
    :action("h", "hard     (HEAD, index and worktree)", function() end)
    :build()

  eq(#data.switches, 0)
  eq(#data.options, 0)
end

T["reset popup"]["get_arguments returns empty (no switches)"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():name("Reset"):action("m", "mixed", function() end):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

return T
