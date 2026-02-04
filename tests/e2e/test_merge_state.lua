-- End-to-end tests for gitlad.nvim merge state detection
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

-- Merge state detection tests
T["merge state detection"] = MiniTest.new_set()

T["merge state detection"]["get_merge_state returns false when not merging"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Check merge state when nothing in progress
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_merge_state({ cwd = %q }, function(state)
      _G.merge_state = state
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(500, function() return _G.merge_state ~= nil end)]])
  local merge_state = child.lua_get([[_G.merge_state]])

  eq(merge_state.merge_in_progress, false)
  -- merge_head_oid is nil when no merge is in progress
  local oid_is_nil = merge_state.merge_head_oid == nil or merge_state.merge_head_oid == vim.NIL
  eq(oid_is_nil, true)

  helpers.cleanup_repo(child, repo)
end

T["merge state detection"]["get_merge_state returns true during merge conflict"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Get feature branch commit hash
  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  -- Try to merge feature (should conflict)
  helpers.git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Check merge state
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_merge_state({ cwd = %q }, function(state)
      _G.merge_state = state
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(500, function() return _G.merge_state ~= nil end)]])
  local merge_state = child.lua_get([[_G.merge_state]])

  eq(merge_state.merge_in_progress, true)
  eq(merge_state.merge_head_oid, feature_hash)

  helpers.cleanup_repo(child, repo)
end

T["merge state detection"]["merge_in_progress sync function works"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Check before merge
  local before_merge =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(before_merge, false)

  -- Start merge with conflict
  helpers.git(child, repo, "merge feature --no-edit || true")

  -- Check during merge
  local during_merge =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(during_merge, true)

  helpers.cleanup_repo(child, repo)
end

-- Merge git operations tests
T["merge operations"] = MiniTest.new_set()

T["merge operations"]["merge performs fast-forward merge"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch and add commit
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Go back to main (which is now behind feature)
  helpers.git(child, repo, "checkout main")

  -- Verify feature.txt doesn't exist on main
  local exists_before =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_before, 0)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Merge feature branch
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("feature", { "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, true)

  -- Verify feature.txt now exists on main
  local exists_after =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_after, 1)

  helpers.cleanup_repo(child, repo)
end

T["merge operations"]["merge with --no-ff creates merge commit"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch and add commit
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Go back to main
  helpers.git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Merge with --no-ff
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("feature", { "--no-ff", "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, true)

  -- Verify a merge commit was created (should have "Merge branch" in message)
  local log = helpers.git(child, repo, "log --oneline -1")
  eq(log:match("Merge branch") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["merge operations"]["merge detects conflicts"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Try to merge (should fail with conflict)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("feature", { "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, false)
  -- Error should mention conflict
  eq(result.err:match("CONFLICT") ~= nil or result.err:match("conflict") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["merge operations"]["merge_abort aborts in-progress merge"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  local head_before = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Start merge with conflict
  helpers.git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify merge is in progress
  local in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress, true)

  -- Abort merge
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge_abort({ cwd = %q }, function(success, err)
      _G.abort_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.abort_result ~= nil end)]])
  local abort_result = child.lua_get([[_G.abort_result]])

  eq(abort_result.success, true)

  -- Verify HEAD is back to where it was
  local head_after = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")
  eq(head_after, head_before)

  -- Verify merge is no longer in progress
  local still_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(still_in_progress, false)

  helpers.cleanup_repo(child, repo)
end

T["merge operations"]["merge_continue commits resolved merge"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  helpers.git(child, repo, "merge feature --no-edit || true")

  -- Resolve conflict manually
  helpers.create_file(child, repo, "test.txt", "line1\nresolved")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Continue merge (commit)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge_continue({ cwd = %q }, function(success, err)
      _G.continue_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(2000, function() return _G.continue_result ~= nil end)]])
  local continue_result = child.lua_get([[_G.continue_result]])

  eq(continue_result.success, true)

  -- Verify merge is no longer in progress
  local still_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(still_in_progress, false)

  -- Verify merge commit was created
  local log = helpers.git(child, repo, "log --oneline -1")
  eq(log:match("Merge branch") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- Status header merge display tests
T["status header"] = MiniTest.new_set()

T["status header"]["shows Merging line during merge conflict"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  helpers.git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load and render
  helpers.wait_for_status(child)

  -- Get status buffer content
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_merging = false
  for _, line in ipairs(lines) do
    if line:match("^Merging:") then
      found_merging = true
      -- Should contain part of the commit hash
      eq(line:match("%x+") ~= nil, true)
    end
  end

  eq(found_merging, true)

  helpers.cleanup_repo(child, repo)
end

-- Error path tests
T["error paths"] = MiniTest.new_set()

T["error paths"]["merge_abort fails gracefully when not merging"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit - no merge in progress
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Try to abort when not merging
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge_abort({ cwd = %q }, function(success, err)
      _G.abort_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.abort_result ~= nil end)]])
  local result = child.lua_get([[_G.abort_result]])

  eq(result.success, false)
  -- Error should indicate no merge to abort
  eq(result.err ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["error paths"]["merge_continue fails with unresolved conflicts"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create merge conflict
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "line1\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature"')

  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "line1\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main"')

  -- Start merge with conflict but don't resolve
  helpers.git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Try to continue without resolving
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge_continue({ cwd = %q }, function(success, err)
      _G.continue_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.continue_result ~= nil end)]])
  local result = child.lua_get([[_G.continue_result]])

  eq(result.success, false)
  -- Error should indicate unmerged paths
  eq(result.err ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["error paths"]["merge fails with invalid branch name"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Try to merge non-existent branch
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("nonexistent-branch", { "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, false)
  -- Error should mention the branch
  eq(result.err ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["error paths"]["ff-only merge fails when not fast-forwardable"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create divergent branches
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Feature"')

  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "main.txt", "main")
  helpers.git(child, repo, "add main.txt")
  helpers.git(child, repo, 'commit -m "Main diverge"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Try ff-only merge on divergent branch
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("feature", { "--ff-only" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, false)
  -- Error should mention fast-forward
  eq(result.err ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- Merge arguments tests
T["merge arguments"] = MiniTest.new_set()

T["merge arguments"]["squash merge stages changes without creating merge commit"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  helpers.git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Perform squash merge
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("feature", { "--squash" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, true)

  -- Changes should be staged
  local staged = helpers.git(child, repo, "diff --cached --name-only")
  eq(staged:match("feature%.txt") ~= nil, true)

  -- No MERGE_HEAD (not a merge commit pending)
  local merge_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(merge_in_progress, false)

  -- HEAD should not have changed (no auto-commit)
  local log = helpers.git(child, repo, "log --oneline -1")
  eq(log:match("Initial") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["merge arguments"]["no-commit merge stages changes without committing"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Go back to main and create a divergent commit
  -- (--no-commit only creates MERGE_HEAD for non-fast-forward merges)
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "main.txt", "main content")
  helpers.git(child, repo, "add main.txt")
  helpers.git(child, repo, 'commit -m "Main diverge"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Perform no-commit merge (now it's a real merge, not fast-forward)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.merge("feature", { "--no-commit", "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.merge_result = { success = success, output = output, err = err }
    end)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return _G.merge_result ~= nil end)]])
  local result = child.lua_get([[_G.merge_result]])

  eq(result.success, true)

  -- Changes should be staged
  local staged = helpers.git(child, repo, "diff --cached --name-only")
  eq(staged:match("feature%.txt") ~= nil, true)

  -- MERGE_HEAD should exist (merge pending)
  local merge_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(merge_in_progress, true)

  helpers.cleanup_repo(child, repo)
end

return T
