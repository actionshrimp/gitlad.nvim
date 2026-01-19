-- End-to-end tests for gitlad.nvim revert functionality
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

-- Helper to create a test git repository
local function create_test_repo(child)
  local repo = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init -b main")
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

-- Helper to wait
local function wait(child, ms)
  child.lua(string.format("vim.wait(%d, function() end)", ms))
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

-- =============================================================================
-- Revert popup tests
-- =============================================================================

T["revert popup"] = MiniTest.new_set()

T["revert popup"]["opens from status buffer with _ key"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial commit"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  wait(child, 500)

  -- Press _ to open revert popup
  child.type_keys("_")
  wait(child, 200)

  -- Should have a popup window
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Buffer should contain "Revert"
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local found_revert = false
  for _, line in ipairs(lines) do
    if line:match("Revert") then
      found_revert = true
      break
    end
  end
  eq(found_revert, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["revert popup"]["has expected switches and actions"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial commit"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  wait(child, 500)

  child.type_keys("_")
  wait(child, 200)

  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])

  local found_edit = false
  local found_no_edit = false
  local found_signoff = false
  local found_revert_action = false

  for _, line in ipairs(lines) do
    if line:match("%-e.*edit") then
      found_edit = true
    end
    if line:match("%-E.*no%-edit") then
      found_no_edit = true
    end
    if line:match("%-s.*signoff") then
      found_signoff = true
    end
    if line:match("V.*Revert") then
      found_revert_action = true
    end
  end

  eq(found_edit, true)
  eq(found_no_edit, true)
  eq(found_signoff, true)
  eq(found_revert_action, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- =============================================================================
-- Revert git operations tests
-- =============================================================================

T["revert operations"] = MiniTest.new_set()

T["revert operations"]["reverts a commit"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Create second commit to revert
  create_file(child, repo, "test.txt", "hello world")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Add world"')

  -- Get the hash of the commit to revert
  local commit_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Revert the commit using git module directly
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.revert({ %q }, { "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.revert_result = { success = success, output = output, err = err }
    end)
  ]],
    commit_hash,
    repo
  ))
  wait(child, 1000)

  local result = child.lua_get([[_G.revert_result]])
  eq(result.success, true)

  -- Verify we now have 3 commits (initial, add world, revert)
  local log = git(child, repo, "log --oneline")
  local commit_count = 0
  for _ in log:gmatch("[^\n]+") do
    commit_count = commit_count + 1
  end
  eq(commit_count, 3)

  -- Verify the file content was reverted
  child.lua(string.format(
    [[
    local f = io.open(%q .. "/test.txt", "r")
    _G.file_content = f:read("*a")
    f:close()
  ]],
    repo
  ))
  local content = child.lua_get("_G.file_content")
  eq(content, "hello")

  cleanup_repo(child, repo)
end

T["revert operations"]["revert no-commit stages changes"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Create second commit to revert
  create_file(child, repo, "test.txt", "hello world")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Add world"')

  local commit_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Revert with --no-commit
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.revert({ %q }, { "--no-commit" }, { cwd = %q }, function(success, output, err)
      _G.revert_result = { success = success, output = output, err = err }
    end)
  ]],
    commit_hash,
    repo
  ))
  wait(child, 1000)

  local result = child.lua_get([[_G.revert_result]])
  eq(result.success, true)

  -- Verify only 2 commits (no revert commit created)
  local log = git(child, repo, "log --oneline")
  local commit_count = 0
  for _ in log:gmatch("[^\n]+") do
    commit_count = commit_count + 1
  end
  eq(commit_count, 2)

  -- Verify there are staged changes
  local status = git(child, repo, "status --short")
  eq(status:match("M") ~= nil, true)

  cleanup_repo(child, repo)
end

-- =============================================================================
-- Revert from log view tests
-- =============================================================================

T["revert from log"] = MiniTest.new_set()

T["revert from log"]["_ key opens revert popup from log view"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create commits
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "First commit"')

  create_file(child, repo, "test.txt", "hello world")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Second commit"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  wait(child, 500)

  -- Open log view
  child.type_keys("l")
  wait(child, 200)
  child.type_keys("l") -- press l again to open log
  wait(child, 500)

  -- Move to a commit line
  child.type_keys("5j")
  wait(child, 100)

  -- Press _ to open revert popup
  child.type_keys("_")
  wait(child, 200)

  -- Should have revert popup
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local found_revert = false
  for _, line in ipairs(lines) do
    if line:match("Revert") then
      found_revert = true
      break
    end
  end
  eq(found_revert, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- =============================================================================
-- In-progress revert tests
-- =============================================================================

T["revert in-progress"] = MiniTest.new_set()

T["revert in-progress"]["detects revert in progress via git sequencer state"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "line1\nline2\nline3")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create commit that modifies line2
  create_file(child, repo, "test.txt", "line1\nmodified\nline3")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Modify line2"')
  local commit_to_revert = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Create another commit that also modifies line2 (will conflict)
  create_file(child, repo, "test.txt", "line1\nconflicting\nline3")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Conflict commit"')

  -- Try to revert using git directly (will conflict and leave in-progress state)
  git(child, repo, "revert --no-edit " .. commit_to_revert .. " 2>&1 || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Check if .git/REVERT_HEAD exists (indicates revert in progress)
  local revert_head_exists =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/.git/REVERT_HEAD")]], repo))
  eq(revert_head_exists, 1)

  -- Now test via our git module
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      _G.sequencer_state = state
    end)
  ]],
    repo
  ))
  wait(child, 500)

  local state = child.lua_get("_G.sequencer_state")
  eq(state.revert_in_progress, true)

  -- Abort the revert
  git(child, repo, "revert --abort")
  cleanup_repo(child, repo)
end

return T
