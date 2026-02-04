-- End-to-end tests for gitlad.nvim stash popup
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

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

-- Stash popup tests
T["stash popup"] = MiniTest.new_set()

T["stash popup"]["opens from status buffer with z key"] = function()
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
  helpers.wait_for_status(child)

  -- Press z to open stash popup
  child.type_keys("z")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains stash-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_stash = false
  local found_pop = false
  local found_apply = false
  for _, line in ipairs(lines) do
    if line:match("z%s+Stash") then
      found_stash = true
    end
    if line:match("p%s+Pop") then
      found_pop = true
    end
    if line:match("a%s+Apply") then
      found_apply = true
    end
  end

  eq(found_stash, true)
  eq(found_pop, true)
  eq(found_apply, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["stash popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("z")
  helpers.wait_for_popup(child)

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_untracked = false
  local found_all = false
  local found_keep_index = false

  for _, line in ipairs(lines) do
    if line:match("%-u.*include%-untracked") then
      found_untracked = true
    end
    if line:match("%-a.*all") then
      found_all = true
    end
    if line:match("%-k.*keep%-index") then
      found_keep_index = true
    end
  end

  eq(found_untracked, true)
  eq(found_all, true)
  eq(found_keep_index, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["stash popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open stash popup
  child.type_keys("z")
  helpers.wait_for_popup(child)
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  helpers.wait_for_popup_closed(child)

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  cleanup_repo(child, repo)
end

T["stash popup"]["z keybinding appears in help"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")

  -- Check for stash popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_stash = false
  for _, line in ipairs(lines) do
    if line:match("z%s+Stash") then
      found_stash = true
    end
  end

  eq(found_stash, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Stash operations tests
T["stash operations"] = MiniTest.new_set()

T["stash operations"]["stash push creates a stash"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes
  create_file(child, repo, "test.txt", "modified")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify no stashes initially
  local stashes_before = git(child, repo, "stash list")
  eq(stashes_before:match("stash@") == nil, true)

  -- Stash changes using git module
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_push("test stash", {}, { cwd = %q }, function(success, err)
      _G.stash_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.stash_result")
  local result = child.lua_get([[_G.stash_result]])

  eq(result.success, true)

  -- Verify stash was created
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") ~= nil, true)
  eq(stashes_after:match("test stash") ~= nil, true)

  -- Verify working directory is clean
  local status = git(child, repo, "status --porcelain")
  eq(status:gsub("%s+", ""), "")

  cleanup_repo(child, repo)
end

T["stash operations"]["stash pop applies and removes stash"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes and stash them
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify stash exists
  local stashes_before = git(child, repo, "stash list")
  eq(stashes_before:match("stash@{0}") ~= nil, true)

  -- Pop the stash
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_pop("stash@{0}", { cwd = %q }, function(success, err)
      _G.pop_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.pop_result")
  local result = child.lua_get([[_G.pop_result]])

  eq(result.success, true)

  -- Verify stash is gone
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") == nil, true)

  -- Verify changes are back
  local status = git(child, repo, "status --porcelain")
  eq(status:match("M test.txt") ~= nil or status:match("M%s+test.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

T["stash operations"]["stash apply keeps stash in list"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes and stash them
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Apply the stash (without removing)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_apply("stash@{0}", { cwd = %q }, function(success, err)
      _G.apply_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.apply_result")
  local result = child.lua_get([[_G.apply_result]])

  eq(result.success, true)

  -- Verify stash still exists
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") ~= nil, true)

  -- Verify changes are applied
  local status = git(child, repo, "status --porcelain")
  eq(status:match("M test.txt") ~= nil or status:match("M%s+test.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

T["stash operations"]["stash drop removes stash without applying"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Make changes and stash them
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify stash exists
  local stashes_before = git(child, repo, "stash list")
  eq(stashes_before:match("stash@{0}") ~= nil, true)

  -- Verify working directory is clean
  local status_before = git(child, repo, "status --porcelain")
  eq(status_before:gsub("%s+", ""), "")

  -- Drop the stash
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_drop("stash@{0}", { cwd = %q }, function(success, err)
      _G.drop_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.drop_result")
  local result = child.lua_get([[_G.drop_result]])

  eq(result.success, true)

  -- Verify stash is gone
  local stashes_after = git(child, repo, "stash list")
  eq(stashes_after:match("stash@{0}") == nil, true)

  -- Verify working directory is still clean (changes weren't applied)
  local status_after = git(child, repo, "status --porcelain")
  eq(status_after:gsub("%s+", ""), "")

  cleanup_repo(child, repo)
end

T["stash operations"]["stash list returns parsed entries"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create multiple stashes
  create_file(child, repo, "test.txt", "modified 1")
  git(child, repo, "stash push -m 'first stash'")

  create_file(child, repo, "test.txt", "modified 2")
  git(child, repo, "stash push -m 'second stash'")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Get stash list
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.stash_list({ cwd = %q }, function(stashes, err)
      _G.list_result = { stashes = stashes, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.list_result")
  local result = child.lua_get([[_G.list_result]])

  eq(result.err == nil, true)
  eq(#result.stashes, 2)

  -- Most recent stash is first (index 0)
  eq(result.stashes[1].index, 0)
  eq(result.stashes[1].ref, "stash@{0}")
  eq(result.stashes[1].message, "second stash")

  eq(result.stashes[2].index, 1)
  eq(result.stashes[2].ref, "stash@{1}")
  eq(result.stashes[2].message, "first stash")

  cleanup_repo(child, repo)
end

-- Stash section in status view tests
T["stash section"] = MiniTest.new_set()

T["stash section"]["shows Stashes section when stashes exist"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a stash
  create_file(child, repo, "test.txt", "modified")
  git(child, repo, "stash push -m 'test stash'")

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Get buffer lines
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    _G.status_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G.status_lines]])

  -- Find Stashes section
  local found_stashes_section = false
  local found_stash_entry = false
  for _, line in ipairs(lines) do
    if line:match("^Stashes %(%d+%)") then
      found_stashes_section = true
    end
    if line:match("stash@{0}") and line:match("test stash") then
      found_stash_entry = true
    end
  end

  eq(found_stashes_section, true)
  eq(found_stash_entry, true)

  cleanup_repo(child, repo)
end

T["stash section"]["hides Stashes section when no stashes"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit only (no stashes)
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Get buffer lines
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    _G.status_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G.status_lines]])

  -- Should NOT have Stashes section
  local found_stashes_section = false
  for _, line in ipairs(lines) do
    if line:match("^Stashes") then
      found_stashes_section = true
    end
  end

  eq(found_stashes_section, false)

  cleanup_repo(child, repo)
end

T["stash section"]["navigation includes stash entries with gj/gk"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create two stashes
  create_file(child, repo, "test.txt", "modified 1")
  git(child, repo, "stash push -m 'first stash'")
  create_file(child, repo, "test.txt", "modified 2")
  git(child, repo, "stash push -m 'second stash'")

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Get buffer content and find stash line
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.stash_line = nil
    for i, line in ipairs(lines) do
      if line:match("stash@{0}") then
        _G.stash_line = i
        break
      end
    end
  ]])
  local stash_line = child.lua_get([[_G.stash_line]])

  -- Stash line should exist
  eq(stash_line ~= nil, true)

  -- Navigate with gj until we reach the stash line
  child.type_keys("gg") -- Go to top first
  for _ = 1, 20 do -- Navigate down several times
    child.type_keys("gj")
    local current_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
    if current_line == stash_line then
      break
    end
  end

  -- Verify we can reach the stash line
  local final_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(final_line, stash_line)

  cleanup_repo(child, repo)
end

T["stash section"]["TAB collapses and expands stash section"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and stash
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  create_file(child, repo, "test.txt", "modified")
  git(child, repo, "stash push -m 'test stash'")

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Find and navigate to Stashes section header
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.stashes_header_line = nil
    for i, line in ipairs(lines) do
      if line:match("^Stashes %(%d+%)") then
        _G.stashes_header_line = i
        break
      end
    end
  ]])
  local header_line = child.lua_get([[_G.stashes_header_line]])
  eq(header_line ~= nil, true)

  -- Move cursor to stashes header
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], header_line))

  -- Check stash entry is visible
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_stash_entry = false
    for _, line in ipairs(lines) do
      if line:match("stash@{0}") then
        _G.has_stash_entry = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.has_stash_entry]]), true)

  -- Press TAB to collapse
  child.type_keys("<Tab>")
  helpers.wait_short(child)

  -- Check stash entry is now hidden
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_stash_entry_after_collapse = false
    for _, line in ipairs(lines) do
      if line:match("stash@{0}") then
        _G.has_stash_entry_after_collapse = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.has_stash_entry_after_collapse]]), false)

  -- Press TAB again to expand
  child.type_keys("<Tab>")
  helpers.wait_short(child)

  -- Check stash entry is visible again
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_stash_entry_after_expand = false
    for _, line in ipairs(lines) do
      if line:match("stash@{0}") then
        _G.has_stash_entry_after_expand = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.has_stash_entry_after_expand]]), true)

  cleanup_repo(child, repo)
end

T["stash section"]["p on stash entry opens stash popup"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and stash
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  create_file(child, repo, "test.txt", "modified")
  git(child, repo, "stash push -m 'test stash'")

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Find and navigate to stash entry
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("stash@{0}") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Press p on stash entry (should open stash popup, not push popup)
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Should have a popup window
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify it's the stash popup by checking content
  -- Stash popup has "Stash" group heading and "Use" group heading with pop/apply/drop actions
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_stash_group = false
    _G.has_use_group = false
    _G.has_pop_action = false
    for _, line in ipairs(lines) do
      if line:match("^Stash$") then
        _G.has_stash_group = true
      end
      if line:match("^Use$") then
        _G.has_use_group = true
      end
      -- Pop action shows "Pop stash@{0}" when stash is at point
      if line:match("p%s+Pop") then
        _G.has_pop_action = true
      end
    end
  ]])
  eq(child.lua_get([[_G.has_stash_group]]), true)
  eq(child.lua_get([[_G.has_use_group]]), true)
  eq(child.lua_get([[_G.has_pop_action]]), true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["stash section"]["p not on stash opens push popup"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit (no stashes)
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Press p (not on stash entry, should open push popup)
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Should have a popup window
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify it's the push popup by checking content
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.is_push_popup = false
    for _, line in ipairs(lines) do
      if line:match("Push") then
        _G.is_push_popup = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.is_push_popup]]), true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["stash section"]["RET on stash entry calls diff_stash"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and stash
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Find and navigate to stash entry
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.stash_line = nil
    for i, line in ipairs(lines) do
      if line:match("stash@{0}") then
        _G.stash_line = i
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  local stash_line = child.lua_get([[_G.stash_line]])
  eq(stash_line ~= nil, true)

  -- Mock diffview to capture the call (since diffview may not be installed)
  -- We'll verify that _diff_stash is called with correct args by checking the fallback notification
  child.lua([[
    -- Override vim.notify to capture the notification
    _G.notify_calls = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.notify_calls, { msg = msg, level = level })
      original_notify(msg, level)
    end
  ]])

  -- Press RET on the stash entry
  child.type_keys("<CR>")
  helpers.wait_short(child, 200)

  -- When diffview is not installed, _diff_stash should show a notification about it
  -- or open a terminal with the fallback command
  -- Check if we got the diffview not installed message OR a terminal was opened
  child.lua([[
    _G.diffview_warning_shown = false
    _G.terminal_opened = false
    for _, call in ipairs(_G.notify_calls) do
      if call.msg:match("diffview.nvim not installed") then
        _G.diffview_warning_shown = true
      end
    end
    -- Check if a terminal buffer was created with stash show command
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
      if buftype == "terminal" then
        _G.terminal_opened = true
      end
    end
  ]])

  -- Either diffview warning was shown or terminal was opened (fallback behavior)
  local diffview_warning = child.lua_get([[_G.diffview_warning_shown]])
  local terminal_opened = child.lua_get([[_G.terminal_opened]])

  -- One of these should be true (either diffview fallback kicked in)
  eq(diffview_warning or terminal_opened, true)

  cleanup_repo(child, repo)
end

T["stash section"]["d d (dwim) on stash entry shows stash diff"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit and stash
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')
  create_file(child, repo, "test.txt", "modified content")
  git(child, repo, "stash push -m 'test stash'")

  -- Open status view
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Find and navigate to stash entry
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.stash_line = nil
    for i, line in ipairs(lines) do
      if line:match("stash@{0}") then
        _G.stash_line = i
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  local stash_line = child.lua_get([[_G.stash_line]])
  eq(stash_line ~= nil, true)

  -- Mock diffview to capture the call
  child.lua([[
    _G.notify_calls = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.notify_calls, { msg = msg, level = level })
      original_notify(msg, level)
    end
  ]])

  -- Open diff popup with 'd', then press 'd' for dwim
  child.type_keys("d")
  helpers.wait_for_popup(child)

  -- Press 'd' again for dwim action
  child.type_keys("d")
  helpers.wait_short(child, 200)

  -- When diffview is not installed, _diff_stash should show a notification about it
  -- or open a terminal with the fallback command
  child.lua([[
    _G.diffview_warning_shown = false
    _G.terminal_opened = false
    for _, call in ipairs(_G.notify_calls) do
      if call.msg:match("diffview.nvim not installed") then
        _G.diffview_warning_shown = true
      end
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
      if buftype == "terminal" then
        _G.terminal_opened = true
      end
    end
  ]])

  local diffview_warning = child.lua_get([[_G.diffview_warning_shown]])
  local terminal_opened = child.lua_get([[_G.terminal_opened]])

  -- One of these should be true (stash diff was triggered via dwim)
  eq(diffview_warning or terminal_opened, true)

  cleanup_repo(child, repo)
end

return T
