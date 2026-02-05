-- End-to-end tests for gitlad.nvim status buffer visibility cycling
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper for truthy assertions
local function assert_truthy(val, msg)
  if not val then
    error(msg or "Expected truthy value, got: " .. tostring(val), 2)
  end
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
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

-- Helper to open gitlad in a repo
local function open_gitlad(child, repo)
  child.cmd("cd " .. repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
end

-- Helper to check if keymap exists
local function has_keymap(child, lhs)
  child.lua(string.format(
    [[
    _G.has_keymap = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == %q then _G.has_keymap = true end
    end
  ]],
    lhs
  ))
  return child.lua_get("_G.has_keymap")
end

-- =============================================================================
-- Keybinding Tests
-- =============================================================================

T["visibility keybindings"] = MiniTest.new_set()

T["visibility keybindings"]["<S-Tab> keymap is set up"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  eq(has_keymap(child, "<S-Tab>"), true, "<S-Tab> should be mapped")
end

T["visibility keybindings"]["1 keymap is set up"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  eq(has_keymap(child, "1"), true, "1 should be mapped")
end

T["visibility keybindings"]["2 keymap is set up"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  eq(has_keymap(child, "2"), true, "2 should be mapped")
end

T["visibility keybindings"]["3 keymap is set up"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  eq(has_keymap(child, "3"), true, "3 should be mapped")
end

T["visibility keybindings"]["4 keymap is set up"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  eq(has_keymap(child, "4"), true, "4 should be mapped")
end

-- =============================================================================
-- Visibility Level Behavior Tests
-- =============================================================================

T["visibility levels"] = MiniTest.new_set()

T["visibility levels"]["default visibility level is 2"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create unpushed commits (need a remote to show unpushed section)
  -- For now, just test with untracked files which always show their items
  helpers.create_file(child, repo, "file.txt", "content")

  open_gitlad(child, repo)

  -- Check visibility level
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    _G.test_level = buffer and buffer.visibility_level or nil
  ]])
  local level = child.lua_get("_G.test_level")
  eq(level, 2, "Default visibility level should be 2")
end

T["visibility levels"]["<S-Tab> toggles all sections"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create more commits to have collapsible sections
  helpers.create_file(child, repo, "file2.txt", "content2")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Second"')

  -- Create a stash to have a collapsible stash section
  helpers.create_file(child, repo, "file3.txt", "content3")
  helpers.git(child, repo, "stash push -m 'test stash'")

  open_gitlad(child, repo)
  helpers.wait_short(child)

  -- Initially no collapsible sections should be collapsed
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _ in pairs(buffer.collapsed_sections) do count = count + 1 end
    _G.test_collapsed_count = count
  ]])
  local initial_collapsed = child.lua_get("_G.test_collapsed_count")
  eq(initial_collapsed, 0, "Initially no sections should be collapsed")

  -- Press <S-Tab> to collapse all collapsible sections
  child.type_keys("<S-Tab>")
  helpers.wait_short(child)

  -- Check that sections are now collapsed
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _, collapsed in pairs(buffer.collapsed_sections) do
      if collapsed then count = count + 1 end
    end
    _G.test_collapsed_count = count
  ]])
  local after_collapse = child.lua_get("_G.test_collapsed_count")
  assert_truthy(after_collapse > 0, "Should have collapsed sections after <S-Tab>")

  -- Press <S-Tab> again to expand all
  child.type_keys("<S-Tab>")
  helpers.wait_short(child)

  -- Check that sections are now expanded
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _, collapsed in pairs(buffer.collapsed_sections) do
      if collapsed then count = count + 1 end
    end
    _G.test_collapsed_count = count
  ]])
  local after_expand = child.lua_get("_G.test_collapsed_count")
  eq(after_expand, 0, "All sections should be expanded after second <S-Tab>")
end

T["visibility levels"]["1 sets level 1 (headers only)"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create commits to have collapsible sections
  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  -- Move to header line for global visibility behavior (not scoped to file)
  child.type_keys("gg")
  helpers.wait_short(child)

  -- Press 1 to set level 1
  child.type_keys("1")
  helpers.wait_short(child, 100)

  child.lua([[
    local status = require("gitlad.ui.views.status")
    _G.test_level = status.get_buffer().visibility_level
  ]])
  local level = child.lua_get("_G.test_level")
  eq(level, 1, "Should be at level 1")
end

T["visibility levels"]["2 sets level 2 (items visible)"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.txt", "content")
  open_gitlad(child, repo)

  -- Move to header line for global visibility behavior
  child.type_keys("gg")
  helpers.wait_short(child)

  -- First set level 1, then level 2
  child.type_keys("1")
  helpers.wait_short(child)
  child.type_keys("2")
  helpers.wait_short(child, 100)

  child.lua([[
    local status = require("gitlad.ui.views.status")
    _G.test_level = status.get_buffer().visibility_level
  ]])
  local level = child.lua_get("_G.test_level")
  eq(level, 2, "Should be at level 2")

  -- Sections should be expanded (collapsed_sections should be empty)
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _ in pairs(buffer.collapsed_sections) do count = count + 1 end
    _G.test_collapsed_count = count
  ]])
  local collapsed_count = child.lua_get("_G.test_collapsed_count")
  eq(collapsed_count, 0, "All sections should be expanded at level 2")
end

T["visibility levels"]["3 shows diff headers only"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create an initial commit
  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify file to create unstaged changes
  helpers.create_file(child, repo, "init.txt", "modified content")

  open_gitlad(child, repo)

  -- Move to header line for global visibility behavior
  child.type_keys("gg")
  helpers.wait_short(child)

  -- Press 3 to show diff headers
  child.type_keys("3")
  helpers.wait_short(child, 100) -- Wait for async diff fetching

  child.lua([[
    local status = require("gitlad.ui.views.status")
    _G.test_level = status.get_buffer().visibility_level
  ]])
  local level = child.lua_get("_G.test_level")
  eq(level, 3, "Should be at level 3")

  -- Check that expanded_files has entries (in headers mode = empty table)
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _ in pairs(buffer.expanded_files) do count = count + 1 end
    _G.test_expanded_count = count
  ]])
  local expanded_count = child.lua_get("_G.test_expanded_count")
  assert_truthy(expanded_count > 0, "Should have expanded files at level 3")

  -- Check that @@ headers are visible but NOT hunk content
  local lines = get_buffer_lines(child)
  local has_diff_header = find_line_with(lines, "@@")
  assert_truthy(has_diff_header, "Should show @@ diff headers at level 3")

  -- Hunk content should NOT be visible (only headers)
  local has_minus_line = find_line_with(lines, "-initial")
  local has_plus_line = find_line_with(lines, "+modified")
  eq(has_minus_line, nil, "Should NOT show hunk content at level 3 (headers only)")
  eq(has_plus_line, nil, "Should NOT show hunk content at level 3 (headers only)")
end

T["visibility levels"]["4 expands everything including hunk content"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create commits
  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify file to create unstaged changes
  helpers.create_file(child, repo, "init.txt", "modified")

  open_gitlad(child, repo)

  -- Move to header line for global visibility behavior
  child.type_keys("gg")
  helpers.wait_short(child)

  -- Press 4 to expand everything
  child.type_keys("4")
  helpers.wait_short(child, 100)

  child.lua([[
    local status = require("gitlad.ui.views.status")
    _G.test_level = status.get_buffer().visibility_level
  ]])
  local level = child.lua_get("_G.test_level")
  eq(level, 4, "Should be at level 4")

  -- Check that expanded_files has entries (set to true = fully expanded)
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _ in pairs(buffer.expanded_files) do count = count + 1 end
    _G.test_expanded_count = count
  ]])
  local expanded_files_count = child.lua_get("_G.test_expanded_count")
  assert_truthy(expanded_files_count > 0, "Should have expanded files at level 4")

  -- Check that full hunk content is visible (not just headers)
  local lines = get_buffer_lines(child)
  local has_diff_header = find_line_with(lines, "@@")
  assert_truthy(has_diff_header, "Should show @@ diff headers at level 4")

  -- Hunk content SHOULD be visible at level 4
  local has_minus_line = find_line_with(lines, "-initial")
  local has_plus_line = find_line_with(lines, "+modified")
  assert_truthy(has_minus_line or has_plus_line, "Should show hunk content at level 4")
end

return T
