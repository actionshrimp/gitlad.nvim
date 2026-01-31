-- End-to-end tests for gitlad.nvim scoped visibility levels (1/2/3/4 keys)
local MiniTest = require("mini.test")
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
  wait(child, 200)
end

-- =============================================================================
-- Scoped Visibility on File Tests
-- =============================================================================

T["scoped visibility on file"] = MiniTest.new_set()

T["scoped visibility on file"]["4 on file line expands only that file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create two files with changes
  create_file(child, repo, "file1.txt", "original1\n")
  create_file(child, repo, "file2.txt", "original2\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify both files
  create_file(child, repo, "file1.txt", "modified1\n")
  create_file(child, repo, "file2.txt", "modified2\n")

  open_gitlad(child, repo)

  -- Cursor should already be on file1 (first item after header)
  -- Check that we're on file1 line
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local info = buffer.line_map[line]
    _G.test_line = line
    _G.test_has_info = info ~= nil
    _G.test_info_type = info and info.type or "none"
    _G.test_info_path = info and info.path or "none"
  ]])
  local line_info_type = child.lua_get("_G.test_info_type")
  local line_info_path = child.lua_get("_G.test_info_path")

  eq(line_info_type, "file", "Should be on a file entry line")
  assert_truthy(line_info_path:find("file"), "Should be on a file path")

  -- Press 4 to fully expand (scoped to this file only)
  child.type_keys("4")
  wait(child, 300)

  -- Verify only the first file is expanded
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    local count = 0
    for _ in pairs(buffer.expanded_files) do count = count + 1 end
    _G.test_expanded_count = count
  ]])
  local expanded_count = child.lua_get("_G.test_expanded_count")

  -- Only one file should be expanded (the one we were on)
  eq(expanded_count, 1, "Only one file should be expanded (scoped to cursor position)")

  -- Verify diff content is visible for file1
  lines = get_buffer_lines(child)
  local has_file1_diff = find_line_with(lines, "+modified1")
  local has_file2_diff = find_line_with(lines, "+modified2")
  assert_truthy(has_file1_diff, "Should show file1 diff content")
  eq(has_file2_diff, nil, "Should NOT show file2 diff content")
end

T["scoped visibility on file"]["1 on file collapses parent section and moves cursor"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create two files with changes
  create_file(child, repo, "file1.txt", "original1\n")
  create_file(child, repo, "file2.txt", "original2\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify both files
  create_file(child, repo, "file1.txt", "modified1\n")
  create_file(child, repo, "file2.txt", "modified2\n")

  open_gitlad(child, repo)

  -- First expand both files
  local lines = get_buffer_lines(child)
  local file1_line = find_line_with(lines, "file1.txt")
  child.cmd(tostring(file1_line))
  child.type_keys("<Tab>") -- Expand file1
  wait(child, 200)

  lines = get_buffer_lines(child)
  local file2_line = find_line_with(lines, "file2.txt")
  child.cmd(tostring(file2_line))
  child.type_keys("<Tab>") -- Expand file2
  wait(child, 200)

  -- Navigate back to file1 and press 1
  -- Since level 1 would hide the file (section collapsed), it should collapse the section
  lines = get_buffer_lines(child)
  file1_line = find_line_with(lines, "file1.txt")
  child.cmd(tostring(file1_line))
  child.type_keys("1")
  wait(child, 200)

  -- Verify the Unstaged section is collapsed (files should not be visible)
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    _G.test_section_collapsed = buffer.collapsed_sections["unstaged"]
  ]])
  local section_collapsed = child.lua_get("_G.test_section_collapsed")

  eq(section_collapsed, true, "Unstaged section should be collapsed")

  -- Verify file lines are not visible in the buffer
  lines = get_buffer_lines(child)
  local file1_visible = find_line_with(lines, "file1.txt")
  local file2_visible = find_line_with(lines, "file2.txt")

  eq(file1_visible, nil, "file1.txt should not be visible when section is collapsed")
  eq(file2_visible, nil, "file2.txt should not be visible when section is collapsed")

  -- Verify cursor moved to section header for easy reopening
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  local section_header_line = find_line_with(lines, "Unstaged")
  eq(cursor_line, section_header_line, "Cursor should move to section header after collapse")

  -- Verify we can easily reopen with Tab
  child.type_keys("<Tab>")
  wait(child, 200)

  lines = get_buffer_lines(child)
  file1_visible = find_line_with(lines, "file1.txt")
  assert_truthy(file1_visible, "file1.txt should be visible after reopening section with Tab")
end

T["scoped visibility on file"]["3 on file shows headers only for that file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file with changes
  create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify file
  create_file(child, repo, "file.txt", "modified1\nmodified2\nmodified3\n")

  open_gitlad(child, repo)

  -- Navigate to file and press 3 for headers-only mode
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("3")
  wait(child, 300)

  -- Verify headers mode
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    _G.test_state = buffer.expanded_files["unstaged:file.txt"]
    _G.test_state_type = type(_G.test_state)
  ]])
  local state_type = child.lua_get("_G.test_state_type")
  eq(state_type, "table", "Should be in headers mode (table)")

  -- Verify @@ header visible but not content
  lines = get_buffer_lines(child)
  local has_header = find_line_with(lines, "@@")
  local has_content = find_line_with(lines, "+modified1")
  assert_truthy(has_header, "Should show @@ header")
  eq(has_content, nil, "Should NOT show hunk content in headers mode")
end

-- =============================================================================
-- Scoped Visibility on Section Header Tests
-- =============================================================================

T["scoped visibility on section"] = MiniTest.new_set()

T["scoped visibility on section"]["4 on section header expands all files in section"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create files with changes
  create_file(child, repo, "file1.txt", "original1\n")
  create_file(child, repo, "file2.txt", "original2\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify both files
  create_file(child, repo, "file1.txt", "modified1\n")
  create_file(child, repo, "file2.txt", "modified2\n")

  open_gitlad(child, repo)

  -- Navigate to Unstaged section header
  local lines = get_buffer_lines(child)
  local section_line = find_line_with(lines, "Unstaged")
  assert_truthy(section_line, "Should find Unstaged section header")
  child.cmd(tostring(section_line))

  -- Press 4 to fully expand all files in section
  child.type_keys("4")
  wait(child, 300)

  -- Verify both files are expanded
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    _G.test_file1_state = buffer.expanded_files["unstaged:file1.txt"]
    _G.test_file2_state = buffer.expanded_files["unstaged:file2.txt"]
  ]])
  local file1_state = child.lua_get("_G.test_file1_state")
  local file2_state = child.lua_get("_G.test_file2_state")

  eq(file1_state, true, "file1.txt should be fully expanded")
  eq(file2_state, true, "file2.txt should be fully expanded")

  -- Verify both diffs are visible
  lines = get_buffer_lines(child)
  local has_file1_diff = find_line_with(lines, "+modified1")
  local has_file2_diff = find_line_with(lines, "+modified2")
  assert_truthy(has_file1_diff, "Should show file1 diff content")
  assert_truthy(has_file2_diff, "Should show file2 diff content")
end

T["scoped visibility on section"]["1 on section header collapses all files in section"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create files with changes
  create_file(child, repo, "file1.txt", "original1\n")
  create_file(child, repo, "file2.txt", "original2\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify both files
  create_file(child, repo, "file1.txt", "modified1\n")
  create_file(child, repo, "file2.txt", "modified2\n")

  open_gitlad(child, repo)

  -- Expand both files first
  local lines = get_buffer_lines(child)
  local file1_line = find_line_with(lines, "file1.txt")
  child.cmd(tostring(file1_line))
  child.type_keys("<Tab>")
  wait(child, 200)

  lines = get_buffer_lines(child)
  local file2_line = find_line_with(lines, "file2.txt")
  child.cmd(tostring(file2_line))
  child.type_keys("<Tab>")
  wait(child, 200)

  -- Navigate to section header and press 1
  lines = get_buffer_lines(child)
  local section_line = find_line_with(lines, "Unstaged")
  child.cmd(tostring(section_line))
  child.type_keys("1")
  wait(child, 200)

  -- Verify both files are collapsed
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    _G.test_file1_state = buffer.expanded_files["unstaged:file1.txt"]
    _G.test_file2_state = buffer.expanded_files["unstaged:file2.txt"]
  ]])
  local file1_state = child.lua_get("_G.test_file1_state")
  local file2_state = child.lua_get("_G.test_file2_state")

  eq(file1_state, false, "file1.txt should be collapsed")
  eq(file2_state, false, "file2.txt should be collapsed")
end

-- =============================================================================
-- Global Visibility Tests (when not on file/section)
-- =============================================================================

T["global visibility"] = MiniTest.new_set()

T["global visibility"]["1/2/3/4 on header applies globally"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file with changes
  create_file(child, repo, "file.txt", "original\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')
  create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo)

  -- Position cursor on the Head: line (global context)
  child.cmd("1") -- Go to first line
  wait(child, 100)

  -- Press 4 to expand globally
  child.type_keys("4")
  wait(child, 300)

  -- Verify file is expanded and visibility level changed
  child.lua([[
    local status = require("gitlad.ui.views.status")
    local buffer = status.get_buffer()
    _G.test_level = buffer.visibility_level
    _G.test_file_state = buffer.expanded_files["unstaged:file.txt"]
  ]])
  local level = child.lua_get("_G.test_level")
  local file_state = child.lua_get("_G.test_file_state")

  eq(level, 4, "Visibility level should be 4")
  eq(file_state, true, "File should be fully expanded")
end

return T
