-- E2E tests for popup persistent switches
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
      -- Point persist module to a temp file so tests don't pollute real data dir
      child.lua([[
        local persist = require("gitlad.utils.persist")
        persist._override_path = vim.fn.tempname() .. "_e2e_persist_test.json"
        persist._reset_cache()
      ]])
      _G.child = child
    end,
    post_case = function()
      if _G.child then
        -- Clean up temp file
        _G.child.lua([[
          local persist = require("gitlad.utils.persist")
          if persist._override_path then
            os.remove(persist._override_path)
          end
        ]])
        _G.child.stop()
        _G.child = nil
      end
    end,
  },
})

T["persistent switch survives popup close and reopen"] = function()
  local child = _G.child

  -- Open popup with a persistent switch, show it
  child.lua([[
    popup = require("gitlad.ui.popup")
    test_popup = popup.builder()
      :name("Test")
      :switch("i", "copy-ignored", "Copy ignored files", { persist_key = "wt_copy_ignored" })
      :action("s", "Switch", function() end)
      :build()
    test_popup:show()
  ]])

  -- Verify switch starts disabled
  local enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, false)

  -- Toggle the persistent switch on
  child.type_keys("-i")
  enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, true)

  -- Close the popup
  child.type_keys("q")

  -- Reopen a new popup instance with the same persist_key
  child.lua([[
    test_popup2 = popup.builder()
      :name("Test")
      :switch("i", "copy-ignored", "Copy ignored files", { persist_key = "wt_copy_ignored" })
      :action("s", "Switch", function() end)
      :build()
    test_popup2:show()
  ]])

  -- Persistent state should be loaded: switch is enabled
  enabled = child.lua_get([[test_popup2.switches[1].enabled]])
  eq(enabled, true)

  -- Popup buffer should reflect enabled state in rendered lines
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(test_popup2.buffer, 0, -1, false)]])
  local found_switch = false
  for _, line in ipairs(lines) do
    if line:match("%-i.*Copy ignored") then
      found_switch = true
    end
  end
  eq(found_switch, true)

  child.type_keys("q")
end

T["non-persistent switch does not reload after reopen"] = function()
  local child = _G.child

  child.lua([[
    popup = require("gitlad.ui.popup")
    test_popup = popup.builder()
      :name("Test")
      :switch("v", "verbose", "Verbose")
      :action("s", "Submit", function() end)
      :build()
    test_popup:show()
  ]])

  -- Toggle on
  child.type_keys("-v")
  local enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, true)

  -- Close and reopen
  child.type_keys("q")

  child.lua([[
    test_popup2 = popup.builder()
      :name("Test")
      :switch("v", "verbose", "Verbose")
      :action("s", "Submit", function() end)
      :build()
    test_popup2:show()
  ]])

  -- Non-persistent: should be false again
  enabled = child.lua_get([[test_popup2.switches[1].enabled]])
  eq(enabled, false)

  child.type_keys("q")
end

T["toggling persistent switch off also persists the off state"] = function()
  local child = _G.child

  child.lua([[
    popup = require("gitlad.ui.popup")
    -- Pre-seed persist with true so popup opens enabled
    local persist = require("gitlad.utils.persist")
    persist.set("wt_flag", true)
    test_popup = popup.builder()
      :name("Test")
      :switch("f", "flag", "My flag", { persist_key = "wt_flag" })
      :action("s", "Submit", function() end)
      :build()
    test_popup:show()
  ]])

  -- Loaded as enabled from persisted value
  local enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, true)

  -- Toggle off
  child.type_keys("-f")
  enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, false)

  -- Close and reopen: should come back as false
  child.type_keys("q")

  child.lua([[
    test_popup2 = popup.builder()
      :name("Test")
      :switch("f", "flag", "My flag", { persist_key = "wt_flag" })
      :action("s", "Submit", function() end)
      :build()
    test_popup2:show()
  ]])

  enabled = child.lua_get([[test_popup2.switches[1].enabled]])
  eq(enabled, false)

  child.type_keys("q")
end

T["persistent switch arguments included in get_arguments when enabled"] = function()
  local child = _G.child

  child.lua([[
    popup = require("gitlad.ui.popup")
    local persist = require("gitlad.utils.persist")
    persist.set("wt_copy_ignored2", true)
    test_popup = popup.builder()
      :name("Test")
      :switch("i", "copy-ignored", "Copy ignored", { persist_key = "wt_copy_ignored2" })
      :build()
  ]])

  local args = child.lua_get([[test_popup:get_arguments()]])
  eq(#args, 1)
  eq(args[1], "--copy-ignored")
end

return T
