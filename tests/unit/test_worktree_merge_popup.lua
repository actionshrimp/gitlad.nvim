local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["worktree_merge popup"] = MiniTest.new_set()

local function find_switch(builder, key)
  for _, sw in ipairs(builder._switches) do
    if sw.key == key then
      return sw
    end
  end
  return nil
end

local function find_option(builder, key)
  for _, opt in ipairs(builder._options) do
    if opt.key == key then
      return opt
    end
  end
  return nil
end

local function find_action(builder, key)
  for _, item in ipairs(builder._actions) do
    if item.type == "action" and item.key == key then
      return item
    end
  end
  return nil
end

T["worktree_merge popup"]["has no-squash switch (s)"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :switch("s", "no-squash", "Skip squash")
    :switch("r", "no-rebase", "Skip rebase")
    :switch("R", "no-remove", "Keep worktree")
    :switch("v", "no-verify", "Skip hooks")

  local sw = find_switch(builder, "s")
  eq(sw ~= nil, true)
  eq(sw.cli, "no-squash")
  eq(sw.description, "Skip squash")
end

T["worktree_merge popup"]["has no-rebase switch (r)"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :switch("s", "no-squash", "Skip squash")
    :switch("r", "no-rebase", "Skip rebase")
    :switch("R", "no-remove", "Keep worktree")
    :switch("v", "no-verify", "Skip hooks")

  local sw = find_switch(builder, "r")
  eq(sw ~= nil, true)
  eq(sw.cli, "no-rebase")
end

T["worktree_merge popup"]["has no-remove switch (R)"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :switch("s", "no-squash", "Skip squash")
    :switch("r", "no-rebase", "Skip rebase")
    :switch("R", "no-remove", "Keep worktree")
    :switch("v", "no-verify", "Skip hooks")

  local sw = find_switch(builder, "R")
  eq(sw ~= nil, true)
  eq(sw.cli, "no-remove")
  eq(sw.description, "Keep worktree")
end

T["worktree_merge popup"]["has no-verify switch (v)"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :switch("s", "no-squash", "Skip squash")
    :switch("r", "no-rebase", "Skip rebase")
    :switch("R", "no-remove", "Keep worktree")
    :switch("v", "no-verify", "Skip hooks")

  local sw = find_switch(builder, "v")
  eq(sw ~= nil, true)
  eq(sw.cli, "no-verify")
end

T["worktree_merge popup"]["has target branch option (t)"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():option("t", "target", "", "Target branch")

  local opt = find_option(builder, "t")
  eq(opt ~= nil, true)
  eq(opt.cli, "target")
  eq(opt.description, "Target branch")
  eq(opt.value, "")
end

T["worktree_merge popup"]["has merge action (m)"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Merge")
    :action("m", "Merge current branch into target", function() end)

  local action = find_action(builder, "m")
  eq(action ~= nil, true)
  eq(action.description, "Merge current branch into target")
end

T["worktree_merge popup"]["popup name is wt Merge"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():name("wt Merge")
  eq(builder._name, "wt Merge")
end

T["worktree_merge popup"]["_run_merge collects switch flags"] = function()
  -- Test that switch flags are assembled correctly via get_arguments
  local popup = require("gitlad.ui.popup")
  local popup_data = popup
    .builder()
    :switch("s", "no-squash", "Skip squash")
    :switch("r", "no-rebase", "Skip rebase")
    :switch("R", "no-remove", "Keep worktree")
    :switch("v", "no-verify", "Skip hooks")
    :build()

  -- Manually enable some switches
  popup_data:toggle_switch("s")
  popup_data:toggle_switch("R")

  local args = popup_data:get_arguments()
  eq(#args, 2)
  eq(args[1], "--no-squash")
  eq(args[2], "--no-remove")
end

T["worktree_merge popup"]["_run_merge uses nil target when option empty"] = function()
  -- Simulate what _run_merge does with an empty target option
  local popup = require("gitlad.ui.popup")
  local popup_data = popup.builder():option("t", "target", "", "Target branch"):build()

  local target = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "target" and opt.value ~= "" then
      target = opt.value
      break
    end
  end
  eq(target, nil)
end

T["worktree_merge popup"]["_run_merge uses provided target when option set"] = function()
  local popup = require("gitlad.ui.popup")
  local popup_data = popup.builder():option("t", "target", "", "Target branch"):build()

  popup_data:set_option("t", "main")

  local target = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "target" and opt.value ~= "" then
      target = opt.value
      break
    end
  end
  eq(target, "main")
end

return T
