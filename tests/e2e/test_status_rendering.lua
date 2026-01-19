-- End-to-end tests for gitlad.nvim status view rendering
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

-- =============================================================================
-- Head/Merge/Push Header Tests
-- =============================================================================

T["status header"] = MiniTest.new_set()

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

T["recent commits"]["shows Recent commits section even with unpushed commits"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "file1.txt", "content 1")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "First commit"')

  -- Create a named branch and set up fake remote/upstream
  git(child, repo, "branch -M main-branch")
  git(child, repo, "remote add origin https://example.com/repo.git")
  git(child, repo, "update-ref refs/remotes/origin/main-branch HEAD~0")
  git(child, repo, "branch --set-upstream-to=origin/main-branch main-branch")

  -- Add a commit that will be "unpushed"
  create_file(child, repo, "file2.txt", "content 2")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Second commit (unpushed)"')

  open_gitlad(child, repo)

  -- Wait for extended status fetch (includes recent commits and unpushed)
  child.lua([[vim.wait(2000, function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local found_recent = false
    local found_unmerged = false
    for _, line in ipairs(lines) do
      if line:find("Recent commits", 1, true) then found_recent = true end
      if line:find("Unmerged into", 1, true) then found_unmerged = true end
    end
    return found_recent and found_unmerged
  end)]])

  local lines = get_buffer_lines(child)

  -- Should show BOTH unpushed section AND recent commits
  local unmerged_line = find_line_with(lines, "Unmerged into")
  local recent_line = find_line_with(lines, "Recent commits")

  assert_truthy(unmerged_line, "Should show Unmerged section when ahead of upstream")
  assert_truthy(recent_line, "Should show Recent commits even when there are unpushed commits")
end

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
-- Status Indicator Line Tests
-- =============================================================================

T["status indicator"] = MiniTest.new_set()

T["status indicator"]["shows placeholder dot when idle"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial commit"')

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)

  -- The status indicator should be on its own line after the branch lines
  -- It should show the placeholder dot "·" when not refreshing
  local found_placeholder = false
  for _, line in ipairs(lines) do
    if line == "·" then
      found_placeholder = true
      break
    end
  end

  assert_truthy(found_placeholder, "Should show placeholder dot (·) when idle")
end

T["status indicator"]["appears after Head line"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial commit"')

  open_gitlad(child, repo)

  local lines = get_buffer_lines(child)

  -- Find Head line and status indicator
  local head_line_num = nil
  local status_line_num = nil

  for i, line in ipairs(lines) do
    if line:match("^Head:") then
      head_line_num = i
    elseif line == "·" then
      status_line_num = i
    end
  end

  assert_truthy(head_line_num, "Should have Head line")
  assert_truthy(status_line_num, "Should have status indicator line")
  assert_truthy(status_line_num > head_line_num, "Status indicator should be after Head line")
end

return T
