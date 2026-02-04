-- End-to-end tests for sequencer state detection (cherry-pick/revert in progress)
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

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

  local repo = helpers.create_test_repo(child)

  -- Make an initial commit
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll cherry-pick later
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to first commit and create a conflicting branch
  helpers.git(child, repo, "checkout HEAD~1")
  helpers.git(child, repo, "checkout -b test-branch")

  -- Modify the same file to create a conflict
  helpers.create_file(child, repo, "feature.txt", "conflicting content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Conflicting commit"')

  -- Try to cherry-pick - this should fail with conflict
  helpers.git(child, repo, "cherry-pick " .. feature_hash .. " 2>&1 || true")

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

  helpers.cleanup_repo(child, repo)
end

T["sequencer state"]["detects revert in progress"] = function()
  local child = _G.child

  local repo = helpers.create_test_repo(child)

  -- Make an initial commit
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll revert later
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Modify the feature file to create a conflict when reverting
  helpers.create_file(child, repo, "feature.txt", "modified content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Modify feature"')

  -- Try to revert the feature commit - this should fail with conflict
  helpers.git(child, repo, "revert --no-edit " .. feature_hash .. " 2>&1 || true")

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

  helpers.cleanup_repo(child, repo)
end

T["sequencer state"]["detects no operation in progress"] = function()
  local child = _G.child

  local repo = helpers.create_test_repo(child)

  -- Make a simple commit
  helpers.create_file(child, repo, "file.txt", "content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

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

  helpers.cleanup_repo(child, repo)
end

T["sequencer state"]["status buffer shows cherry-pick in progress"] = function()
  local child = _G.child

  local repo = helpers.create_test_repo(child)

  -- Make an initial commit
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll cherry-pick later
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to first commit and create a conflicting branch
  helpers.git(child, repo, "checkout HEAD~1")
  helpers.git(child, repo, "checkout -b test-branch")

  -- Modify the same file to create a conflict
  helpers.create_file(child, repo, "feature.txt", "conflicting content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Conflicting commit"')

  -- Try to cherry-pick - this should fail with conflict
  helpers.git(child, repo, "cherry-pick " .. feature_hash .. " 2>&1 || true")

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

  helpers.cleanup_repo(child, repo)
end

T["sequencer state"]["status buffer shows revert in progress"] = function()
  local child = _G.child

  local repo = helpers.create_test_repo(child)

  -- Make an initial commit
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create a commit that we'll revert later
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Get the feature commit hash
  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Modify the feature file to create a conflict when reverting
  helpers.create_file(child, repo, "feature.txt", "modified content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Modify feature"')

  -- Try to revert the feature commit - this should fail with conflict
  helpers.git(child, repo, "revert --no-edit " .. feature_hash .. " 2>&1 || true")

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

  helpers.cleanup_repo(child, repo)
end

return T
