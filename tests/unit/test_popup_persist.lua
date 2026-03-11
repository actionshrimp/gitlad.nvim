local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- Isolate each test to a fresh temp file so they don't interfere with each other
-- or with the real user data directory.
local function tmp_path()
  return vim.fn.tempname() .. "_popup_persist_test.json"
end

local function make_persist(path)
  local p = require("gitlad.utils.persist")
  p._override_path = path
  p._reset_cache()
  return p
end

-- ──────────────────────────────────────────────────────────────
-- persist module
-- ──────────────────────────────────────────────────────────────

T["persist"] = MiniTest.new_set()

T["persist"]["get returns nil for unknown key"] = function()
  local p = make_persist(tmp_path())
  eq(p.get("no_such_key"), nil)
end

T["persist"]["set and get roundtrip boolean true"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("my_switch", true)
  p._reset_cache()
  eq(p.get("my_switch"), true)
end

T["persist"]["set and get roundtrip boolean false"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("my_switch", false)
  p._reset_cache()
  eq(p.get("my_switch"), false)
end

T["persist"]["multiple keys are independent"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("switch_a", true)
  p.set("switch_b", false)
  p._reset_cache()
  eq(p.get("switch_a"), true)
  eq(p.get("switch_b"), false)
end

T["persist"]["overwrite existing key"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("my_switch", true)
  p.set("my_switch", false)
  p._reset_cache()
  eq(p.get("my_switch"), false)
end

T["persist"]["survives cache reset (reads from disk)"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("key1", true)
  -- Reset cache to force disk read on next access
  p._reset_cache()
  eq(p.get("key1"), true)
end

-- ──────────────────────────────────────────────────────────────
-- PopupBuilder persist_key integration
-- ──────────────────────────────────────────────────────────────

T["popup persist_key"] = MiniTest.new_set()

T["popup persist_key"]["switch without persist_key defaults to enabled=false"] = function()
  local popup = require("gitlad.ui.popup")
  local data = popup.builder():switch("a", "all", "All files"):build()
  eq(data.switches[1].enabled, false)
  eq(data.switches[1].persist_key, nil)
end

T["popup persist_key"]["switch with persist_key loads false (no saved state)"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  -- No saved state yet
  eq(p.get("test_switch"), nil)

  local popup = require("gitlad.ui.popup")
  local data =
    popup.builder():switch("a", "all", "All files", { persist_key = "test_switch" }):build()
  -- No persisted value → falls back to opts.enabled default (false)
  eq(data.switches[1].enabled, false)
  eq(data.switches[1].persist_key, "test_switch")
end

T["popup persist_key"]["switch with persist_key loads saved true state"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("sticky_verbose", true)

  local popup = require("gitlad.ui.popup")
  local data =
    popup.builder():switch("v", "verbose", "Verbose", { persist_key = "sticky_verbose" }):build()
  eq(data.switches[1].enabled, true)
end

T["popup persist_key"]["switch with persist_key loads saved false state (overrides enabled=true default)"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("sticky_flag", false)

  local popup = require("gitlad.ui.popup")
  -- opts.enabled = true, but persisted value = false → persisted wins
  local data = popup
    .builder()
    :switch("f", "force", "Force", { enabled = true, persist_key = "sticky_flag" })
    :build()
  eq(data.switches[1].enabled, false)
end

T["popup persist_key"]["toggle_switch saves state when persist_key is set"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p._reset_cache()

  local popup = require("gitlad.ui.popup")
  local data =
    popup.builder():switch("a", "all", "All files", { persist_key = "save_test" }):build()

  eq(data.switches[1].enabled, false)
  data:toggle_switch("a")
  eq(data.switches[1].enabled, true)

  -- Value should have been saved to disk
  p._reset_cache()
  eq(p.get("save_test"), true)

  -- Toggle off
  data:toggle_switch("a")
  eq(data.switches[1].enabled, false)
  p._reset_cache()
  eq(p.get("save_test"), false)
end

T["popup persist_key"]["toggle_switch does NOT save when no persist_key"] = function()
  local path = tmp_path()
  local p = make_persist(path)

  local popup = require("gitlad.ui.popup")
  -- Use a key that won't collide with any persisted value
  local data = popup.builder():switch("n", "no-verify", "No verify"):build()

  data:toggle_switch("n")
  eq(data.switches[1].enabled, true)

  -- Nothing should have been written for this switch
  p._reset_cache()
  eq(p.get("no-verify"), nil)
end

T["popup persist_key"]["rebuilt popup picks up previously toggled state"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p._reset_cache()

  local popup = require("gitlad.ui.popup")

  -- First popup instance: toggle on
  local data1 = popup
    .builder()
    :switch("c", "copy-ignored", "Copy ignored files", { persist_key = "wt_copy_ignored" })
    :build()
  data1:toggle_switch("c")
  eq(data1.switches[1].enabled, true)

  -- Second popup instance (simulates reopening): should load saved state
  local data2 = popup
    .builder()
    :switch("c", "copy-ignored", "Copy ignored files", { persist_key = "wt_copy_ignored" })
    :build()
  eq(data2.switches[1].enabled, true)
end

T["popup persist_key"]["exclusive switch disables and persists the other"] = function()
  local path = tmp_path()
  local p = make_persist(path)
  p.set("switch_x", true)
  p.set("switch_y", false)

  local popup = require("gitlad.ui.popup")
  local data = popup
    .builder()
    :switch("x", "opt-x", "Option X", { persist_key = "switch_x", exclusive_with = { "opt-y" } })
    :switch("y", "opt-y", "Option Y", { persist_key = "switch_y" })
    :build()

  -- switch_x is loaded as enabled (saved true), switch_y as disabled (saved false)
  eq(data.switches[1].enabled, true)
  eq(data.switches[2].enabled, false)

  -- Enable switch_y (exclusive with opt-x) → should disable and persist switch_x=false
  data.switches[2].exclusive_with = { "opt-x" }
  data:toggle_switch("y")
  eq(data.switches[2].enabled, true)
  eq(data.switches[1].enabled, false)

  p._reset_cache()
  eq(p.get("switch_x"), false)
  eq(p.get("switch_y"), true)
end

return T
