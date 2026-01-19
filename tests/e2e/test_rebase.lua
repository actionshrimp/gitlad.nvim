-- End-to-end tests for gitlad.nvim rebase popup
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

-- Rebase popup tests
T["rebase popup"] = MiniTest.new_set()

T["rebase popup"]["opens from status buffer with r key"] = function()
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
    if line:match("p%s+pushremote") then
      found_pushremote = true
    end
    if line:match("u%s+upstream") then
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
  cleanup_repo(child, repo)
end

T["rebase popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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
  local found_interactive = false

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
    if line:match("%-i.*[Ii]nteractive") then
      found_interactive = true
    end
  end

  eq(found_autostash, true)
  eq(found_keep_empty, true)
  eq(found_autosquash, true)
  eq(found_interactive, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["rebase popup"]["autostash is enabled by default"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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
  cleanup_repo(child, repo)
end

T["rebase popup"]["switch toggling with -A"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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
  cleanup_repo(child, repo)
end

T["rebase popup"]["shows warning when no upstream configured"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit (no remote, no upstream)
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Clear messages
  child.lua([[vim.cmd("messages clear")]])

  -- Open rebase popup
  child.type_keys("r")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Try to rebase onto upstream (should fail - no upstream)
  child.type_keys("u")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Should have shown warning message
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  eq(messages:match("No upstream configured") ~= nil, true)

  cleanup_repo(child, repo)
end

T["rebase popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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

  cleanup_repo(child, repo)
end

T["rebase popup"]["r keybinding appears in help"] = function()
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
  cleanup_repo(child, repo)
end

T["rebase popup"]["shows in-progress actions when rebase is active"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a second commit
  create_file(child, repo, "test.txt", "hello world")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Second"')

  -- Create a conflicting change and start rebase that will conflict
  -- First, create a branch from initial commit
  git(child, repo, "checkout -b feature HEAD~1")
  create_file(child, repo, "test.txt", "conflicting change")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  -- Try to rebase onto main (this will cause conflict)
  git(child, repo, "rebase main 2>&1 || true")

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

  cleanup_repo(child, repo)
end

T["rebase popup"]["status shows rebase in progress"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a second commit
  create_file(child, repo, "test.txt", "hello world")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Second"')

  -- Create a conflicting change and start rebase that will conflict
  git(child, repo, "checkout -b feature HEAD~1")
  create_file(child, repo, "test.txt", "conflicting change")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  -- Start rebase that will conflict
  git(child, repo, "rebase main 2>&1 || true")

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
  git(child, repo, "rebase --abort")
  cleanup_repo(child, repo)
end

return T
