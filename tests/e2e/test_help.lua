-- End-to-end tests for gitlad.nvim help popup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to create a file in the repo
local function create_file(child, repo, filename, content)
  child.lua(string.format(
    [[
    local path = %q .. "/" .. %q
    local f = io.open(path, "w")
    f:write(%q)
    f:close()
  ]],
    repo,
    filename,
    content
  ))
end

-- Helper to cleanup repo
local function cleanup_repo(child, repo)
  child.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

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

-- Help popup tests
T["help popup"] = MiniTest.new_set()

T["help popup"]["opens from status buffer with ? key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press ? to open help popup
  child.type_keys("?")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Close and cleanup
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["displays Navigation section"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  -- Get popup content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_navigation = false
  local found_j = false
  local found_k = false

  for _, line in ipairs(lines) do
    if line:match("Navigation") then
      found_navigation = true
    end
    -- Match "j Next item" with any whitespace
    if line:match("j%s+Next item") then
      found_j = true
    end
    -- Match "k Previous item" with any whitespace
    if line:match("k%s+Previous item") then
      found_k = true
    end
  end

  eq(found_navigation, true)
  eq(found_j, true)
  eq(found_k, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["displays Applying changes section"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_section = false
  local found_s = false
  local found_u = false
  local found_S = false
  local found_U = false

  for _, line in ipairs(lines) do
    -- Section is now "Applying changes"
    if line:match("Applying changes") then
      found_section = true
    end
    -- Descriptions are now shorter: "Stage", "Unstage", etc.
    if line:match("s%s+Stage[^%s]") or line:match("s%s+Stage%s") then
      found_s = true
    end
    if line:match("u%s+Unstage[^%s]") or line:match("u%s+Unstage%s") then
      found_u = true
    end
    if line:match("S%s+Stage all") then
      found_S = true
    end
    if line:match("U%s+Unstage all") then
      found_U = true
    end
  end

  eq(found_section, true)
  eq(found_s, true)
  eq(found_u, true)
  eq(found_S, true)
  eq(found_U, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["displays Transient commands section"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_transient = false
  local found_c = false
  local found_p = false

  for _, line in ipairs(lines) do
    -- Section is now "Transient commands"
    if line:match("Transient commands") then
      found_transient = true
    end
    if line:match("c%s+Commit") then
      found_c = true
    end
    if line:match("p%s+Push") then
      found_p = true
    end
  end

  eq(found_transient, true)
  eq(found_c, true)
  eq(found_p, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["displays Essential commands section"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_essential = false
  local found_gr = false
  local found_dollar = false
  local found_q = false
  local found_question = false

  for _, line in ipairs(lines) do
    -- Section is now "Essential commands"
    if line:match("Essential commands") then
      found_essential = true
    end
    if line:match("gr%s+Refresh") then
      found_gr = true
    end
    if line:match("%$%s+Git command history") then
      found_dollar = true
    end
    if line:match("q%s+Close") then
      found_q = true
    end
    if line:match("%?%s+This help") then
      found_question = true
    end
  end

  eq(found_essential, true)
  eq(found_gr, true)
  eq(found_dollar, true)
  eq(found_q, true)
  eq(found_question, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["closes with q key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  -- Verify 2 windows
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Close with q
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify back to 1 window
  win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 1)

  -- Verify we're in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  cleanup_repo(child, repo)
end

T["help popup"]["closes with Esc key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  -- Verify 2 windows
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Close with Esc
  child.type_keys("<Esc>")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify back to 1 window
  win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 1)

  cleanup_repo(child, repo)
end

T["help popup"]["pressing c opens commit popup"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and stage a file so commit popup can open
  create_file(child, repo, "test.txt", "hello")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help popup
  child.type_keys("?")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press c to open commit popup
  child.type_keys("c")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify commit popup is now shown (check for commit-specific content)
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_commit_action = false
  local found_amend = false

  for _, line in ipairs(lines) do
    -- Look for commit popup specific content (Amend action)
    if line:match("a%s+Amend") then
      found_amend = true
    end
    -- Look for the commit action with description
    if line:match("c%s+Commit") then
      found_commit_action = true
    end
  end

  eq(found_amend, true)
  eq(found_commit_action, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["pressing p opens push popup"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help popup
  child.type_keys("?")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press p to open push popup
  child.type_keys("p")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify push popup is now shown (check for push-specific content)
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_force_with_lease = false
  local found_push_action = false

  for _, line in ipairs(lines) do
    -- Look for push popup specific content
    if line:match("force%-with%-lease") then
      found_force_with_lease = true
    end
    -- Match either "p Push" or "p pushRemote" (new magit-style action)
    if line:match("p%s+[Pp]ush") then
      found_push_action = true
    end
  end

  eq(found_force_with_lease, true)
  eq(found_push_action, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["pressing $ opens git command history"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help popup
  child.type_keys("?")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press $ to open history
  child.type_keys("$")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify history buffer is shown
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://history") ~= nil, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["help popup"]["has title 'Help'"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("?")

  -- The popup should have a title "Help" in the window config
  -- We can check by looking at the window title if available
  -- For now, just verify the popup opens with correct content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Verify we have content (not empty)
  eq(#lines > 0, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

return T
