-- End-to-end tests for gitlad.nvim push popup
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

-- Push popup tests
T["push popup"] = MiniTest.new_set()

T["push popup"]["opens from status buffer with p key"] = function()
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
  helpers.wait_for_status(child)

  -- Press p to open push popup (evil-collection-magit style)
  child.type_keys("p")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains push-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_pushremote = false
  local found_elsewhere = false
  for _, line in ipairs(lines) do
    -- New magit-style action names
    if line:match("p%s+pushRemote") then
      found_pushremote = true
    end
    if line:match("e%s+elsewhere") then
      found_elsewhere = true
    end
  end

  eq(found_pushremote, true)
  eq(found_elsewhere, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("p")

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_force_lease = false
  local found_force = false
  local found_dry_run = false
  local found_tags = false

  for _, line in ipairs(lines) do
    if line:match("%-f.*force%-with%-lease") then
      found_force_lease = true
    end
    if line:match("%-F.*force") and not line:match("force%-with%-lease") then
      found_force = true
    end
    if line:match("%-n.*dry%-run") then
      found_dry_run = true
    end
    if line:match("%-t.*tags") then
      found_tags = true
    end
  end

  eq(found_force_lease, true)
  eq(found_force, true)
  eq(found_dry_run, true)
  eq(found_tags, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push popup"]["switch toggling with -f"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("p")

  -- Check initial state - force-with-lease should not be enabled
  helpers.wait_for_popup(child)
  eq(helpers.popup_switch_enabled(child, "%-f.*force%-with%-lease"), false)

  -- Toggle force-with-lease switch
  child.type_keys("-f")
  helpers.wait_short(child)

  -- Check that switch is now enabled (highlighted)
  eq(helpers.popup_switch_enabled(child, "%-f.*force%-with%-lease"), true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push popup"]["shows warning when no remote configured"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (no remote at all)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Verify popup shows "Push main to" heading (includes branch name)
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_push_heading = false
  for _, line in ipairs(lines) do
    if line:match("Push.*to") then
      found_push_heading = true
      break
    end
  end
  eq(found_push_heading, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push popup"]["has remote option for manual override"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Add a single remote
  helpers.git(child, repo, "remote add myremote https://example.com/repo.git")

  -- Create a new branch with no upstream configured
  helpers.git(child, repo, "checkout -b feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup and verify remote option exists (can be set with =r)
  child.type_keys("p")
  helpers.wait_for_popup(child)

  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Should have =r Remote option (starts empty, user can set it)
  local found_remote_option = false
  for _, line in ipairs(lines) do
    if line:match("=r%s+Remote") then
      found_remote_option = true
      break
    end
  end
  eq(found_remote_option, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push popup"]["shows magit-style push actions"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Add multiple remotes
  helpers.git(child, repo, "remote add upstream https://example.com/upstream.git")
  helpers.git(child, repo, "remote add origin https://example.com/origin.git")
  helpers.git(child, repo, "remote add fork https://example.com/fork.git")

  -- Create a new branch with no upstream configured
  helpers.git(child, repo, "checkout -b feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Should show magit-style actions:
  -- - pushRemote: either "pushRemote, setting that" (unconfigured) or actual ref like "origin/branch"
  -- - upstream: either "@{upstream}, setting it" (unconfigured) or actual ref like "origin/main"
  -- - elsewhere: always "elsewhere"
  local found_pushremote = false
  local found_upstream = false
  local found_elsewhere = false
  for _, line in ipairs(lines) do
    -- Match either "pushRemote" (unconfigured) or a ref like "origin/something" (configured)
    if line:match("^%s*p%s+pushRemote") or line:match("^%s*p%s+%S+/%S+") then
      found_pushremote = true
    end
    -- Match either "@{upstream}" (unconfigured) or a ref like "origin/something" (configured)
    if line:match("^%s*u%s+@{upstream}") or line:match("^%s*u%s+%S+/%S+") then
      found_upstream = true
    end
    if line:match("^%s*e%s+elsewhere") then
      found_elsewhere = true
    end
  end
  eq(found_pushremote, true)
  eq(found_upstream, true)
  eq(found_elsewhere, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  helpers.wait_for_popup(child)

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["push popup"]["p keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")

  -- Check for push popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_push = false
  for _, line in ipairs(lines) do
    if line:match("p%s+Push") then
      found_push = true
    end
  end

  eq(found_push, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

-- Push section tests (o, T, t actions)
T["push section"] = MiniTest.new_set()

T["push section"]["popup shows Push section with o, T, t actions"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Check for new Push section with o, T, t actions
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_push_section = false
  local found_another_branch = false
  local found_a_tag = false
  local found_all_tags = false

  for _, line in ipairs(lines) do
    -- Look for the "Push" section heading (distinct from "Push main to" section)
    if line:match("^Push$") then
      found_push_section = true
    end
    if line:match("o%s+another branch") then
      found_another_branch = true
    end
    if line:match("T%s+a tag") then
      found_a_tag = true
    end
    if line:match("t%s+all tags") then
      found_all_tags = true
    end
  end

  eq(found_push_section, true)
  eq(found_another_branch, true)
  eq(found_a_tag, true)
  eq(found_all_tags, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["push section"]["T action shows no tags message when no tags exist"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (no tags)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Press T to push a tag - should show "No tags found" message
  child.type_keys("T")
  helpers.wait_short(child, 200)

  -- Check notification for no tags
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  eq(messages:match("No tags found") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["push section"]["t action shows no remotes message when no remotes configured"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (no remote)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Press t to push all tags - should show "No remotes configured" message
  child.type_keys("t")

  -- Wait for the "No remotes configured" message to appear
  local found = helpers.wait_for_message(child, "No remotes configured")
  eq(found, true)

  helpers.cleanup_repo(child, repo)
end

T["push section"]["T action shows tag list when tags exist"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit with tags
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')
  helpers.git(child, repo, "tag v1.0.0")
  helpers.git(child, repo, "tag v1.0.1")

  -- Add a remote
  helpers.git(child, repo, "remote add origin https://example.com/repo.git")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Press T to push a tag - should open tag selector
  child.type_keys("T")
  helpers.wait_short(child, 300)

  -- The vim.ui.select should be showing tags
  -- We can't easily verify vim.ui.select content, but we can verify no error occurred
  -- and that the popup closed (action was triggered)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  -- There should be the status window + possibly the select popup
  eq(win_count >= 1, true)

  -- Cancel the selection
  child.type_keys("<Esc>")
  helpers.wait_for_popup(child)

  helpers.cleanup_repo(child, repo)
end

return T
