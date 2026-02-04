-- End-to-end tests for gitlad.nvim file and section staging
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
-- Staging/Unstaging Files Tests
-- =============================================================================

T["staging files"] = MiniTest.new_set()

T["staging files"]["s stages untracked file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked file
  create_file(child, repo, "new.txt", "new content")

  open_gitlad(child, repo)

  -- Navigate to the untracked file and stage it
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  assert_truthy(file_line, "Should find new.txt")

  -- Go to that line and press 's' to stage
  child.cmd(tostring(file_line))
  child.type_keys("s")
  wait(child, 200)

  -- Verify file moved to staged section
  lines = get_buffer_lines(child)
  local staged_section = find_line_with(lines, "Staged")
  local untracked_section = find_line_with(lines, "Untracked")

  -- new.txt should be in staged now
  local new_line = find_line_with(lines, "new.txt")
  assert_truthy(staged_section, "Should have Staged section")
  assert_truthy(new_line and new_line > staged_section, "new.txt should be in staged section")

  -- Verify git state
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("A  new.txt"), "Git should show file as staged (A)")
end

T["staging files"]["s stages unstaged modified file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "file.txt", "original")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify without staging
  create_file(child, repo, "file.txt", "modified")

  open_gitlad(child, repo)

  -- Navigate to the file and stage it
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("s")
  wait(child, 200)

  -- Verify git state
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("M  file.txt"), "Git should show file as staged modified (M)")
end

T["staging files"]["u unstages staged file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage a new file
  create_file(child, repo, "staged.txt", "content")
  git(child, repo, "add staged.txt")

  open_gitlad(child, repo)

  -- Navigate to the staged file and unstage it
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "staged.txt")
  child.cmd(tostring(file_line))
  child.type_keys("u")
  wait(child, 200)

  -- Verify file moved to untracked section
  lines = get_buffer_lines(child)
  local untracked_section = find_line_with(lines, "Untracked")
  local file_new_line = find_line_with(lines, "staged.txt")

  assert_truthy(untracked_section, "Should have Untracked section")
  assert_truthy(
    file_new_line and file_new_line > untracked_section,
    "staged.txt should be in untracked section"
  )

  -- Verify git state
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("%?%? staged.txt"), "Git should show file as untracked (??)")
end

T["staging files"]["maintains sort order after staging"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage two files to have existing staged section
  create_file(child, repo, "aaa.txt", "a")
  create_file(child, repo, "zzz.txt", "z")
  git(child, repo, "add aaa.txt zzz.txt")

  -- Create an untracked file that should go in the middle alphabetically
  create_file(child, repo, "mmm.txt", "m")

  open_gitlad(child, repo)

  -- Stage mmm.txt
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "mmm.txt")
  child.cmd(tostring(file_line))
  child.type_keys("s")
  wait(child, 200)

  -- Verify sort order in staged section
  lines = get_buffer_lines(child)
  local aaa_line = find_line_with(lines, "aaa.txt")
  local mmm_line = find_line_with(lines, "mmm.txt")
  local zzz_line = find_line_with(lines, "zzz.txt")

  assert_truthy(aaa_line < mmm_line, "aaa.txt should come before mmm.txt")
  assert_truthy(mmm_line < zzz_line, "mmm.txt should come before zzz.txt")
end

T["staging files"]["S stages all files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create multiple untracked and modified files
  create_file(child, repo, "new1.txt", "new1")
  create_file(child, repo, "new2.txt", "new2")
  create_file(child, repo, "init.txt", "modified")

  open_gitlad(child, repo)

  -- Press S to stage all
  child.type_keys("S")
  wait(child, 200)

  -- Verify all files are staged
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("A  new1.txt"), "new1.txt should be staged")
  assert_truthy(status:find("A  new2.txt"), "new2.txt should be staged")
  assert_truthy(status:find("M  init.txt"), "init.txt should be staged")
end

T["staging files"]["U unstages all files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage multiple files
  create_file(child, repo, "new1.txt", "new1")
  create_file(child, repo, "new2.txt", "new2")
  git(child, repo, "add .")

  open_gitlad(child, repo)

  -- Press U to unstage all
  child.type_keys("U")
  wait(child, 200)

  -- Verify all files are unstaged
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("%?%? new1.txt"), "new1.txt should be untracked")
  assert_truthy(status:find("%?%? new2.txt"), "new2.txt should be untracked")
end

T["staging files"]["shows mixed staged and unstaged for same file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "mixed.txt", "line1\nline2\nline3\n")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage a modification
  create_file(child, repo, "mixed.txt", "line1\nline2 modified\nline3\n")
  git(child, repo, "add mixed.txt")

  -- Make another unstaged modification
  create_file(child, repo, "mixed.txt", "line1\nline2 modified\nline3 also modified\n")

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)

  -- File should appear in both sections
  local staged_section = find_line_with(lines, "Staged")
  local unstaged_section = find_line_with(lines, "Unstaged")

  assert_truthy(staged_section, "Should have Staged section")
  assert_truthy(unstaged_section, "Should have Unstaged section")

  -- Count occurrences of mixed.txt
  local count = 0
  for _, line in ipairs(lines) do
    if line:find("mixed.txt", 1, true) then
      count = count + 1
    end
  end
  eq(count, 2, "mixed.txt should appear in both staged and unstaged sections")
end

-- =============================================================================
-- Section-Level Staging Tests
-- =============================================================================

T["section staging"] = MiniTest.new_set()

T["section staging"]["s on Untracked header stages all untracked files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create multiple untracked files
  create_file(child, repo, "new1.txt", "content1")
  create_file(child, repo, "new2.txt", "content2")
  create_file(child, repo, "new3.txt", "content3")

  open_gitlad(child, repo)

  -- Find and go to the Untracked section header
  local lines = get_buffer_lines(child)
  local untracked_header = find_line_with(lines, "Untracked")
  assert_truthy(untracked_header, "Should have Untracked section")

  -- Go to the section header and press 's' to stage the entire section
  child.cmd(tostring(untracked_header))
  child.type_keys("s")
  wait(child, 200)

  -- Verify all files are now staged
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("A  new1.txt"), "new1.txt should be staged")
  assert_truthy(status:find("A  new2.txt"), "new2.txt should be staged")
  assert_truthy(status:find("A  new3.txt"), "new3.txt should be staged")
  eq(status:find("%?%?"), nil, "No untracked files should remain")
end

T["section staging"]["s on Unstaged header stages all unstaged files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit files
  create_file(child, repo, "file1.txt", "original1")
  create_file(child, repo, "file2.txt", "original2")
  create_file(child, repo, "file3.txt", "original3")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify all files without staging
  create_file(child, repo, "file1.txt", "modified1")
  create_file(child, repo, "file2.txt", "modified2")
  create_file(child, repo, "file3.txt", "modified3")

  open_gitlad(child, repo)

  -- Find and go to the Unstaged section header
  local lines = get_buffer_lines(child)
  local unstaged_header = find_line_with(lines, "Unstaged")
  assert_truthy(unstaged_header, "Should have Unstaged section")

  -- Go to the section header and press 's' to stage the entire section
  child.cmd(tostring(unstaged_header))
  child.type_keys("s")
  wait(child, 200)

  -- Verify all files are now staged
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("M  file1.txt"), "file1.txt should be staged")
  assert_truthy(status:find("M  file2.txt"), "file2.txt should be staged")
  assert_truthy(status:find("M  file3.txt"), "file3.txt should be staged")
  eq(status:find(" M "), nil, "No unstaged modified files should remain")
end

T["section staging"]["u on Staged header unstages all staged files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage multiple new files
  create_file(child, repo, "staged1.txt", "content1")
  create_file(child, repo, "staged2.txt", "content2")
  create_file(child, repo, "staged3.txt", "content3")
  git(child, repo, "add .")

  open_gitlad(child, repo)

  -- Find and go to the Staged section header
  local lines = get_buffer_lines(child)
  local staged_header = find_line_with(lines, "Staged")
  assert_truthy(staged_header, "Should have Staged section")

  -- Go to the section header and press 'u' to unstage the entire section
  child.cmd(tostring(staged_header))
  child.type_keys("u")
  wait(child, 200)

  -- Verify all files are now untracked
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("%?%? staged1.txt"), "staged1.txt should be untracked")
  assert_truthy(status:find("%?%? staged2.txt"), "staged2.txt should be untracked")
  assert_truthy(status:find("%?%? staged3.txt"), "staged3.txt should be untracked")
  eq(status:find("A "), nil, "No staged files should remain")
end

T["section staging"]["s on Staged header does nothing"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage a file
  create_file(child, repo, "staged.txt", "content")
  git(child, repo, "add staged.txt")

  open_gitlad(child, repo)

  -- Find and go to the Staged section header
  local lines = get_buffer_lines(child)
  local staged_header = find_line_with(lines, "Staged")
  assert_truthy(staged_header, "Should have Staged section")

  -- Go to the section header and press 's' (should do nothing)
  child.cmd(tostring(staged_header))
  child.type_keys("s")
  wait(child, 200)

  -- Verify file is still staged (unchanged)
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("A  staged.txt"), "staged.txt should still be staged")
end

T["section staging"]["u on Unstaged header does nothing"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "file.txt", "original")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify without staging
  create_file(child, repo, "file.txt", "modified")

  open_gitlad(child, repo)

  -- Find and go to the Unstaged section header
  local lines = get_buffer_lines(child)
  local unstaged_header = find_line_with(lines, "Unstaged")
  assert_truthy(unstaged_header, "Should have Unstaged section")

  -- Go to the section header and press 'u' (should do nothing)
  child.cmd(tostring(unstaged_header))
  child.type_keys("u")
  wait(child, 200)

  -- Verify file is still unstaged (unchanged)
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find(" M file.txt"), "file.txt should still be unstaged")
end

-- =============================================================================
-- Cursor Positioning After Unstaging Tests
-- =============================================================================

T["unstage cursor positioning"] = MiniTest.new_set()

T["unstage cursor positioning"]["u moves cursor to next staged file"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage multiple files (alphabetical order: aaa, bbb, ccc)
  create_file(child, repo, "aaa.txt", "a")
  create_file(child, repo, "bbb.txt", "b")
  create_file(child, repo, "ccc.txt", "c")
  git(child, repo, "add .")

  open_gitlad(child, repo)

  -- Find and go to the middle file (bbb.txt)
  local lines = get_buffer_lines(child)
  local bbb_line = find_line_with(lines, "bbb.txt")
  assert_truthy(bbb_line, "Should find bbb.txt")
  child.cmd(tostring(bbb_line))

  -- Unstage bbb.txt
  child.type_keys("u")
  wait(child, 200)

  -- Cursor should now be on ccc.txt (the next staged file)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  lines = get_buffer_lines(child)
  local current_line_text = lines[cursor_line]
  assert_truthy(
    current_line_text:find("ccc.txt"),
    "Cursor should be on ccc.txt (next staged file), but is on: " .. tostring(current_line_text)
  )
end

T["unstage cursor positioning"]["u moves cursor to previous staged file when last"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage multiple files (alphabetical order: aaa, bbb)
  create_file(child, repo, "aaa.txt", "a")
  create_file(child, repo, "bbb.txt", "b")
  git(child, repo, "add .")

  open_gitlad(child, repo)

  -- Find and go to the last file (bbb.txt)
  local lines = get_buffer_lines(child)
  local bbb_line = find_line_with(lines, "bbb.txt")
  assert_truthy(bbb_line, "Should find bbb.txt")
  child.cmd(tostring(bbb_line))

  -- Unstage bbb.txt
  child.type_keys("u")
  wait(child, 200)

  -- Cursor should now be on aaa.txt (the previous staged file)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  lines = get_buffer_lines(child)
  local current_line_text = lines[cursor_line]
  assert_truthy(
    current_line_text:find("aaa.txt"),
    "Cursor should be on aaa.txt (previous staged file), but is on: " .. tostring(current_line_text)
  )
end

T["unstage cursor positioning"]["repeated u unstages multiple files in succession"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage 3 files
  create_file(child, repo, "file1.txt", "1")
  create_file(child, repo, "file2.txt", "2")
  create_file(child, repo, "file3.txt", "3")
  git(child, repo, "add .")

  open_gitlad(child, repo)

  -- Find and go to the first staged file
  local lines = get_buffer_lines(child)
  local file1_line = find_line_with(lines, "file1.txt")
  assert_truthy(file1_line, "Should find file1.txt")
  child.cmd(tostring(file1_line))

  -- Unstage all three files by pressing u three times
  child.type_keys("u")
  wait(child, 200)
  child.type_keys("u")
  wait(child, 200)
  child.type_keys("u")
  wait(child, 200)

  -- All files should now be unstaged
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("%?%? file1.txt"), "file1.txt should be untracked")
  assert_truthy(status:find("%?%? file2.txt"), "file2.txt should be untracked")
  assert_truthy(status:find("%?%? file3.txt"), "file3.txt should be untracked")
  eq(status:find("A "), nil, "No staged files should remain")
end

-- =============================================================================
-- Intent-to-Add (gs keybinding) Tests
-- =============================================================================

T["intent to add"] = MiniTest.new_set()

T["intent to add"]["gs marks untracked file with intent-to-add"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked file
  create_file(child, repo, "new.txt", "new content\nline 2\nline 3")

  open_gitlad(child, repo)

  -- Navigate to the untracked file
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  assert_truthy(file_line, "Should find new.txt")

  -- Go to that line and press 'gs' to mark intent-to-add
  child.cmd(tostring(file_line))
  child.type_keys("gs")
  wait(child, 200)

  -- Verify file moved to unstaged section (git add -N marks as AM)
  lines = get_buffer_lines(child)
  local unstaged_section = find_line_with(lines, "Unstaged")
  local untracked_section = find_line_with(lines, "Untracked")

  -- new.txt should be in unstaged now
  local new_line = find_line_with(lines, "new.txt")
  assert_truthy(unstaged_section, "Should have Unstaged section")
  assert_truthy(new_line and new_line > unstaged_section, "new.txt should be in unstaged section")

  -- Should NOT be in untracked
  if untracked_section then
    -- If untracked section exists, new.txt should not be in it
    local untracked_files_start = untracked_section + 1
    -- Check that new.txt is not after the untracked header
    assert_truthy(
      new_line < untracked_section or new_line == nil,
      "new.txt should not be in untracked section"
    )
  end

  -- Verify git state: after git add -N, porcelain shows " A new.txt" (space + A)
  -- meaning: index unchanged, worktree has added file
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find(" A new.txt"), "Git should show file as intent-to-add ( A)")
end

T["intent to add"]["gs on non-untracked file shows info message"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "file.txt", "original")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify the file (will be unstaged)
  create_file(child, repo, "file.txt", "modified")

  open_gitlad(child, repo)

  -- Navigate to the unstaged file
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  assert_truthy(file_line, "Should find file.txt")

  -- Go to that line and press 'gs'
  child.cmd(tostring(file_line))
  child.type_keys("gs")
  wait(child, 100)

  -- File should still be in unstaged (gs is no-op for non-untracked)
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find(" M file.txt"), "Git should show file as unstaged modified")
end

T["intent to add"]["gs followed by regular staging works"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked file
  create_file(child, repo, "new.txt", "line 1\nline 2\nline 3")

  -- First, verify file is untracked
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("%?%? new.txt"), "File should start as untracked")

  open_gitlad(child, repo)

  -- Navigate to the untracked file
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  assert_truthy(file_line, "Should find new.txt")
  child.cmd(tostring(file_line))

  -- Press gs to mark intent-to-add
  child.type_keys("gs")
  wait(child, 500)

  -- Verify git state changed to intent-to-add
  status = git(child, repo, "status --porcelain")
  assert_truthy(status:find(" A new.txt"), "After gs, git should show intent-to-add ( A)")

  -- Close gitlad and reopen to get fresh state
  child.type_keys("q")
  wait(child, 100)
  child.cmd("Gitlad")
  wait(child, 300)

  -- Now the file should be in unstaged section - find it and stage
  lines = get_buffer_lines(child)
  file_line = find_line_with(lines, "new.txt")
  assert_truthy(file_line, "Should still find new.txt")
  child.cmd(tostring(file_line))

  -- Stage the whole file
  child.type_keys("s")
  wait(child, 300)

  -- Verify file is now fully staged
  status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("A  new.txt"), "Git should show file as fully staged (A)")
end

-- =============================================================================
-- Directory Staging Tests
-- =============================================================================

T["directory staging"] = MiniTest.new_set()

-- Helper to wait for buffer content to appear
local function wait_for_content(child, text, timeout)
  timeout = timeout or 1000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local content = table.concat(lines, "\n")
      return content:find(%q, 1, true) ~= nil
    end, 10)
  ]],
    timeout,
    text
  ))
end

T["directory staging"]["s on untracked directory stages all files inside"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked directory with multiple files
  create_file(child, repo, "newdir/file1.txt", "content1")
  create_file(child, repo, "newdir/file2.txt", "content2")
  create_file(child, repo, "newdir/sub/file3.txt", "content3")

  open_gitlad(child, repo)

  -- Navigate to the untracked directory and stage it
  local lines = get_buffer_lines(child)
  local dir_line = find_line_with(lines, "newdir/")
  assert_truthy(dir_line, "Should find newdir/ in untracked section")

  -- Go to that line and press 's' to stage
  child.cmd(tostring(dir_line))
  child.type_keys("s")

  -- Wait for "Staged" section to appear (directory staging triggers refresh)
  wait_for_content(child, "Staged", 2000)

  -- Verify files are staged (not the directory)
  lines = get_buffer_lines(child)
  local staged_section = find_line_with(lines, "Staged")
  assert_truthy(staged_section, "Should have Staged section")

  -- Should see individual files in staged section, not the directory
  local file1_line = find_line_with(lines, "newdir/file1.txt")
  local file2_line = find_line_with(lines, "newdir/file2.txt")
  local file3_line = find_line_with(lines, "newdir/sub/file3.txt")

  assert_truthy(file1_line, "Should see newdir/file1.txt")
  assert_truthy(file2_line, "Should see newdir/file2.txt")
  assert_truthy(file3_line, "Should see newdir/sub/file3.txt")

  -- Verify they are in the staged section (after header)
  assert_truthy(file1_line > staged_section, "file1 should be in staged section")
  assert_truthy(file2_line > staged_section, "file2 should be in staged section")
  assert_truthy(file3_line > staged_section, "file3 should be in staged section")

  -- Verify git state
  local status = git(child, repo, "status --porcelain")
  assert_truthy(status:find("A  newdir/file1.txt"), "file1 should be staged")
  assert_truthy(status:find("A  newdir/file2.txt"), "file2 should be staged")
  assert_truthy(status:find("A  newdir/sub/file3.txt"), "file3 should be staged")
end

T["directory staging"]["staged section shows file count after staging directory"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked directory with 3 files
  create_file(child, repo, "mydir/a.txt", "a")
  create_file(child, repo, "mydir/b.txt", "b")
  create_file(child, repo, "mydir/c.txt", "c")

  open_gitlad(child, repo)

  -- Stage the directory
  local lines = get_buffer_lines(child)
  local dir_line = find_line_with(lines, "mydir/")
  assert_truthy(dir_line, "Should find mydir/")

  child.cmd(tostring(dir_line))
  child.type_keys("s")

  -- Wait for "Staged (3)" to appear (directory staging triggers refresh)
  wait_for_content(child, "Staged (3)", 2000)

  -- Verify staged section shows count of 3
  lines = get_buffer_lines(child)
  local staged_line = find_line_with(lines, "Staged (3)")
  assert_truthy(staged_line, "Staged section should show count of 3 files")
end

T["directory staging"]["unstaging all files collapses back to directory"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked directory with multiple files
  create_file(child, repo, "testdir/file1.txt", "content1")
  create_file(child, repo, "testdir/file2.txt", "content2")

  open_gitlad(child, repo)

  -- Stage the directory
  local lines = get_buffer_lines(child)
  local dir_line = find_line_with(lines, "testdir/")
  assert_truthy(dir_line, "Should find testdir/")

  child.cmd(tostring(dir_line))
  child.type_keys("s")

  -- Wait for staged files to appear
  wait_for_content(child, "Staged (2)", 2000)

  -- Now unstage all by pressing 'u' on the Staged section header
  lines = get_buffer_lines(child)
  local staged_header = find_line_with(lines, "Staged")
  assert_truthy(staged_header, "Should find Staged section")

  child.cmd(tostring(staged_header))
  child.type_keys("u")
  wait(child, 200)

  -- Files should collapse back to directory
  lines = get_buffer_lines(child)
  local dir_entry = find_line_with(lines, "testdir/")
  assert_truthy(dir_entry, "Should see testdir/ collapsed in untracked")

  -- Should NOT see individual files
  local file1 = find_line_with(lines, "testdir/file1.txt")
  local file2 = find_line_with(lines, "testdir/file2.txt")
  eq(file1, nil, "Should NOT see individual file1")
  eq(file2, nil, "Should NOT see individual file2")

  -- Should show Untracked (1) not Untracked (2)
  local untracked_header = find_line_with(lines, "Untracked (1)")
  assert_truthy(untracked_header, "Should show Untracked (1) for collapsed directory")
end

T["directory staging"]["unstaging individual files collapses when all untracked"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked directory
  create_file(child, repo, "mydir/a.txt", "a")
  create_file(child, repo, "mydir/b.txt", "b")

  open_gitlad(child, repo)

  -- Stage the directory
  local lines = get_buffer_lines(child)
  local dir_line = find_line_with(lines, "mydir/")
  child.cmd(tostring(dir_line))
  child.type_keys("s")

  -- Wait for staged files
  wait_for_content(child, "Staged (2)", 2000)

  -- Unstage first file
  lines = get_buffer_lines(child)
  local file_a = find_line_with(lines, "mydir/a.txt")
  assert_truthy(file_a, "Should find mydir/a.txt")
  child.cmd(tostring(file_a))
  child.type_keys("u")
  wait(child, 200)

  -- Should still see individual files (one staged, one untracked)
  lines = get_buffer_lines(child)
  local staged_b = find_line_with(lines, "mydir/b.txt")
  local untracked_a = find_line_with(lines, "mydir/a.txt")
  assert_truthy(staged_b, "mydir/b.txt should still be staged")
  assert_truthy(untracked_a, "mydir/a.txt should be in untracked")

  -- Now unstage the second file
  lines = get_buffer_lines(child)
  file_b = find_line_with(lines, "mydir/b.txt")
  child.cmd(tostring(file_b))
  child.type_keys("u")
  wait(child, 200)

  -- Now should collapse to directory
  lines = get_buffer_lines(child)
  local dir_entry = find_line_with(lines, "mydir/")
  assert_truthy(dir_entry, "Should see mydir/ collapsed")

  -- Individual files should not be visible
  eq(find_line_with(lines, "mydir/a.txt"), nil, "Should NOT see mydir/a.txt")
  eq(find_line_with(lines, "mydir/b.txt"), nil, "Should NOT see mydir/b.txt")
end

return T
