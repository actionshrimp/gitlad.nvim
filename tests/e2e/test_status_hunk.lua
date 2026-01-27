-- End-to-end tests for gitlad.nvim diff expansion, hunk staging, and visual selection
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
-- Diff Expansion Tests
-- =============================================================================

T["diff expansion"] = MiniTest.new_set()

T["diff expansion"]["TAB expands diff for modified file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file with multiple lines
  create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify the file
  create_file(child, repo, "file.txt", "line1\nline2 modified\nline3\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

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
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "file.txt", "original\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify the file
  create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (2-state toggle: collapsed <-> expanded)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- First TAB: fully expanded
  wait(child, 200)

  -- Verify diff shown
  lines = get_buffer_lines(child)
  local has_diff = find_line_with(lines, "@@")
  assert_truthy(has_diff, "Should show @@ header after first TAB")

  -- Second TAB: collapse
  child.type_keys("<Tab>")
  wait(child, 100)

  -- Verify collapsed
  lines = get_buffer_lines(child)
  has_diff = find_line_with(lines, "@@")
  eq(has_diff, nil, "Should not show diff after second TAB (collapsed)")
end

T["diff expansion"]["shows content for untracked file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked file
  create_file(child, repo, "new.txt", "line1\nline2\nline3\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

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
  local repo = create_test_repo(child)

  -- Create a file with multiple sections that will create multiple hunks
  local original = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n"
  create_file(child, repo, "file.txt", original)
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify to create two separate hunks
  local modified =
    "line1 modified\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10 modified\n"
  create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

  -- Find the first hunk's diff line and stage it
  lines = get_buffer_lines(child)
  local first_hunk_line = find_line_with(lines, "+line1 modified")
  assert_truthy(first_hunk_line, "Should find first hunk line")

  child.cmd(tostring(first_hunk_line))
  child.type_keys("s")
  wait(child, 300)

  -- Verify: file should now appear in both staged and unstaged
  -- (first hunk staged, second hunk still unstaged)
  local status = git(child, repo, "status --porcelain")
  assert_truthy(
    status:find("MM file.txt"),
    "File should show MM status (staged + unstaged changes)"
  )
end

T["hunk staging"]["u on diff line unstages single hunk"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file
  create_file(child, repo, "file.txt", "original line\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify and stage
  create_file(child, repo, "file.txt", "modified line\n")
  git(child, repo, "add file.txt")

  open_gitlad(child, repo)

  -- Expand the staged diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

  -- Find a diff line and unstage
  lines = get_buffer_lines(child)
  local diff_line = find_line_with(lines, "+modified")
  assert_truthy(diff_line, "Should find diff line")

  child.cmd(tostring(diff_line))
  child.type_keys("u")
  wait(child, 300)

  -- Verify file is now unstaged
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find(" M file.txt"), "File should show unstaged modified status")
end

-- =============================================================================
-- Visual Selection Hunk Tests
-- =============================================================================

T["visual selection"] = MiniTest.new_set()

T["visual selection"]["stages selected lines from hunk"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file
  create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify multiple lines
  create_file(child, repo, "file.txt", "line1 changed\nline2 changed\nline3\n")

  open_gitlad(child, repo)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

  -- Find the first changed line
  lines = get_buffer_lines(child)
  local first_plus = find_line_with(lines, "+line1 changed")
  assert_truthy(first_plus, "Should find +line1 changed")

  -- Visually select just the first line and stage it
  child.cmd(tostring(first_plus))
  child.type_keys("V", "s")
  wait(child, 300)

  -- Verify partial staging occurred
  local status = git(child, repo, "status --porcelain")
  -- File should have both staged and unstaged changes (MM)
  assert_truthy(status:find("MM file.txt"), "File should have partial staging (MM status)")
end

T["visual selection"]["unstages selected lines from staged hunk"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file
  create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify and stage all changes
  create_file(child, repo, "file.txt", "line1 changed\nline2 changed\nline3\n")
  git(child, repo, "add file.txt")

  open_gitlad(child, repo)

  -- Expand the staged diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

  -- Find the first changed line
  lines = get_buffer_lines(child)
  local first_plus = find_line_with(lines, "+line1 changed")
  assert_truthy(first_plus, "Should find +line1 changed")

  -- Visually select just the first line and unstage it
  child.cmd(tostring(first_plus))
  child.type_keys("V", "u")
  wait(child, 300)

  -- Verify partial unstaging occurred
  local status = git(child, repo, "status --porcelain")
  -- File should have both staged and unstaged changes (MM)
  assert_truthy(
    status:find("MM file.txt"),
    "File should have partial staging after unstage (MM status)"
  )
end

T["visual selection"]["stages multiple selected lines"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file with more lines
  create_file(child, repo, "file.txt", "a\nb\nc\nd\ne\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify lines b, c, d
  create_file(child, repo, "file.txt", "a\nB\nC\nD\ne\n")

  open_gitlad(child, repo)

  -- Expand the diff (single TAB for 2-state toggle)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 200)

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
  wait(child, 300)

  -- Verify partial staging - should have MM status
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("MM file.txt"), "File should have partial staging (MM status)")

  -- Verify staged diff contains B and C but D is still in working copy
  local staged_diff = git(child, repo, "diff --cached file.txt")
  assert_truthy(staged_diff:find("+B"), "Staged diff should contain +B")
  assert_truthy(staged_diff:find("+C"), "Staged diff should contain +C")

  local unstaged_diff = git(child, repo, "diff file.txt")
  assert_truthy(unstaged_diff:find("+D"), "Unstaged diff should still contain +D")
end

-- =============================================================================
-- Hunk Navigation Tests
-- =============================================================================

T["hunk navigation"] = MiniTest.new_set()

T["hunk navigation"]["<CR> on diff line jumps to file at correct line"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create a file with multiple lines and commit it
  local content =
    "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\n"
  create_file(child, repo, "file.txt", content)
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Modify lines 5-7 to create a change
  local modified =
    "line 1\nline 2\nline 3\nline 4\nmodified 5\nmodified 6\nmodified 7\nline 8\nline 9\nline 10\n"
  create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Navigate to the unstaged file
  child.type_keys("gj")
  wait(child, 100)

  -- Expand the diff (single TAB for 2-state toggle)
  child.type_keys("<Tab>") -- TAB: fully expanded (2-state toggle)
  wait(child, 300)

  -- Move down to a diff line (should be on a + line)
  -- Navigate down several lines to get into the diff content
  child.type_keys("jjjj")
  wait(child, 100)

  -- Press <CR> to jump to file
  child.type_keys("<CR>")
  wait(child, 200)

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
  local repo = create_test_repo(child)

  -- Create a file with many lines
  local content = ""
  for i = 1, 20 do
    content = content .. "line " .. i .. "\n"
  end
  create_file(child, repo, "file.txt", content)
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Modify line 15
  local modified = ""
  for i = 1, 20 do
    if i == 15 then
      modified = modified .. "modified line 15\n"
    else
      modified = modified .. "line " .. i .. "\n"
    end
  end
  create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Navigate to file and expand
  child.type_keys("gj")
  wait(child, 100)
  child.type_keys("<Tab>")
  wait(child, 300)

  -- Move down once to get to the @@ header line
  child.type_keys("j")
  wait(child, 100)

  -- Get current line content to verify we're on @@ line
  local lines = get_buffer_lines(child)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  local current_line = lines[cursor_line]
  assert_truthy(current_line:match("^@@"), "Should be on @@ header line")

  -- Press <CR> to jump to file
  child.type_keys("<CR>")
  wait(child, 200)

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
  local repo = create_test_repo(child)

  -- Create a file with multiple sections to get multiple hunks
  local original = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n"
  create_file(child, repo, "file.txt", original)
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify to create two separate hunks
  local modified =
    "line1 modified\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10 modified\n"
  create_file(child, repo, "file.txt", modified)

  open_gitlad(child, repo)

  -- Navigate to file and expand
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- Expand (fully expanded by default)
  wait(child, 200)

  -- Verify both hunks are visible
  lines = get_buffer_lines(child)
  local first_hunk = find_line_with(lines, "+line1 modified")
  local second_hunk = find_line_with(lines, "+line10 modified")
  assert_truthy(first_hunk, "First hunk should be visible")
  assert_truthy(second_hunk, "Second hunk should be visible")

  -- Collapse the file
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
  wait(child, 100)

  -- Verify collapsed
  lines = get_buffer_lines(child)
  local has_hunk = find_line_with(lines, "+line1")
  eq(has_hunk, nil, "Should be collapsed (no hunk visible)")

  -- Re-expand the file
  child.type_keys("<Tab>")
  wait(child, 200)

  -- Verify both hunks are still visible (remembered state restored)
  lines = get_buffer_lines(child)
  first_hunk = find_line_with(lines, "+line1 modified")
  second_hunk = find_line_with(lines, "+line10 modified")
  assert_truthy(first_hunk, "First hunk should be visible after re-expand")
  assert_truthy(second_hunk, "Second hunk should be visible after re-expand")
end

T["expansion memory"]["defaults to fully expanded when no remembered state"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "file.txt", "original\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify the file
  create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo)

  -- Navigate to file and expand (first time, no remembered state)
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>") -- Expand
  wait(child, 200)

  -- Verify fully expanded (diff content visible, not just headers)
  lines = get_buffer_lines(child)
  local has_diff_header = find_line_with(lines, "@@")
  local has_content = find_line_with(lines, "+modified")

  assert_truthy(has_diff_header, "Should show @@ header")
  assert_truthy(has_content, "Should show diff content (fully expanded by default)")
end

return T
