-- End-to-end tests for gitlad.nvim status view
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
-- Status View Rendering Tests
-- =============================================================================

T["status view"] = MiniTest.new_set()

T["status view"]["shows branch info"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial commit"')

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local head_line = find_line_with(lines, "Head:")
  assert_truthy(head_line, "Should have Head: line")

  local _, line = find_line_with(lines, "main")
  if not line then
    _, line = find_line_with(lines, "master")
  end
  assert_truthy(line, "Should show branch name (main or master)")
end

T["status view"]["shows untracked files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked files
  create_file(child, repo, "untracked1.txt", "content1")
  create_file(child, repo, "untracked2.txt", "content2")

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local section_line = find_line_with(lines, "Untracked")
  assert_truthy(section_line, "Should have Untracked section")

  local file1_line = find_line_with(lines, "untracked1.txt")
  local file2_line = find_line_with(lines, "untracked2.txt")
  assert_truthy(file1_line, "Should show untracked1.txt")
  assert_truthy(file2_line, "Should show untracked2.txt")
end

T["status view"]["shows staged files with A status"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Stage a new file
  create_file(child, repo, "new_file.txt", "new content")
  git(child, repo, "add new_file.txt")

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local staged_section = find_line_with(lines, "Staged")
  assert_truthy(staged_section, "Should have Staged section")

  -- Find line with new_file.txt and check it has A status
  local file_line_num, file_line = find_line_with(lines, "new_file.txt")
  assert_truthy(file_line_num, "Should show new_file.txt")
  assert_truthy(file_line:find("A"), "Should show A (added) status")
end

T["status view"]["shows unstaged modified files with M status"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "file.txt", "original content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Modify the file without staging
  create_file(child, repo, "file.txt", "modified content")

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local unstaged_section = find_line_with(lines, "Unstaged")
  assert_truthy(unstaged_section, "Should have Unstaged section")

  local file_line_num, file_line = find_line_with(lines, "file.txt")
  assert_truthy(file_line_num, "Should show file.txt")
  assert_truthy(file_line:find("M"), "Should show M (modified) status")
end

T["status view"]["shows staged deleted files with D status"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create and commit a file
  create_file(child, repo, "to_delete.txt", "content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Delete and stage the deletion
  git(child, repo, "rm to_delete.txt")

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local staged_section = find_line_with(lines, "Staged")
  assert_truthy(staged_section, "Should have Staged section")

  local file_line_num, file_line = find_line_with(lines, "to_delete.txt")
  assert_truthy(file_line_num, "Should show to_delete.txt")
  assert_truthy(file_line:find("D"), "Should show D (deleted) status")
end

T["status view"]["shows files in alphabetical order"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create untracked files in non-alphabetical order
  create_file(child, repo, "zebra.txt", "z")
  create_file(child, repo, "apple.txt", "a")
  create_file(child, repo, "mango.txt", "m")

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)

  local apple_line = find_line_with(lines, "apple.txt")
  local mango_line = find_line_with(lines, "mango.txt")
  local zebra_line = find_line_with(lines, "zebra.txt")

  assert_truthy(apple_line, "Should show apple.txt")
  assert_truthy(mango_line, "Should show mango.txt")
  assert_truthy(zebra_line, "Should show zebra.txt")

  -- Verify alphabetical order
  assert_truthy(apple_line < mango_line, "apple.txt should come before mango.txt")
  assert_truthy(mango_line < zebra_line, "mango.txt should come before zebra.txt")
end

T["status view"]["shows mixed staged and unstaged for same file"] = function()
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

  -- Navigate to file and expand
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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

  -- Navigate to file and expand
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
  wait(child, 200)

  -- Verify expanded
  lines = get_buffer_lines(child)
  local has_diff = find_line_with(lines, "@@")
  assert_truthy(has_diff, "Should show diff after first TAB")

  -- Collapse with another TAB
  child.type_keys("<Tab>")
  wait(child, 100)

  -- Verify collapsed
  lines = get_buffer_lines(child)
  has_diff = find_line_with(lines, "@@")
  eq(has_diff, nil, "Should not show diff after second TAB")
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

  -- Navigate to file and expand
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "new.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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

  -- Expand the diff
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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

  -- Expand the staged diff
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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

  -- Expand the diff
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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

  -- Expand the staged diff
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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

  -- Expand the diff
  local lines = get_buffer_lines(child)
  local file_line = find_line_with(lines, "file.txt")
  child.cmd(tostring(file_line))
  child.type_keys("<Tab>")
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
-- Head/Merge/Push Header Tests
-- =============================================================================

T["status header"] = MiniTest.new_set()

-- Helper to create a test repo with upstream tracking
local function create_test_repo_with_upstream(child)
  local repo = child.lua_get("vim.fn.tempname()")
  local remote = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
    [[
    local repo = %q
    local remote = %q

    -- Create the bare remote
    vim.fn.mkdir(remote, "p")
    vim.fn.system("git -C " .. remote .. " init --bare")

    -- Create the local repo
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init")
    vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")

    -- Create initial commit
    local f = io.open(repo .. "/init.txt", "w")
    f:write("initial content")
    f:close()
    vim.fn.system("git -C " .. repo .. " add .")
    vim.fn.system("git -C " .. repo .. " commit -m 'Initial commit'")

    -- Add remote and push with tracking
    vim.fn.system("git -C " .. repo .. " remote add origin " .. remote)

    -- Get default branch and push
    local branch = vim.fn.system("git -C " .. repo .. " branch --show-current"):gsub("\n", "")
    vim.fn.system("git -C " .. repo .. " push -u origin " .. branch)
  ]],
    repo,
    remote
  ))
  return repo
end

T["status header"]["shows Head line with commit message"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit with a specific message
  create_file(child, repo, "init.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Add initial file"')

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local _, head_line = find_line_with(lines, "Head:")
  assert_truthy(head_line, "Should have Head: line")
  -- The head line should contain the commit message
  assert_truthy(head_line:find("Add initial file"), "Head line should show commit message")
end

T["status header"]["shows Merge line when upstream exists"] = function()
  local child = _G.child
  local repo = create_test_repo_with_upstream(child)

  -- Open gitlad
  child.cmd("cd " .. repo)
  child.cmd("Gitlad")

  -- Wait for async status fetch including extended status data
  child.lua([[vim.wait(2000, function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("Merge:", 1, true) then return true end
    end
    return false
  end)]])

  local lines = get_buffer_lines(child)
  local merge_line = find_line_with(lines, "Merge:")
  assert_truthy(merge_line, "Should have Merge: line when upstream exists")
end

T["status header"]["hides Merge line when no upstream"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit without any remote
  create_file(child, repo, "init.txt", "initial")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial commit"')

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)
  local merge_line = find_line_with(lines, "Merge:")
  eq(merge_line, nil, "Should not have Merge: line when no upstream")
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
-- Buffer Protection Tests
-- =============================================================================

T["buffer protection"] = MiniTest.new_set()

T["buffer protection"]["status buffer is not modifiable"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "file.txt", "content")

  open_gitlad(child, repo)

  -- Check that buffer is not modifiable
  local modifiable = child.lua_get("vim.bo.modifiable")
  eq(modifiable, false)
end

T["buffer protection"]["cannot edit status buffer with normal commands"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "file.txt", "content")

  open_gitlad(child, repo)

  -- Get line count before attempting edit
  local line_count_before = child.lua_get("vim.api.nvim_buf_line_count(0)")

  -- Try to add a line with 'o' (should fail silently or error)
  -- Since buffer is non-modifiable, this should not change anything
  child.lua([[
    pcall(function()
      vim.cmd("normal! o")
    end)
  ]])

  -- Line count should remain the same
  local line_count_after = child.lua_get("vim.api.nvim_buf_line_count(0)")
  eq(line_count_before, line_count_after)
end

-- =============================================================================
-- Recent Commits Tests
-- =============================================================================

T["recent commits"] = MiniTest.new_set()

T["recent commits"]["shows Recent commits section when no upstream"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create multiple commits (no remote/upstream)
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "First commit"')

  create_file(child, repo, "file2.txt", "content 2")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Second commit"')

  open_gitlad(child, repo)

  -- Wait for extended status fetch (includes recent commits)
  child.lua([[vim.wait(2000, function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("Recent commits", 1, true) then return true end
    end
    return false
  end)]])

  local lines = get_buffer_lines(child)
  local recent_line = find_line_with(lines, "Recent commits")
  assert_truthy(recent_line, "Should show Recent commits section when no upstream")
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

return T
