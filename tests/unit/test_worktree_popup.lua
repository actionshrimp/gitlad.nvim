-- Tests for gitlad.popups.worktree popup structure
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- Helper to find a switch by its key
local function find_switch(popup, key)
  for _, sw in ipairs(popup.switches) do
    if sw.key == key then
      return sw
    end
  end
  return nil
end

-- Helper to find an action by its key
local function find_action(popup, key)
  for _, item in ipairs(popup.actions) do
    if item.type == "action" and item.key == key then
      return item
    end
  end
  return nil
end

T["worktree popup"] = MiniTest.new_set()

T["worktree popup"]["builds with correct structure"] = function()
  local popup_module = require("gitlad.ui.popup")

  -- Build a worktree popup similar to the one in the module
  local worktree_popup = popup_module
    .builder()
    :name("Worktree")
    :switch("f", "force", "Force operations")
    :switch("d", "detach", "Detach HEAD")
    :switch("l", "lock", "Lock after adding")
    :group_heading("Create new")
    :action("b", "worktree", function() end)
    :action("c", "branch and worktree", function() end)
    :group_heading("Commands")
    :action("m", "Move worktree", function() end)
    :action("k", "Delete worktree", function() end)
    :action("g", "Visit worktree", function() end)
    :group_heading("Lock")
    :action("l", "Lock worktree", function() end)
    :action("u", "Unlock worktree", function() end)
    :group_heading("Maintenance")
    :action("p", "Prune stale", function() end)
    :build()

  eq(worktree_popup.name, "Worktree")
  eq(#worktree_popup.switches, 3)
end

T["worktree popup"]["has correct switches"] = function()
  local popup_module = require("gitlad.ui.popup")

  local worktree_popup = popup_module
    .builder()
    :name("Worktree")
    :switch("f", "force", "Force operations")
    :switch("d", "detach", "Detach HEAD")
    :switch("l", "lock", "Lock after adding")
    :action("b", "test", function() end)
    :build()

  local force_switch = find_switch(worktree_popup, "f")
  expect.equality(force_switch ~= nil, true)
  eq(force_switch.cli, "force")
  eq(force_switch.description, "Force operations")

  local detach_switch = find_switch(worktree_popup, "d")
  expect.equality(detach_switch ~= nil, true)
  eq(detach_switch.cli, "detach")

  local lock_switch = find_switch(worktree_popup, "l")
  expect.equality(lock_switch ~= nil, true)
  eq(lock_switch.cli, "lock")
end

T["worktree popup"]["has correct actions"] = function()
  local popup_module = require("gitlad.ui.popup")

  local worktree_popup = popup_module
    .builder()
    :name("Worktree")
    :action("b", "worktree", function() end)
    :action("c", "branch and worktree", function() end)
    :action("m", "Move worktree", function() end)
    :action("k", "Delete worktree", function() end)
    :action("g", "Visit worktree", function() end)
    :action("p", "Prune stale", function() end)
    :build()

  -- Check actions exist
  local add_action = find_action(worktree_popup, "b")
  expect.equality(add_action ~= nil, true)
  eq(add_action.description, "worktree")

  local branch_action = find_action(worktree_popup, "c")
  expect.equality(branch_action ~= nil, true)
  eq(branch_action.description, "branch and worktree")

  local move_action = find_action(worktree_popup, "m")
  expect.equality(move_action ~= nil, true)
  eq(move_action.description, "Move worktree")

  local delete_action = find_action(worktree_popup, "k")
  expect.equality(delete_action ~= nil, true)
  eq(delete_action.description, "Delete worktree")

  local visit_action = find_action(worktree_popup, "g")
  expect.equality(visit_action ~= nil, true)
  eq(visit_action.description, "Visit worktree")

  local prune_action = find_action(worktree_popup, "p")
  expect.equality(prune_action ~= nil, true)
  eq(prune_action.description, "Prune stale")
end

T["worktree popup"]["get_arguments returns enabled switch flags"] = function()
  local popup_module = require("gitlad.ui.popup")

  local worktree_popup = popup_module
    .builder()
    :name("Worktree")
    :switch("f", "force", "Force operations")
    :switch("d", "detach", "Detach HEAD")
    :switch("l", "lock", "Lock after adding")
    :action("b", "test", function() end)
    :build()

  -- Enable force and lock switches
  worktree_popup.switches[1].enabled = true -- force
  worktree_popup.switches[3].enabled = true -- lock

  local args = worktree_popup:get_arguments()

  -- Should contain --force and --lock
  local has_force = vim.tbl_contains(args, "--force")
  local has_lock = vim.tbl_contains(args, "--lock")
  local has_detach = vim.tbl_contains(args, "--detach")

  expect.equality(has_force, true)
  expect.equality(has_lock, true)
  expect.equality(has_detach, false)
end

T["worktree popup"]["has correct group headings"] = function()
  local popup_module = require("gitlad.ui.popup")

  local worktree_popup = popup_module
    .builder()
    :name("Worktree")
    :group_heading("Create new")
    :action("b", "worktree", function() end)
    :group_heading("Commands")
    :action("k", "Delete", function() end)
    :group_heading("Lock")
    :action("l", "Lock", function() end)
    :group_heading("Maintenance")
    :action("p", "Prune", function() end)
    :build()

  -- Count group headings
  local headings = 0
  for _, item in ipairs(worktree_popup.actions) do
    if item.type == "heading" then
      headings = headings + 1
    end
  end

  eq(headings, 4)
end

return T
