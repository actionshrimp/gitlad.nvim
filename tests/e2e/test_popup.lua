-- End-to-end tests for gitlad.nvim popup system
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start fresh child process for each test
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
      -- Load popup module
      child.lua([[popup = require("gitlad.ui.popup")]])
      -- Store child in test context
      _G.child = child
    end,
    post_case = function()
      if _G.child then
        _G.child.stop()
        _G.child = nil
      end
    end,
  },
})

T["popup shows and closes with q"] = function()
  local child = _G.child

  child.lua([[
    test_popup = popup.builder()
      :name("Test Popup")
      :switch("a", "all", "All files")
      :action("c", "Commit", function() end)
      :build()
    test_popup:show()
  ]])

  -- Verify popup window exists
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2) -- Main window + popup

  -- Verify buffer contains expected content
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(test_popup.buffer, 0, -1, false)]])
  local found_args = false
  local found_switch = false
  for _, line in ipairs(lines) do
    if line:match("Arguments") then
      found_args = true
    end
    if line:match("%-a.*All files") then
      found_switch = true
    end
  end
  eq(found_args, true)
  eq(found_switch, true)

  -- Close with q
  child.type_keys("q")

  -- Verify popup is closed
  win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 1)
end

T["switch toggle with -key"] = function()
  local child = _G.child

  child.lua([[
    test_popup = popup.builder()
      :name("Test Popup")
      :switch("a", "all", "All files")
      :switch("v", "verbose", "Verbose")
      :build()
    test_popup:show()
  ]])

  -- Check initial state (not enabled)
  local enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, false)

  -- Toggle switch with -a
  child.type_keys("-a")

  -- Check state is now enabled
  enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, true)

  -- Toggle again
  child.type_keys("-a")

  -- Check state is back to disabled
  enabled = child.lua_get([[test_popup.switches[1].enabled]])
  eq(enabled, false)

  -- Clean up
  child.type_keys("q")
end

T["action callback is called and popup closes"] = function()
  local child = _G.child

  child.lua([[
    action_called = false
    action_popup = nil
    test_popup = popup.builder()
      :name("Test Popup")
      :action("c", "Commit", function(p)
        action_called = true
        action_popup = p
      end)
      :build()
    test_popup:show()
  ]])

  -- Verify popup is open
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Press action key
  child.type_keys("c")

  -- Verify callback was called
  local called = child.lua_get([[action_called]])
  eq(called, true)

  -- Verify popup was passed to callback
  local popup_passed = child.lua_get([[action_popup ~= nil]])
  eq(popup_passed, true)

  -- Verify popup is closed
  win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 1)
end

T["get_arguments returns correct CLI args after toggling"] = function()
  local child = _G.child

  child.lua([[
    test_popup = popup.builder()
      :name("Test Popup")
      :switch("a", "all", "All files")
      :switch("v", "verbose", "Verbose")
      :option("A", "author", "", "Author")
      :build()
    test_popup:show()
  ]])

  -- Initially no args
  local args = child.lua_get([[test_popup:get_arguments()]])
  eq(#args, 0)

  -- Toggle first switch
  child.type_keys("-a")

  args = child.lua_get([[test_popup:get_arguments()]])
  eq(#args, 1)
  eq(args[1], "--all")

  -- Toggle second switch
  child.type_keys("-v")

  args = child.lua_get([[test_popup:get_arguments()]])
  eq(#args, 2)
  eq(args[1], "--all")
  eq(args[2], "--verbose")

  -- Set option value directly (since vim.ui.input is tricky to test)
  child.lua([[test_popup:set_option("A", "John")]])
  child.lua([[test_popup:refresh()]])

  args = child.lua_get([[test_popup:get_arguments()]])
  eq(#args, 3)
  eq(args[3], "--author=John")

  -- Clean up
  child.type_keys("q")
end

T["to_cli returns correct string"] = function()
  local child = _G.child

  child.lua([[
    test_popup = popup.builder()
      :name("Test Popup")
      :switch("a", "all", "All", { enabled = true })
      :switch("v", "verbose", "Verbose", { enabled = true })
      :option("A", "author", "Jane", "Author")
      :build()
  ]])

  local cli = child.lua_get([[test_popup:to_cli()]])
  eq(cli, "--all --verbose --author=Jane")
end

T["Esc closes popup"] = function()
  local child = _G.child

  child.lua([[
    test_popup = popup.builder()
      :name("Test Popup")
      :action("c", "Commit", function() end)
      :build()
    test_popup:show()
  ]])

  -- Verify popup is open
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Close with Escape
  child.type_keys("<Esc>")

  -- Verify popup is closed
  win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 1)
end

return T
