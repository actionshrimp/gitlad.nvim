-- End-to-end tests for gitlad.nvim fetch popup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start fresh child process for each test
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
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

-- Fetch popup tests
T["fetch popup"] = MiniTest.new_set()

T["fetch popup"]["opens from status buffer with f key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press f to open fetch popup
  child.type_keys("f")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains fetch-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_fetch_pushremote = false
  local found_fetch_upstream = false
  local found_fetch_elsewhere = false
  local found_fetch_all = false
  for _, line in ipairs(lines) do
    if line:match("p%s+Fetch from pushremote") then
      found_fetch_pushremote = true
    end
    if line:match("u%s+Fetch from upstream") then
      found_fetch_upstream = true
    end
    if line:match("e%s+Fetch elsewhere") then
      found_fetch_elsewhere = true
    end
    if line:match("a%s+Fetch all remotes") then
      found_fetch_all = true
    end
  end

  eq(found_fetch_pushremote, true)
  eq(found_fetch_upstream, true)
  eq(found_fetch_elsewhere, true)
  eq(found_fetch_all, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["fetch popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("f")

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_prune = false
  local found_tags = false

  for _, line in ipairs(lines) do
    if line:match("%-P.*[Pp]rune") then
      found_prune = true
    end
    if line:match("%-t.*tags") then
      found_tags = true
    end
  end

  eq(found_prune, true)
  eq(found_tags, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["fetch popup"]["switch toggling with -P"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("f")

  -- Check initial state - prune should not be enabled
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_before = child.lua_get([[popup_lines]])

  local prune_enabled_before = false
  for _, line in ipairs(lines_before) do
    if line:match("%*%-P.*[Pp]rune") then
      prune_enabled_before = true
    end
  end
  eq(prune_enabled_before, false)

  -- Toggle prune switch
  child.type_keys("-P")
  child.lua([[vim.wait(50, function() return false end)]])

  -- Check that switch is now enabled (has * marker)
  child.lua([[
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_after = child.lua_get([[popup_lines]])

  local prune_enabled_after = false
  for _, line in ipairs(lines_after) do
    if line:match("%*%-P.*[Pp]rune") then
      prune_enabled_after = true
    end
  end
  eq(prune_enabled_after, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["fetch popup"]["shows warning when no upstream configured"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (no remote, no upstream)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Clear messages
  child.lua([[vim.cmd("messages clear")]])

  -- Open fetch popup
  child.type_keys("f")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Try to fetch from upstream (should fail - no upstream)
  child.type_keys("u")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Should have shown warning message
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  eq(messages:match("No upstream configured") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["fetch popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open fetch popup
  child.type_keys("f")
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["fetch popup"]["f keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help with ?
  child.type_keys("?")

  -- Check for fetch popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_fetch = false
  for _, line in ipairs(lines) do
    if line:match("f%s+Fetch") then
      found_fetch = true
    end
  end

  eq(found_fetch, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

return T
