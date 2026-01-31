-- End-to-end tests for gitlad.nvim push popup
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

-- Helper to create a test git repository
local function create_test_repo(child)
  local repo = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init")
    vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")
  ]],
    repo
  ))
  return repo
end

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

-- Helper to run a git command
local function git(child, repo, args)
  return child.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
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

-- Push popup tests
T["push popup"] = MiniTest.new_set()

T["push popup"]["opens from status buffer with p key"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

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
  cleanup_repo(child, repo)
end

T["push popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

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
  cleanup_repo(child, repo)
end

T["push popup"]["switch toggling with -f"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("p")

  -- Check initial state - force-with-lease should not be enabled
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_before = child.lua_get([[popup_lines]])

  local force_lease_enabled_before = false
  for _, line in ipairs(lines_before) do
    if line:match("%*%-f.*force%-with%-lease") then
      force_lease_enabled_before = true
    end
  end
  eq(force_lease_enabled_before, false)

  -- Toggle force-with-lease switch
  child.type_keys("-f")
  child.lua([[vim.wait(50, function() return false end)]])

  -- Check that switch is now enabled (has * marker)
  child.lua([[
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines_after = child.lua_get([[popup_lines]])

  local force_lease_enabled_after = false
  for _, line in ipairs(lines_after) do
    if line:match("%*%-f.*force%-with%-lease") then
      force_lease_enabled_after = true
    end
  end
  eq(force_lease_enabled_after, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["push popup"]["shows warning when no remote configured"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit (no remote at all)
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open push popup
  child.type_keys("p")
  child.lua([[vim.wait(100, function() return false end)]])

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
  cleanup_repo(child, repo)
end

T["push popup"]["has remote option for manual override"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add a single remote
  git(child, repo, "remote add myremote https://example.com/repo.git")

  -- Create a new branch with no upstream configured
  git(child, repo, "checkout -b feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(800, function() return false end)]])

  -- Open push popup and verify remote option exists (can be set with =r)
  child.type_keys("p")
  child.lua([[vim.wait(100, function() return false end)]])

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
  cleanup_repo(child, repo)
end

T["push popup"]["shows magit-style push actions"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Add multiple remotes
  git(child, repo, "remote add upstream https://example.com/upstream.git")
  git(child, repo, "remote add origin https://example.com/origin.git")
  git(child, repo, "remote add fork https://example.com/fork.git")

  -- Create a new branch with no upstream configured
  git(child, repo, "checkout -b feature-branch")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(800, function() return false end)]])

  -- Open push popup
  child.type_keys("p")
  child.lua([[vim.wait(100, function() return false end)]])

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
  cleanup_repo(child, repo)
end

T["push popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open push popup
  child.type_keys("p")
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

  cleanup_repo(child, repo)
end

T["push popup"]["p keybinding appears in help"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

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
  cleanup_repo(child, repo)
end

return T
