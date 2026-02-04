-- End-to-end tests for gitlad.nvim navigation and refresh
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

-- Helper for truthy assertions (mini.test doesn't have expect.truthy)
local function assert_truthy(val, msg)
  if not val then
    error(msg or "Expected truthy value, got: " .. tostring(val), 2)
  end
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start fresh child process for each test
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
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
    vim.fn.system("git -C " .. repo .. " config commit.gpgsign false")
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
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(path, "w")
    f:write(%q)
    f:close()
  ]],
    repo,
    filename,
    content
  ))
end

-- Helper to run git command in repo
local function git(child, repo, args)
  -- Use %q for both repo and args to properly escape quotes
  return child.lua_get(string.format("vim.fn.system('git -C ' .. %q .. ' ' .. %q)", repo, args))
end

-- Helper to get buffer lines
local function get_buffer_lines(child)
  return child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
end

-- Helper to find line containing text
local function find_line_with(lines, pattern)
  for i, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return i, line
    end
  end
  return nil, nil
end

-- Helper to wait for async operations
local function wait(child, ms)
  ms = ms or 100
  child.lua(string.format("vim.wait(%d, function() return false end)", ms))
end

-- Helper to open gitlad in a repo
local function open_gitlad(child, repo)
  child.cmd("cd " .. repo)
  child.cmd("Gitlad")
  wait(child, 200) -- Wait for async status fetch
end

-- =============================================================================
-- Refresh Tests
-- =============================================================================

T["refresh"] = MiniTest.new_set()

T["refresh"]["gr refreshes status"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  open_gitlad(child, repo)

  -- Initially no untracked files
  local lines = get_buffer_lines(child)
  local has_newfile = find_line_with(lines, "newfile.txt")
  eq(has_newfile, nil, "Should not show newfile.txt initially")

  -- Create a new file externally
  create_file(child, repo, "newfile.txt", "content")

  -- Simulate pressing 'gr' using feedkeys and process events
  child.lua([[
    vim.api.nvim_feedkeys("gr", "x", false)
  ]])

  -- Wait for async refresh to complete
  child.lua([[vim.wait(1000, function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("newfile.txt", 1, true) then return true end
    end
    return false
  end)]])

  -- Should now show the new file
  lines = get_buffer_lines(child)
  has_newfile = find_line_with(lines, "newfile.txt")
  assert_truthy(has_newfile, "Should show newfile.txt after refresh")
end

T["refresh"]["shows updated status after external git changes"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "file.txt", "original")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked file
  create_file(child, repo, "new.txt", "content")

  open_gitlad(child, repo)

  -- Verify file is in Untracked first
  local lines = get_buffer_lines(child)
  local untracked_section = find_line_with(lines, "Untracked")
  assert_truthy(untracked_section, "Should have Untracked section initially")

  -- Stage externally via git
  git(child, repo, "add new.txt")

  -- Simulate pressing 'gr' using feedkeys and process events
  child.lua([[
    vim.api.nvim_feedkeys("gr", "x", false)
  ]])

  -- Wait for refresh to complete - use vim.wait with a condition
  child.lua([[vim.wait(1000, function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("Staged", 1, true) then return true end
    end
    return false
  end)]])

  -- Should now show file as staged
  lines = get_buffer_lines(child)
  local staged_section = find_line_with(lines, "Staged")
  local new_line = find_line_with(lines, "new.txt")

  assert_truthy(staged_section, "Should have Staged section")
  assert_truthy(
    new_line and new_line > staged_section,
    "new.txt should be in staged section after refresh"
  )
end

-- =============================================================================
-- Navigation Tests
-- =============================================================================

T["navigation"] = MiniTest.new_set()

T["navigation"]["gj/gk keymaps are set up"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file to have something to navigate
  create_file(child, repo, "file.txt", "content")

  open_gitlad(child, repo)

  -- Check that gj and gk keymaps exist
  child.lua([[
    _G.has_gj = false
    _G.has_gk = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "gj" then _G.has_gj = true end
      if km.lhs == "gk" then _G.has_gk = true end
    end
  ]])
  local has_gj = child.lua_get("_G.has_gj")
  local has_gk = child.lua_get("_G.has_gk")
  eq(has_gj, true)
  eq(has_gk, true)
end

T["navigation"]["gj navigates to next file entry"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create multiple files
  create_file(child, repo, "aaa.txt", "content a")
  create_file(child, repo, "bbb.txt", "content b")

  open_gitlad(child, repo)

  -- Move to first line (header)
  child.cmd("1")

  -- Press gj to navigate to first file
  child.type_keys("gj")
  wait(child, 100)

  local lines = get_buffer_lines(child)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")

  -- Should be on a file line
  local line_content = lines[cursor_line]
  assert_truthy(
    line_content:find("aaa.txt") or line_content:find("bbb.txt"),
    "gj should move to a file entry, got: " .. (line_content or "nil")
  )
end

T["navigation"]["j/k are not overridden (normal vim movement)"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "file.txt", "content")

  open_gitlad(child, repo)

  -- Check that j and k are NOT mapped (normal vim movement)
  child.lua([[
    _G.has_j_mapping = false
    _G.has_k_mapping = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "j" then _G.has_j_mapping = true end
      if km.lhs == "k" then _G.has_k_mapping = true end
    end
  ]])
  local has_j = child.lua_get("_G.has_j_mapping")
  local has_k = child.lua_get("_G.has_k_mapping")
  -- j and k should NOT be mapped (allow normal line movement)
  eq(has_j, false)
  eq(has_k, false)
end

T["navigation"]["gr is mapped for refresh"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "file.txt", "content")

  open_gitlad(child, repo)

  -- Check that gr keymap exists
  child.lua([[
    _G.has_gr = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "gr" then _G.has_gr = true end
    end
  ]])
  local has_gr = child.lua_get("_G.has_gr")
  eq(has_gr, true)
end

T["navigation"]["gg works to jump to top of buffer"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create files to have content in buffer
  create_file(child, repo, "file1.txt", "content 1")
  create_file(child, repo, "file2.txt", "content 2")
  create_file(child, repo, "file3.txt", "content 3")

  open_gitlad(child, repo)

  -- Move to the bottom
  child.type_keys("G")
  wait(child, 100)

  local cursor_after_G = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(cursor_after_G > 1, "G should move to end of buffer")

  -- Now press gg to go to top
  child.type_keys("gg")
  wait(child, 100)

  local cursor_after_gg = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(cursor_after_gg, 1, "gg should move to line 1")
end

-- =============================================================================
-- CR on commit tests
-- =============================================================================

T["cr on commit"] = MiniTest.new_set()

T["cr on commit"]["<CR> on commit in log view triggers diff"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create commits
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "First commit"')

  create_file(child, repo, "file2.txt", "content 2")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Second commit"')

  open_gitlad(child, repo)

  -- Open log view (l then l)
  child.type_keys("ll")
  wait(child, 500)

  -- Verify we're in log buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  assert_truthy(buf_name:find("gitlad://log"), "Should be in log buffer")

  -- Navigate to a commit
  child.type_keys("gj")
  wait(child, 100)

  -- Press <CR> on commit - should trigger diff
  -- Since diffview may not be installed in test env, we capture any notification
  child.lua([[
    _G.last_notify = nil
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      _G.last_notify = { msg = msg, level = level }
      original_notify(msg, level)
    end
  ]])

  child.type_keys("<CR>")
  wait(child, 300)

  -- Either diffview opens (test passes), or we get a notification about diffview not being installed
  -- In either case, no error should occur - the key should be bound
  local errors = child.lua_get("vim.v.errmsg")
  eq(errors == "" or errors == nil, true, "Should not have errors")
end

T["cr on commit"]["<CR> keymap is set on log buffer"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a commit
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  open_gitlad(child, repo)

  -- Open log view
  child.type_keys("ll")
  wait(child, 500)

  -- Check that <CR> keymap exists
  child.lua([[
    _G.has_cr = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "<CR>" then _G.has_cr = true end
    end
  ]])
  local has_cr = child.lua_get("_G.has_cr")
  eq(has_cr, true, "<CR> should be mapped in log buffer")
end

T["navigation"]["reopening status buffer positions cursor at first item"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create multiple files so we have enough content to scroll
  for i = 1, 20 do
    create_file(child, repo, "file" .. i .. ".txt", "content " .. i)
  end

  open_gitlad(child, repo)

  -- Wait for buffer to have content (20 files should give us plenty of lines)
  child.lua([[
    vim.wait(2000, function()
      local line_count = vim.api.nvim_buf_line_count(0)
      return line_count > 15
    end)
  ]])

  -- Verify buffer has enough lines
  local line_count = child.lua_get("vim.api.nvim_buf_line_count(0)")
  assert_truthy(line_count > 15, "Buffer should have more than 15 lines, got " .. line_count)

  -- Get initial cursor position (should be at first item, not line 1 header)
  local initial_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(
    initial_line > 1,
    "Cursor should start past header line, at first item, got " .. initial_line
  )

  -- Remember where the first item is
  local first_item_line = initial_line

  -- Go to end of buffer using G (standard vim motion)
  child.type_keys("G")
  wait(child, 100)

  local scrolled_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(
    scrolled_line > first_item_line,
    "Should be past first item after G, got " .. scrolled_line
  )

  -- Close status buffer
  child.type_keys("q")
  wait(child, 100)

  -- Reopen status buffer
  child.cmd("Gitlad")
  wait(child, 500)

  -- Cursor should be back at first item (same position as initial open)
  local reopened_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(reopened_line, first_item_line, "Cursor should be at first item after reopening")
end

return T
