-- End-to-end tests for gitlad.nvim rebase popup
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

-- Rebase popup tests
T["rebase popup"] = MiniTest.new_set()

T["rebase popup"]["opens from status buffer with r key"] = function()
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

  -- Press r to open rebase popup
  child.type_keys("r")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains rebase-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_pushremote = false
  local found_upstream = false
  local found_elsewhere = false
  for _, line in ipairs(lines) do
    -- Dynamic labels: shows "pushRemote, setting that" when not configured
    if line:match("p%s+pushRemote") then
      found_pushremote = true
    end
    -- Dynamic labels: shows "@{upstream}, setting it" when not configured
    if line:match("u%s+@{upstream}") then
      found_upstream = true
    end
    if line:match("e%s+elsewhere") then
      found_elsewhere = true
    end
  end

  eq(found_pushremote, true)
  eq(found_upstream, true)
  eq(found_elsewhere, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("r")

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_autostash = false
  local found_keep_empty = false
  local found_autosquash = false

  for _, line in ipairs(lines) do
    if line:match("%-A.*[Aa]utostash") then
      found_autostash = true
    end
    if line:match("%-k.*keep%-empty") then
      found_keep_empty = true
    end
    if line:match("%-a.*[Aa]utosquash") then
      found_autosquash = true
    end
  end

  eq(found_autostash, true)
  eq(found_keep_empty, true)
  eq(found_autosquash, true)
  -- Note: interactive (-i) is an action, not a switch, so it's tested separately in test_rebase_editor.lua

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["autostash is enabled by default"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("r")

  -- Check that autostash is enabled (has * marker)
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local autostash_enabled = false
  for _, line in ipairs(lines) do
    if line:match("%*%-A.*[Aa]utostash") then
      autostash_enabled = true
    end
  end
  eq(autostash_enabled, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["switch toggling with -A"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("r")

  -- Check initial state - autostash should be enabled
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_before = child.lua_get([[popup_lines]])

  local autostash_enabled_before = false
  for _, line in ipairs(lines_before) do
    if line:match("%*%-A.*[Aa]utostash") then
      autostash_enabled_before = true
    end
  end
  eq(autostash_enabled_before, true)

  -- Toggle autostash switch off
  child.type_keys("-A")
  child.lua([[vim.wait(50, function() return false end)]])

  -- Check that switch is now disabled (no * marker)
  child.lua([[
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_after = child.lua_get([[popup_lines]])

  local autostash_enabled_after = false
  for _, line in ipairs(lines_after) do
    if line:match("%*%-A.*[Aa]utostash") then
      autostash_enabled_after = true
    end
  end
  eq(autostash_enabled_after, false)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["prompts to set upstream when not configured"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (no remote, no upstream)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Mock the prompt module's prompt_for_ref function to track if it was called
  -- This is more reliable than mocking vim.ui.input since the prompt module
  -- might use mini.pick or snacks.nvim if available
  child.lua([[
    _G.prompt_was_called = false
    local prompt = require("gitlad.utils.prompt")
    _G.original_prompt_for_ref = prompt.prompt_for_ref
    prompt.prompt_for_ref = function(opts, callback)
      _G.prompt_was_called = true
      -- Cancel the prompt to avoid hanging
      if callback then
        callback(nil)
      end
    end
  ]])

  -- Open rebase popup
  child.type_keys("r")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Try to rebase onto upstream (should prompt to set it)
  child.type_keys("u")
  child.lua([[vim.wait(300, function() return false end)]])

  -- Verify prompt was invoked (magit-style flow: prompt to set upstream)
  local prompt_called = child.lua_get([[_G.prompt_was_called]])
  eq(prompt_called, true)

  -- Restore original prompt_for_ref
  child.lua([[
    local prompt = require("gitlad.utils.prompt")
    prompt.prompt_for_ref = _G.original_prompt_for_ref
  ]])

  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open rebase popup
  child.type_keys("r")
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

T["rebase popup"]["r keybinding appears in help"] = function()
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

  -- Check for rebase popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_rebase = false
  for _, line in ipairs(lines) do
    if line:match("r%s+Rebase") then
      found_rebase = true
    end
  end

  eq(found_rebase, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["shows in-progress actions when rebase is active"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second commit on a named branch (avoid main/master ambiguity)
  helpers.git(child, repo, "checkout -b target")
  helpers.create_file(child, repo, "test.txt", "hello world")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Second"')

  -- Create a conflicting change and start rebase that will conflict
  -- First, create a branch from initial commit
  helpers.git(child, repo, "checkout -b feature HEAD~1")
  helpers.create_file(child, repo, "test.txt", "conflicting change")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature"')

  -- Try to rebase onto target (this will cause conflict)
  helpers.git(child, repo, "rebase target 2>&1 || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open rebase popup - should show in-progress actions
  child.type_keys("r")

  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_continue = false
  local found_skip = false
  local found_abort = false
  for _, line in ipairs(lines) do
    if line:match("r%s+Continue") then
      found_continue = true
    end
    if line:match("s%s+Skip") then
      found_skip = true
    end
    if line:match("a%s+Abort") then
      found_abort = true
    end
  end

  eq(found_continue, true)
  eq(found_skip, true)
  eq(found_abort, true)

  -- Abort the rebase to clean up
  child.type_keys("a")
  child.lua([[vim.wait(300, function() return false end)]])

  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["status shows rebase in progress"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second commit on a named branch (avoid main/master ambiguity)
  helpers.git(child, repo, "checkout -b target")
  helpers.create_file(child, repo, "test.txt", "hello world")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Second"')

  -- Create a conflicting change and start rebase that will conflict
  helpers.git(child, repo, "checkout -b feature HEAD~1")
  helpers.create_file(child, repo, "test.txt", "conflicting change")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature"')

  -- Start rebase that will conflict
  helpers.git(child, repo, "rebase target 2>&1 || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Check that status shows rebase in progress
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_rebasing = false
  for _, line in ipairs(lines) do
    if line:match("Rebasing") then
      found_rebasing = true
    end
  end

  eq(found_rebasing, true)

  -- Abort the rebase to clean up
  helpers.git(child, repo, "rebase --abort")
  helpers.cleanup_repo(child, repo)
end

T["rebase popup"]["continue after resolving conflicts opens commit editor"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second commit on a named branch
  helpers.git(child, repo, "checkout -b target")
  helpers.create_file(child, repo, "test.txt", "hello world")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Second"')

  -- Create a conflicting change and start rebase that will conflict
  helpers.git(child, repo, "checkout -b feature HEAD~1")
  helpers.create_file(child, repo, "test.txt", "conflicting change")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature"')

  -- Start rebase that will conflict
  helpers.git(child, repo, "rebase target 2>&1 || true")

  -- Resolve the conflict by writing the resolved content
  helpers.create_file(child, repo, "test.txt", "resolved content")
  helpers.git(child, repo, "add test.txt")

  -- Open gitlad status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify rebase is in progress
  local rebase_in_progress =
    child.lua_get(string.format([[require("gitlad.git").rebase_in_progress({ cwd = %q })]], repo))
  eq(rebase_in_progress, true)

  -- Open rebase popup with 'r'
  child.type_keys("r")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Press 'r' to continue
  child.type_keys("r")

  -- Wait for the commit editor to open (COMMIT_EDITMSG file)
  -- The editor should open because git needs to confirm the conflict resolution message
  child.lua([[
    vim.wait(2000, function()
      local bufname = vim.api.nvim_buf_get_name(0)
      return bufname:match("COMMIT_EDITMSG") ~= nil
    end, 50)
  ]])

  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("COMMIT_EDITMSG") ~= nil, true)

  -- The commit message should contain conflict information
  child.lua([[
    _test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_test_lines]])
  local content = table.concat(lines, "\n")

  -- Should contain "Conflicts:" section added by git
  eq(content:find("Conflicts:") ~= nil or content:find("Feature") ~= nil, true)

  -- Accept the commit message with ZZ to complete the rebase
  child.type_keys("ZZ")

  -- Wait for rebase to complete (condition-based wait instead of fixed timeout)
  child.lua(string.format(
    [[
    vim.wait(5000, function()
      return not require("gitlad.git").rebase_in_progress({ cwd = %q })
    end, 50)
  ]],
    repo
  ))

  -- Verify rebase completed (no longer in progress)
  local rebase_still_in_progress =
    child.lua_get(string.format([[require("gitlad.git").rebase_in_progress({ cwd = %q })]], repo))
  eq(rebase_still_in_progress, false)

  -- Verify we're back in the status buffer (not a blank scratch buffer)
  local final_bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(final_bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

return T
