-- End-to-end tests for sequencer state detection (cherry-pick/revert in progress)
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

-- Test sequencer state detection
T["sequencer state"] = MiniTest.new_set()

T["sequencer state"]["detects cherry-pick in progress"] = function()
  local child = _G.child

  local repo = create_test_repo(child)

  -- Make an initial commit
  create_file(child, repo, "file.txt", "initial content")
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll cherry-pick later
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to first commit and create a conflicting branch
  git(child, repo, "checkout HEAD~1")
  git(child, repo, "checkout -b test-branch")

  -- Modify the same file to create a conflict
  create_file(child, repo, "feature.txt", "conflicting content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Conflicting commit"')

  -- Try to cherry-pick - this should fail with conflict
  git(child, repo, "cherry-pick " .. feature_hash .. " 2>&1 || true")

  -- Check that CHERRY_PICK_HEAD exists
  local cherry_pick_head_exists =
    child.lua_get(string.format([[vim.fn.filereadable("%s/.git/CHERRY_PICK_HEAD") == 1]], repo))
  eq(cherry_pick_head_exists, true)

  -- Now check the git module detects it
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      vim.g.test_seq_state = state
    end)
  ]],
    repo,
    repo
  ))

  child.lua([[vim.wait(500, function() return vim.g.test_seq_state ~= nil end)]])
  local seq_state = child.lua_get([[vim.g.test_seq_state]])

  eq(seq_state.cherry_pick_in_progress, true)
  eq(seq_state.revert_in_progress, false)
  eq(type(seq_state.sequencer_head_oid), "string")

  cleanup_repo(child, repo)
end

T["sequencer state"]["detects revert in progress"] = function()
  local child = _G.child

  local repo = create_test_repo(child)

  -- Make an initial commit
  create_file(child, repo, "file.txt", "initial content")
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll revert later
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Modify the feature file to create a conflict when reverting
  create_file(child, repo, "feature.txt", "modified content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Modify feature"')

  -- Try to revert the feature commit - this should fail with conflict
  git(child, repo, "revert --no-edit " .. feature_hash .. " 2>&1 || true")

  -- Check that REVERT_HEAD exists
  local revert_head_exists =
    child.lua_get(string.format([[vim.fn.filereadable("%s/.git/REVERT_HEAD") == 1]], repo))
  eq(revert_head_exists, true)

  -- Now check the git module detects it
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      vim.g.test_seq_state = state
    end)
  ]],
    repo,
    repo
  ))

  child.lua([[vim.wait(500, function() return vim.g.test_seq_state ~= nil end)]])
  local seq_state = child.lua_get([[vim.g.test_seq_state]])

  eq(seq_state.cherry_pick_in_progress, false)
  eq(seq_state.revert_in_progress, true)
  eq(type(seq_state.sequencer_head_oid), "string")

  cleanup_repo(child, repo)
end

T["sequencer state"]["detects no operation in progress"] = function()
  local child = _G.child

  local repo = create_test_repo(child)

  -- Make a simple commit
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Check that no sequencer operation is detected
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      vim.g.test_seq_state = state
    end)
  ]],
    repo,
    repo
  ))

  child.lua([[vim.wait(500, function() return vim.g.test_seq_state ~= nil end)]])
  local seq_state = child.lua_get([[vim.g.test_seq_state]])

  eq(seq_state.cherry_pick_in_progress, false)
  eq(seq_state.revert_in_progress, false)

  cleanup_repo(child, repo)
end

T["sequencer state"]["status buffer shows cherry-pick in progress"] = function()
  local child = _G.child

  local repo = create_test_repo(child)

  -- Make an initial commit
  create_file(child, repo, "file.txt", "initial content")
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll cherry-pick later
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to first commit and create a conflicting branch
  git(child, repo, "checkout HEAD~1")
  git(child, repo, "checkout -b test-branch")

  -- Modify the same file to create a conflict
  create_file(child, repo, "feature.txt", "conflicting content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Conflicting commit"')

  -- Try to cherry-pick - this should fail with conflict
  git(child, repo, "cherry-pick " .. feature_hash .. " 2>&1 || true")

  -- Open status buffer
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load (async fetch)
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Get buffer lines
  child.lua([[
    local buf = vim.api.nvim_get_current_buf()
    vim.g.status_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[vim.g.status_lines]])

  -- Check for cherry-pick indicator in header
  local found_cherry_pick = false
  for _, line in ipairs(lines) do
    if line:match("Cherry%-picking:") then
      found_cherry_pick = true
      break
    end
  end

  eq(found_cherry_pick, true)

  cleanup_repo(child, repo)
end

T["sequencer state"]["status buffer shows revert in progress"] = function()
  local child = _G.child

  local repo = create_test_repo(child)

  -- Make an initial commit
  create_file(child, repo, "file.txt", "initial content")
  git(child, repo, "add file.txt")
  git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll revert later
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Modify the feature file to create a conflict when reverting
  create_file(child, repo, "feature.txt", "modified content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Modify feature"')

  -- Try to revert the feature commit - this should fail with conflict
  git(child, repo, "revert --no-edit " .. feature_hash .. " 2>&1 || true")

  -- Open status buffer
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load (async fetch)
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Get buffer lines
  child.lua([[
    local buf = vim.api.nvim_get_current_buf()
    vim.g.status_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[vim.g.status_lines]])

  -- Check for revert indicator in header
  local found_revert = false
  for _, line in ipairs(lines) do
    if line:match("Reverting:") then
      found_revert = true
      break
    end
  end

  eq(found_revert, true)

  cleanup_repo(child, repo)
end

return T
