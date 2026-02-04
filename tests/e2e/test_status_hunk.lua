-- End-to-end tests for gitlad.nvim diff expansion, hunk staging, and visual selection
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

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

-- =============================================================================
-- Diff Expansion Tests
-- =============================================================================

T["diff expansion"] = MiniTest.new_set()

T["diff expansion"]["TAB expands diff for modified file"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and commit a file with multiple lines
  helpers.create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify the file
  helpers.create_file(child, repo, "file.txt", "line1\nline2 modified\nline3\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Check that diff lines are shown
  lines = get_buffer_lines(child)
  local has_diff_header = find_line_with(lines, "@@")
  local has_minus_line = find_line_with(lines, "-line2")
  local has_plus_line = find_line_with(lines, "+line2 modified")

  assert_truthy(has_diff_header, "Should show @@ diff header")
  assert_truthy(has_minus_line, "Should show removed line")
  assert_truthy(has_plus_line, "Should show added line")
end

T["diff expansion"]["TAB collapses expanded diff"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and commit a file
  helpers.create_file(child, repo, "file.txt", "original\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify the file
  helpers.create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (2-state toggle: collapsed <-> expanded)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- First TAB: fully expanded
  helpers.wait_short(child, 100)

  -- Verify diff shown
  lines = get_buffer_lines(child)
  local has_diff = find_line_with(lines, "@@")
  assert_truthy(has_diff, "Should show @@ header after first TAB")

  -- Second TAB: collapse
  child.type_keys("<Tab>")
  helpers.wait_short(child)

  -- Verify collapsed
  lines = get_buffer_lines(child)
  has_diff = find_line_with(lines, "@@")
  eq(has_diff, nil, "Should not show diff after second TAB (collapsed)")
end

T["diff expansion"]["shows content for untracked file"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create untracked file
  helpers.create_file(child, repo, "new.txt", "line1\nline2\nline3\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Check that file content is shown
  lines = get_buffer_lines(child)
  local has_line1 = find_line_with(lines, "line1")
  local has_line2 = find_line_with(lines, "line2")

  assert_truthy(has_line1, "Should show line1 from untracked file")
  assert_truthy(has_line2, "Should show line2 from untracked file")
end

-- =============================================================================
-- Hunk Staging Tests
-- =============================================================================

T["hunk staging"] = MiniTest.new_set()

T["hunk staging"]["s on diff line stages single hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file with multiple sections that will create multiple hunks
  local original = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n"
  helpers.create_file(child, repo, "file.txt", original)
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify to create two separate hunks
  local modified =
    "line1 modified\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10 modified\n"
  helpers.create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Find the first hunk's diff line and stage it
  lines = get_buffer_lines(child)
  local first_hunk_line = find_line_with(lines, "+line1 modified")
  assert_truthy(first_hunk_line, "Should find first hunk line")

  child.cmd(tostring(first_hunk_line))
  child.type_keys("s")
  helpers.wait_short(child, 150)

  -- Verify: file should now appear in both staged and unstaged
  -- (first hunk staged, second hunk still unstaged)
  local status = helpers.git(child, repo, "status --porcelain")
  assert_truthy(
    status:find("MM file.txt"),
    "File should show MM status (staged + unstaged changes)"
  )
end

T["hunk staging"]["u on diff line unstages single hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file
  helpers.create_file(child, repo, "file.txt", "original line\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify and stage
  helpers.create_file(child, repo, "file.txt", "modified line\n")
  helpers.git(child, repo, "add file.txt")

  open_gitlad(child, repo)

  -- Expand the staged diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Find a diff line and unstage
  lines = get_buffer_lines(child)
  local diff_line = find_line_with(lines, "+modified")
  assert_truthy(diff_line, "Should find diff line")

  child.cmd(tostring(diff_line))
  child.type_keys("u")
  helpers.wait_short(child, 150)

  -- Verify file is now unstaged
  local status = helpers.git(child, repo, "status --porcelain")
  assert_truthy(status:find(" M file.txt"), "File should show unstaged modified status")
end

-- =============================================================================
-- Visual Selection Hunk Tests
-- =============================================================================

T["visual selection"] = MiniTest.new_set()

T["visual selection"]["stages selected lines from hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file
  helpers.create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify multiple lines
  helpers.create_file(child, repo, "file.txt", "line1 changed\nline2 changed\nline3\n")

  open_gitlad(child, repo)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Find the first changed line
  lines = get_buffer_lines(child)
  local first_plus = find_line_with(lines, "+line1 changed")
  assert_truthy(first_plus, "Should find +line1 changed")

  -- Visually select just the first line and stage it
  child.cmd(tostring(first_plus))
  child.type_keys("V", "s")
  helpers.wait_short(child, 150)

  -- Verify partial staging occurred
  local status = helpers.git(child, repo, "status --porcelain")
  -- File should have both staged and unstaged changes (MM)
  assert_truthy(status:find("MM file.txt"), "File should have partial staging (MM status)")
end

T["visual selection"]["unstages selected lines from staged hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file
  helpers.create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify and stage all changes
  helpers.create_file(child, repo, "file.txt", "line1 changed\nline2 changed\nline3\n")
  helpers.git(child, repo, "add file.txt")

  open_gitlad(child, repo)

  -- Expand the staged diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Find the first changed line
  lines = get_buffer_lines(child)
  local first_plus = find_line_with(lines, "+line1 changed")
  assert_truthy(first_plus, "Should find +line1 changed")

  -- Visually select just the first line and unstage it
  child.cmd(tostring(first_plus))
  child.type_keys("V", "u")
  helpers.wait_short(child, 150)

  -- Verify partial unstaging occurred
  local status = helpers.git(child, repo, "status --porcelain")
  -- File should have both staged and unstaged changes (MM)
  assert_truthy(
    status:find("MM file.txt"),
    "File should have partial staging after unstage (MM status)"
  )
end

T["visual selection"]["stages multiple selected lines"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file with more lines
  helpers.create_file(child, repo, "file.txt", "a\nb\nc\nd\ne\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify lines b, c, d
  helpers.create_file(child, repo, "file.txt", "a\nB\nC\nD\ne\n")

  open_gitlad(child, repo)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Find the +B line and select B and C (but not D)
  lines = get_buffer_lines(child)
  local plus_b = find_line_with(lines, "+B")
  local plus_c = find_line_with(lines, "+C")
  assert_truthy(plus_b, "Should find +B")
  assert_truthy(plus_c, "Should find +C")

  -- Select from +B to +C and stage
  child.cmd(tostring(plus_b))
  child.type_keys("V")
  child.cmd(tostring(plus_c))
  child.type_keys("s")
  helpers.wait_short(child, 150)

  -- Verify partial staging - should have MM status
  local status = helpers.git(child, repo, "status --porcelain")
  assert_truthy(status:find("MM file.txt"), "File should have partial staging (MM status)")

  -- Verify staged diff contains B and C but D is still in working copy
  local staged_diff = helpers.git(child, repo, "diff --cached file.txt")
  assert_truthy(staged_diff:find("+B"), "Staged diff should contain +B")
  assert_truthy(staged_diff:find("+C"), "Staged diff should contain +C")

  local unstaged_diff = helpers.git(child, repo, "diff file.txt")
  assert_truthy(unstaged_diff:find("+D"), "Unstaged diff should still contain +D")
end

-- =============================================================================
-- Hunk Navigation Tests
-- =============================================================================

T["hunk navigation"] = MiniTest.new_set()

T["hunk navigation"]["<CR> on diff line jumps to file at correct line"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file with multiple lines and commit it
  local content =
    "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\n"
  helpers.create_file(child, repo, "file.txt", content)
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Modify lines 5-7 to create a change
  local modified =
    "line 1\nline 2\nline 3\nline 4\nmodified 5\nmodified 6\nmodified 7\nline 8\nline 9\nline 10\n"
  helpers.create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Cursor should already be on the unstaged file (first item)
  -- Expand the diff (single TAB for 2-state toggle)
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 150)

  -- Move down to a diff line (should be on a + line)
  -- Navigate down several lines to get into the diff content
  child.type_keys("jjjj")
  helpers.wait_short(child)

  -- Press <CR> to jump to file
  child.type_keys("<CR>")
  helpers.wait_short(child, 100)

  -- Verify we're now in file.txt
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  assert_truthy(buf_name:find("file.txt"), "Should be in file.txt buffer")

  -- Verify cursor is around line 5-7 (the modified lines)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(
    cursor_line >= 4 and cursor_line <= 8,
    "Cursor should be around modified lines (4-8), got: " .. cursor_line
  )
end

T["hunk navigation"]["<CR> on hunk header jumps to hunk start line"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file with many lines
  local content = ""
  for i = 1, 20 do
    content = content .. "line " .. i .. "\n"
  end
  helpers.create_file(child, repo, "file.txt", content)
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Modify line 15
  local modified = ""
  for i = 1, 20 do
    if i == 15 then
      modified = modified .. "modified line 15\n"
    else
      modified = modified .. "line " .. i .. "\n"
    end
  end
  helpers.create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Cursor should already be on file (first item)
  -- Expand the file
  child.type_keys("<Tab>")
  helpers.wait_short(child, 150)

  -- Move down once to get to the @@ header line
  child.type_keys("j")
  helpers.wait_short(child)

  -- Get current line content to verify we're on @@ line
  local lines = get_buffer_lines(child)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  local current_line = lines[cursor_line]
  assert_truthy(current_line:match("^@@"), "Should be on @@ header line")

  -- Press <CR> to jump to file
  child.type_keys("<CR>")
  helpers.wait_short(child, 100)

  -- Verify we're in file.txt
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  assert_truthy(buf_name:find("file.txt"), "Should be in file.txt buffer")

  -- Cursor should be around line 15 (where the change is)
  cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(
    cursor_line >= 12 and cursor_line <= 16,
    "Cursor should be around line 15, got: " .. cursor_line
  )
end

-- =============================================================================
-- Expansion Memory Tests
-- =============================================================================

T["expansion memory"] = MiniTest.new_set()

T["expansion memory"]["re-expanding file restores remembered hunk state"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file with multiple sections to get multiple hunks
  local original = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n"
  helpers.create_file(child, repo, "file.txt", original)
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify to create two separate hunks
  local modified =
    "line1 modified\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10 modified\n"
  helpers.create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Navigate to file and expand
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- Expand (fully expanded by default)
  helpers.wait_short(child, 100)

  -- Verify both hunks are visible
  lines = get_buffer_lines(child)
  local first_hunk = find_line_with(lines, "+line1 modified")
  local second_hunk = find_line_with(lines, "+line10 modified")
  assert_truthy(first_hunk, "First hunk should be visible")
  assert_truthy(second_hunk, "Second hunk should be visible")

  -- Collapse the file
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
  helpers.wait_short(child)

  -- Verify collapsed
  lines = get_buffer_lines(child)
  local has_hunk = find_line_with(lines, "+line1")
  eq(has_hunk, nil, "Should be collapsed (no hunk visible)")

  -- Re-expand the file
  child.type_keys("<Tab>")
  helpers.wait_short(child, 100)

  -- Verify both hunks are still visible (remembered state restored)
  lines = get_buffer_lines(child)
  first_hunk = find_line_with(lines, "+line1 modified")
  second_hunk = find_line_with(lines, "+line10 modified")
  assert_truthy(first_hunk, "First hunk should be visible after re-expand")
  assert_truthy(second_hunk, "Second hunk should be visible after re-expand")
end

T["expansion memory"]["defaults to fully expanded when no remembered state"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and commit a file
  helpers.create_file(child, repo, "file.txt", "original\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify the file
  helpers.create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (first time, no remembered state)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- Expand
  helpers.wait_short(child, 100)

  -- Verify fully expanded (diff content visible, not just headers)
  lines = get_buffer_lines(child)
  local has_diff_header = find_line_with(lines, "@@")
  local has_content = find_line_with(lines, "+modified")

  assert_truthy(has_diff_header, "Should show @@ header")
  assert_truthy(has_content, "Should show diff content (fully expanded by default)")
end

-- =============================================================================
-- Hunk Discard Tests
-- =============================================================================

T["hunk discard"] = MiniTest.new_set()

-- Helper to get file contents from repo
local function read_file_content(child, repo, filename)
  local path = repo .. "/" .. filename
  return child.lua_get(string.format("vim.fn.join(vim.fn.readfile(%q), '\\n') .. '\\n'", path))
end

-- Helper to mock vim.ui.select to auto-confirm Yes
local function mock_ui_select_yes(child)
  child.lua([[
    _G.original_ui_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      -- Auto-select "Yes" (first item)
      on_choice("Yes")
    end
  ]])
end

-- Helper to restore vim.ui.select
local function restore_ui_select(child)
  child.lua([[
    if _G.original_ui_select then
      vim.ui.select = _G.original_ui_select
    end
  ]])
end

T["hunk discard"]["x on diff line discards single hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file with multiple sections that will create multiple hunks
  local original = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n"
  helpers.create_file(child, repo, "file.txt", original)
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify to create two separate hunks
  local modified =
    "line1 modified\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10 modified\n"
  helpers.create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Mock vim.ui.select to auto-confirm
  mock_ui_select_yes(child)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  helpers.wait_short(child, 100)

  -- Find the first hunk's diff line and discard it
  lines = get_buffer_lines(child)
  local first_hunk_line = find_line_with(lines, "+line1 modified")
  assert_truthy(first_hunk_line, "Should find first hunk line")

  child.cmd(tostring(first_hunk_line))
  child.type_keys("x")
  helpers.wait_short(child, 150)

  restore_ui_select(child)

  -- Verify: first hunk should be discarded, second hunk should remain
  local content = read_file_content(child, repo, "file.txt")
  assert_truthy(content:find("line1\n"), "First line should be reverted to original")
  assert_truthy(not content:find("line1 modified"), "First modified line should be gone")
  assert_truthy(content:find("line10 modified"), "Second modified line should still be present")
end

T["hunk discard"]["x on file discards whole file when not on hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and modify a file
  helpers.create_file(child, repo, "file.txt", "original\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')
  helpers.create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo)

  -- Mock vim.ui.select to auto-confirm
  mock_ui_select_yes(child)

  -- Don't expand - stay on file line
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))

  child.type_keys("x")
  helpers.wait_short(child, 150)

  restore_ui_select(child)

  -- Verify file is back to original
  local content = read_file_content(child, repo, "file.txt")
  eq(content, "original\n")
end

T["hunk discard"]["visual selection discards single line from hunk"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file
  helpers.create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Add multiple new lines that will be in same hunk
  helpers.create_file(child, repo, "file.txt", "line1\nnew1\nnew2\nline2\nline3\n")

  open_gitlad(child, repo)

  -- Mock vim.ui.select to auto-confirm
  mock_ui_select_yes(child)

  -- Expand the diff
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
  helpers.wait_short(child, 100)

  -- Find the first new line
  lines = get_buffer_lines(child)
  local new1_line = find_line_with(lines, "+new1")
  assert_truthy(new1_line, "Should find +new1")

  -- Visual select just new1 and discard it
  child.cmd(tostring(new1_line))
  child.type_keys("V", "x")
  helpers.wait_short(child, 150)

  restore_ui_select(child)

  -- Verify: new1 should be gone, but new2 should remain
  local content = read_file_content(child, repo, "file.txt")
  assert_truthy(not content:find("new1"), "new1 should be discarded")
  assert_truthy(content:find("new2"), "new2 should still be present")
end

T["hunk discard"]["cannot discard staged changes"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create, modify, and stage
  helpers.create_file(child, repo, "file.txt", "original\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')
  helpers.create_file(child, repo, "file.txt", "modified\n")
  helpers.git(child, repo, "add file.txt")

  open_gitlad(child, repo)

  -- Find the staged file
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))

  -- Expand and try to discard
  child.type_keys("<Tab>")
  helpers.wait_short(child, 100)
  lines = get_buffer_lines(child)
  local diff_line = find_line_with(lines, "+modified")
  if diff_line then
    child.cmd(tostring(diff_line))
  end

  child.type_keys("x")
  helpers.wait_short(child, 100)

  -- File should still be staged (discard blocked)
  local status = helpers.git(child, repo, "status --porcelain")
  assert_truthy(
    status:find("M  file.txt") or status:find("A  file.txt"),
    "File should still be staged"
  )
end

-- =============================================================================
-- Visual Selection Staging for Untracked Files
-- =============================================================================

T["visual selection untracked"] = MiniTest.new_set()

T["visual selection untracked"]["stages selected lines from untracked file"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "init.txt", "initial")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create an untracked file with multiple lines
  helpers.create_file(child, repo, "new.txt", "line1\nline2\nline3\nline4\nline5\n")

  open_gitlad(child, repo)

  -- Navigate to the untracked file and expand it
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  assert_truthy(file_line, "Should find new.txt")
  child.cmd(tostring(file_line))

  -- Expand to see the diff
  child.type_keys("<Tab>")
  helpers.wait_short(child, 100)

  -- Find lines to select (we'll select line1 and line2 but not line3-5)
  lines = get_buffer_lines(child)
  local plus_line1 = find_line_with(lines, "+line1")
  local plus_line2 = find_line_with(lines, "+line2")
  assert_truthy(plus_line1, "Should find +line1")
  assert_truthy(plus_line2, "Should find +line2")

  -- Visual select lines 1-2 and stage them
  child.cmd(tostring(plus_line1))
  child.type_keys("V")
  child.cmd(tostring(plus_line2))
  child.type_keys("s")
  helpers.wait_short(child, 200) -- Extra wait for intent-to-add + apply patch

  -- Verify partial staging occurred:
  -- - git add -N was run first
  -- - Then partial patch was applied
  -- File should have both staged (line1, line2) and unstaged (line3, line4, line5) changes
  local status = helpers.git(child, repo, "status --porcelain")
  -- Should be AM (Added in index with modifications in worktree)
  assert_truthy(status:find("AM new.txt"), "File should have partial staging (AM status)")

  -- Verify staged diff contains line1 and line2
  local staged_diff = helpers.git(child, repo, "diff --cached new.txt")
  assert_truthy(staged_diff:find("+line1"), "Staged diff should contain +line1")
  assert_truthy(staged_diff:find("+line2"), "Staged diff should contain +line2")

  -- Verify unstaged diff contains line3, line4, line5 (but not line1, line2)
  local unstaged_diff = helpers.git(child, repo, "diff new.txt")
  assert_truthy(unstaged_diff:find("+line3"), "Unstaged diff should contain +line3")
  assert_truthy(unstaged_diff:find("+line4"), "Unstaged diff should contain +line4")
  assert_truthy(unstaged_diff:find("+line5"), "Unstaged diff should contain +line5")
end

return T
