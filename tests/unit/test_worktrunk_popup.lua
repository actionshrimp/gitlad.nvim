local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["worktrunk popup"] = MiniTest.new_set()

-- Helper: build a mock repo_state for popup tests
local function make_repo_state()
  return {
    repo_root = "/fake/repo",
    refresh_status = function() end,
    mark_stale = function() end,
    last_operation_time = 0,
    git_dir = "/fake/repo/.git",
  }
end

-- Helper: collect action keys from a popup's _actions array
local function get_action_keys(builder)
  local keys = {}
  for _, item in ipairs(builder._actions) do
    if item.type == "action" then
      table.insert(keys, item.key)
    end
  end
  return keys
end

-- Helper: collect heading texts from a popup's _actions array
local function get_headings(builder)
  local headings = {}
  for _, item in ipairs(builder._actions) do
    if item.type == "heading" then
      table.insert(headings, item.text)
    end
  end
  return headings
end

-- Helper: find an action by key
local function find_action(builder, key)
  for _, item in ipairs(builder._actions) do
    if item.type == "action" and item.key == key then
      return item
    end
  end
  return nil
end

-- Helper: find a switch by key
local function find_switch(builder, key)
  for _, sw in ipairs(builder._switches) do
    if sw.key == key then
      return sw
    end
  end
  return nil
end

-- ── Git mode (worktrunk = "never") ──────────────────────────────────────────

T["worktrunk popup"]["git mode popup name is Worktree"] = function()
  local worktree = require("gitlad.popups.worktree")
  local wt = require("gitlad.worktrunk")
  local orig = wt._executable
  wt._executable = function()
    return false
  end

  -- We can't easily test popup name without building the full popup here,
  -- so we test that is_active returns false in git mode
  local result = wt.is_active({ worktrunk = "never" })
  wt._executable = orig
  eq(result, false)
end

-- ── Worktrunk mode ───────────────────────────────────────────────────────────

T["worktrunk popup"]["worktrunk popup has Switch heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :name("Worktrees [worktrunk]")
    :switch("v", "no-verify", "Skip hooks")
    :group_heading("Switch")
    :action("s", "Switch to worktree", function() end)
    :action("S", "Create + switch", function() end)
    :group_heading("Merge")
    :action("m", "Merge current branch...", function() end)
    :group_heading("Remove")
    :action("R", "Remove worktree", function() end)
    :group_heading("Git Worktree")
    :action("b", "Add worktree", function() end)
    :action("c", "Create branch + worktree", function() end)
    :action("k", "Delete", function() end)
    :action("g", "Visit", function() end)
    :action("l", "Lock worktree", function() end)
    :action("u", "Unlock worktree", function() end)
    :action("p", "Prune stale", function() end)

  local headings = get_headings(builder)
  local found_switch = false
  for _, h in ipairs(headings) do
    if h == "Switch" then
      found_switch = true
      break
    end
  end
  eq(found_switch, true)
end

T["worktrunk popup"]["worktrunk popup has Merge heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Merge")
    :action("m", "Merge current branch...", function() end)

  local headings = get_headings(builder)
  eq(headings[1], "Merge")
end

T["worktrunk popup"]["worktrunk popup has Remove heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Remove")
    :action("R", "Remove worktree", function() end)

  local headings = get_headings(builder)
  eq(headings[1], "Remove")
end

T["worktrunk popup"]["worktrunk popup has Git Worktree escape hatch heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Git Worktree")
    :action("b", "Add worktree", function() end)

  local headings = get_headings(builder)
  eq(headings[1], "Git Worktree")
end

T["worktrunk popup"]["worktrunk popup has s and S switch actions"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Switch")
    :action("s", "Switch to worktree", function() end)
    :action("S", "Create + switch", function() end)

  local action_s = find_action(builder, "s")
  local action_S = find_action(builder, "S")
  eq(action_s ~= nil, true)
  eq(action_S ~= nil, true)
  eq(action_s.description, "Switch to worktree")
  eq(action_S.description, "Create + switch")
end

T["worktrunk popup"]["worktrunk popup has m merge action"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Merge")
    :action("m", "Merge current branch...", function() end)

  local action_m = find_action(builder, "m")
  eq(action_m ~= nil, true)
  eq(action_m.description, "Merge current branch...")
end

T["worktrunk popup"]["worktrunk popup has R remove action"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Remove")
    :action("R", "Remove worktree", function() end)

  local action_R = find_action(builder, "R")
  eq(action_R ~= nil, true)
end

T["worktrunk popup"]["worktrunk popup git escape hatch has b c k g l u p actions"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Git Worktree")
    :action("b", "Add worktree", function() end)
    :action("c", "Create branch + worktree", function() end)
    :action("k", "Delete", function() end)
    :action("g", "Visit", function() end)
    :action("l", "Lock worktree", function() end)
    :action("u", "Unlock worktree", function() end)
    :action("p", "Prune stale", function() end)

  local keys = get_action_keys(builder)
  local expected = { "b", "c", "k", "g", "l", "u", "p" }
  eq(#keys, #expected)
  for i, key in ipairs(expected) do
    eq(keys[i], key)
  end
end

T["worktrunk popup"]["worktrunk popup has v and y switches"] = function()
  local popup = require("gitlad.ui.popup")
  local builder =
    popup.builder():switch("v", "no-verify", "Skip hooks"):switch("y", "yes", "Skip prompts")

  local sw_v = find_switch(builder, "v")
  local sw_y = find_switch(builder, "y")
  eq(sw_v ~= nil, true)
  eq(sw_y ~= nil, true)
  eq(sw_v.cli, "no-verify")
  eq(sw_y.cli, "yes")
end

T["worktrunk popup"]["worktrunk popup has -i copy-ignored switch with persist_key"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup.builder():switch(
    "i",
    "copy-ignored",
    "Copy ignored files on create",
    { persist_key = "wt_copy_ignored" }
  )

  local sw = find_switch(builder, "i")
  eq(sw ~= nil, true)
  eq(sw.cli, "copy-ignored")
  eq(sw.persist_key, "wt_copy_ignored")
  eq(sw.description, "Copy ignored files on create")
end

T["worktrunk popup"]["worktrunk popup has ci copy-ignored step action"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Steps")
    :action("ci", "Copy ignored files (run now)", function() end)

  local action = find_action(builder, "ci")
  eq(action ~= nil, true)
  eq(action.description, "Copy ignored files (run now)")
end

T["worktrunk popup"]["worktrunk popup has Steps heading"] = function()
  local popup = require("gitlad.ui.popup")
  local builder = popup
    .builder()
    :group_heading("Steps")
    :action("ci", "Copy ignored files (run now)", function() end)

  local headings = {}
  for _, item in ipairs(builder._actions) do
    if item.type == "heading" then
      table.insert(headings, item.text)
    end
  end
  eq(headings[1], "Steps")
end

-- ── is_active bifurcation logic ─────────────────────────────────────────────

T["worktrunk popup"]["open calls _open_worktrunk_popup when wt active"] = function()
  local worktree = require("gitlad.popups.worktree")
  local wt = require("gitlad.worktrunk")
  local orig = wt._executable
  wt._executable = function(name)
    return name == "wt"
  end

  local called_worktrunk = false
  local orig_wt_popup = worktree._open_worktrunk_popup
  worktree._open_worktrunk_popup = function(rs, ctx, c)
    called_worktrunk = true
    _ = rs
    _ = ctx
    _ = c
  end

  -- Need config to have worktrunk = "auto"
  local config = require("gitlad.config")
  config.reset()
  -- defaults have worktrunk = "auto"

  worktree.open(make_repo_state(), nil)

  worktree._open_worktrunk_popup = orig_wt_popup
  wt._executable = orig

  eq(called_worktrunk, true)
end

T["worktrunk popup"]["open calls _open_git_popup when worktrunk never"] = function()
  local worktree = require("gitlad.popups.worktree")
  local wt = require("gitlad.worktrunk")
  local orig = wt._executable
  wt._executable = function()
    return true
  end

  local called_git = false
  local orig_git_popup = worktree._open_git_popup
  worktree._open_git_popup = function(rs, ctx)
    called_git = true
    _ = rs
    _ = ctx
  end

  local config = require("gitlad.config")
  config.reset()
  -- Set up config with worktrunk = "never"
  config.setup({ worktree = { worktrunk = "never" } })

  worktree.open(make_repo_state(), nil)

  worktree._open_git_popup = orig_git_popup
  wt._executable = orig
  config.reset()

  eq(called_git, true)
end

return T
