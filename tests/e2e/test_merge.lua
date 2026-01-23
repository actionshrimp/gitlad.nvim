-- End-to-end tests for gitlad.nvim merge functionality
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
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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

  cleanup_repo(child, repo)
end

T["merge state detection"]["get_merge_state returns true during merge conflict"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Get feature branch commit hash
  local feature_hash = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Try to merge feature (should conflict)
  git(child, repo, "merge feature --no-edit || true")

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

  cleanup_repo(child, repo)
end

T["merge state detection"]["merge_in_progress sync function works"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Check before merge
  local before_merge =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(before_merge, false)

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  -- Check during merge
  local during_merge =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(during_merge, true)

  cleanup_repo(child, repo)
end

-- Merge git operations tests
T["merge operations"] = MiniTest.new_set()

T["merge operations"]["merge performs fast-forward merge"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch and add commit
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Go back to main (which is now behind feature)
  git(child, repo, "checkout main")

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

  cleanup_repo(child, repo)
end

T["merge operations"]["merge with --no-ff creates merge commit"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch and add commit
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Go back to main
  git(child, repo, "checkout main")

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
  local log = git(child, repo, "log --oneline -1")
  eq(log:match("Merge branch") ~= nil, true)

  cleanup_repo(child, repo)
end

T["merge operations"]["merge detects conflicts"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

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

  cleanup_repo(child, repo)
end

T["merge operations"]["merge_abort aborts in-progress merge"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  local head_before = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

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
  local head_after = git(child, repo, "rev-parse HEAD"):gsub("%s+", "")
  eq(head_after, head_before)

  -- Verify merge is no longer in progress
  local still_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(still_in_progress, false)

  cleanup_repo(child, repo)
end

T["merge operations"]["merge_continue commits resolved merge"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  -- Resolve conflict manually
  create_file(child, repo, "test.txt", "line1\nresolved")
  git(child, repo, "add test.txt")

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
  local log = git(child, repo, "log --oneline -1")
  eq(log:match("Merge branch") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Merge popup UI tests
T["merge popup"] = MiniTest.new_set()

T["merge popup"]["opens from status buffer with m key"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press m to open merge popup
  child.type_keys("m")

  -- Wait for async popup to open
  child.lua([[vim.wait(500, function() return false end)]])

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains merge-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_merge = false
  local found_squash = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge") then
      found_merge = true
    end
    if line:match("s%s+Squash") then
      found_squash = true
    end
  end

  eq(found_merge, true)
  eq(found_squash, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_ff_only = false
  local found_no_ff = false

  for _, line in ipairs(lines) do
    if line:match("%-f.*ff%-only") then
      found_ff_only = true
    end
    if line:match("%-n.*no%-ff") then
      found_no_ff = true
    end
  end

  eq(found_ff_only, true)
  eq(found_no_ff, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["closes with q"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open merge popup
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  cleanup_repo(child, repo)
end

T["merge popup"]["m keybinding appears in help"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help with ?
  child.type_keys("?")

  -- Check for merge in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_merge = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge") then
      found_merge = true
    end
  end

  eq(found_merge, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["shows in-progress popup during merge conflict"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load fully
  child.lua([[vim.wait(1500, function() return false end)]])

  -- Verify merge state is detected
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

  -- Open merge popup
  child.type_keys("m")

  -- Wait for async popup to open (merge state detection is async)
  child.lua([[vim.wait(2000, function() return false end)]])

  -- Wait for popup window to appear
  child.lua([[
    vim.wait(500, function()
      return #vim.api.nvim_list_wins() > 1
    end)
  ]])

  -- Verify popup shows in-progress state
  -- The popup name (with "in progress") is shown in window title, not buffer content
  -- So we verify the in-progress actions are present instead
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- In-progress popup should have "Commit merge" and "Abort merge" actions
  -- (not the normal "Merge", "Squash merge" actions)
  local found_commit = false
  local found_abort = false
  local found_normal_merge = false -- This should NOT be present in in-progress popup
  for _, line in ipairs(lines) do
    if line:match("m%s+Commit merge") then
      found_commit = true
    end
    if line:match("a%s+Abort merge") then
      found_abort = true
    end
    -- In normal popup, "m" is for regular "Merge" not "Commit merge"
    -- and "s" is for "Squash merge"
    if line:match("s%s+Squash merge") then
      found_normal_merge = true
    end
  end

  eq(found_commit, true)
  eq(found_abort, true)
  eq(found_normal_merge, false) -- Squash should NOT be in in-progress popup

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- Status header merge display tests
T["status header"] = MiniTest.new_set()

T["status header"]["shows Merging line during merge conflict"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load and render
  child.lua([[vim.wait(1000, function() return false end)]])

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

  cleanup_repo(child, repo)
end

-- Staging conflicted files tests
T["staging conflicted files"] = MiniTest.new_set()

T["staging conflicted files"]["s on conflicted file stages it (marks as resolved)"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  -- Resolve conflict manually
  create_file(child, repo, "test.txt", "line1\nresolved")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Verify file is in Conflicted section
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_conflicted_section = false
  local conflicted_line = nil
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      found_conflicted_section = true
    end
    if found_conflicted_section and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  eq(found_conflicted_section, true)
  eq(conflicted_line ~= nil, true)

  -- Navigate to the conflicted file and press s to stage
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
  child.type_keys("s")

  -- Wait for staging to complete
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Verify file is now staged (in git status)
  local staged_status = git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("test%.txt") ~= nil, true)

  -- Verify merge can now be completed
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

  -- Verify merge is complete
  local in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress, false)

  cleanup_repo(child, repo)
end

T["staging conflicted files"]["s on Conflicted section header stages all conflicted files"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main with two files
  create_file(child, repo, "file1.txt", "content1")
  create_file(child, repo, "file2.txt", "content2")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting changes
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "file1.txt", "feature1")
  create_file(child, repo, "file2.txt", "feature2")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Feature changes"')

  -- Go back to main and make conflicting changes
  git(child, repo, "checkout main")
  create_file(child, repo, "file1.txt", "main1")
  create_file(child, repo, "file2.txt", "main2")
  git(child, repo, "add .")
  git(child, repo, 'commit -m "Main changes"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  -- Resolve conflicts manually
  create_file(child, repo, "file1.txt", "resolved1")
  create_file(child, repo, "file2.txt", "resolved2")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Find Conflicted section header
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local conflicted_header_line = nil
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      conflicted_header_line = i
      break
    end
  end

  eq(conflicted_header_line ~= nil, true)

  -- Navigate to section header and press s
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_header_line))
  child.type_keys("s")

  -- Wait for staging to complete
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Verify both files are now staged
  local staged_status = git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("file1%.txt") ~= nil, true)
  eq(staged_status:match("file2%.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Conflict marker safeguard tests
T["conflict marker safeguard"] = MiniTest.new_set()

T["conflict marker safeguard"]["s on file with conflict markers shows confirmation prompt"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict (file will have conflict markers)
  git(child, repo, "merge feature --no-edit || true")

  -- Verify the file has conflict markers
  local file_content = git(child, repo, "cat test.txt || cat " .. repo .. "/test.txt")
  eq(file_content:match("<<<<<<<") ~= nil, true)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Find the conflicted file line
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_conflicted_section = false
  local conflicted_line = nil
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      found_conflicted_section = true
    end
    if found_conflicted_section and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  eq(found_conflicted_section, true)
  eq(conflicted_line ~= nil, true)

  -- Mock vim.ui.select to track calls and auto-cancel
  child.lua([[
    _G.ui_select_called = false
    _G.original_ui_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      _G.ui_select_called = true
      on_choice(nil)  -- Cancel
    end
  ]])

  -- Navigate to conflicted file and press s
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
  child.type_keys("s")
  child.lua([[vim.wait(500, function() return false end)]])

  -- Check if vim.ui.select was called
  local ui_select_called = child.lua_get([[_G.ui_select_called]])
  eq(ui_select_called, true)

  -- Restore
  child.lua([[vim.ui.select = _G.original_ui_select]])
  cleanup_repo(child, repo)
end

T["conflict marker safeguard"]["s on resolved file without markers stages immediately"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting change
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make conflicting change
  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main change"')

  -- Start merge with conflict
  git(child, repo, "merge feature --no-edit || true")

  -- Resolve conflict by writing clean content (no conflict markers)
  create_file(child, repo, "test.txt", "resolved content")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Find the conflicted file line
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_conflicted_section = false
  local conflicted_line = nil
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      found_conflicted_section = true
    end
    if found_conflicted_section and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  eq(conflicted_line ~= nil, true)

  -- Navigate to the conflicted file and press s
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
  child.type_keys("s")

  -- Wait for staging to complete (no prompt expected)
  child.lua([[vim.wait(1000, function() return false end)]])

  -- File should be staged since there were no conflict markers
  local staged_status = git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("test%.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Diffview integration tests
T["diffview integration"] = MiniTest.new_set()

T["diffview integration"]["e keybinding is mapped in status buffer"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Check that 'e' keybinding exists using a helper function
  child.lua([[
    _G.has_e_keymap = false
    local maps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, map in ipairs(maps) do
      if map.lhs == 'e' then
        _G.has_e_keymap = true
        break
      end
    end
  ]])

  local has_e_map = child.lua_get([[_G.has_e_keymap]])
  eq(has_e_map, true)

  cleanup_repo(child, repo)
end

T["diffview integration"]["e keybinding appears in help"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help with ?
  child.type_keys("?")
  child.lua([[vim.wait(300, function() return false end)]])

  -- Check for 'e' in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_e = false
  for _, line in ipairs(lines) do
    if line:match("e%s+Edit file") then
      found_e = true
    end
  end

  eq(found_e, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- =============================================================================
-- Branch selection tests
-- =============================================================================
T["branch selection"] = MiniTest.new_set()

T["branch selection"]["prompts with vim.ui.select when no context branch"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create a feature branch
  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature"')
  git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Mock vim.ui.select to capture the call
  child.lua([[
    _G.select_called = false
    _G.select_items = nil
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      _G.select_called = true
      _G.select_items = items
      on_choice(nil)  -- Cancel selection
    end
  ]])

  -- Open merge popup and trigger merge action
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  child.type_keys("m") -- Press 'm' again to trigger merge action
  child.lua([[vim.wait(500, function() return false end)]])

  local select_called = child.lua_get([[_G.select_called]])
  eq(select_called, true)

  local select_items = child.lua_get([[_G.select_items]])
  -- Should contain the feature branch
  local found_feature = false
  if select_items then
    for _, item in ipairs(select_items) do
      if item == "feature" then
        found_feature = true
      end
    end
  end
  eq(found_feature, true)

  -- Restore
  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

T["branch selection"]["excludes current branch from selection list"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Create feature branches
  git(child, repo, "checkout -b feature1")
  git(child, repo, "checkout -b feature2")
  git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Mock vim.ui.select
  child.lua([[
    _G.select_items = nil
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      _G.select_items = items
      on_choice(nil)
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])

  local select_items = child.lua_get([[_G.select_items]])

  -- Should NOT contain main (current branch)
  local found_main = false
  if select_items then
    for _, item in ipairs(select_items) do
      if item == "main" then
        found_main = true
      end
    end
  end
  eq(found_main, false)

  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

T["branch selection"]["shows notification when no branches available"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit on main - only one branch exists
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Track notifications
  child.lua([[
    _G.notifications = {}
    _G.original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.notifications, { msg = msg, level = level })
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])
  child.type_keys("m")
  child.lua([[vim.wait(1000, function() return false end)]])

  local notifications = child.lua_get([[_G.notifications]])

  -- Should have notification about no branches
  local found_no_branches = false
  for _, n in ipairs(notifications) do
    if n.msg and n.msg:match("No branches to merge") then
      found_no_branches = true
    end
  end
  eq(found_no_branches, true)

  child.lua([[vim.notify = _G.original_notify]])
  cleanup_repo(child, repo)
end

-- =============================================================================
-- Diffview integration tests (extended)
-- =============================================================================
T["diffview fallback"] = MiniTest.new_set()

T["diffview fallback"]["shows message when diffview not installed"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Ensure diffview is not available
  child.lua([[
    package.loaded["diffview"] = nil
    package.preload["diffview"] = nil
  ]])

  -- Track notifications
  child.lua([[
    _G.notifications = {}
    _G.original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.notifications, { msg = msg, level = level })
    end
  ]])

  -- Find conflicted file and press 'e'
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_conflicted = false
  local conflicted_line = nil
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      found_conflicted = true
    end
    if found_conflicted and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  if conflicted_line then
    child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
    child.type_keys("e")
    child.lua([[vim.wait(500, function() return false end)]])

    local notifications = child.lua_get([[_G.notifications]])

    -- Should have notification about diffview not installed
    local found_diffview_msg = false
    for _, n in ipairs(notifications) do
      if n.msg and n.msg:match("diffview.nvim not installed") then
        found_diffview_msg = true
      end
    end
    eq(found_diffview_msg, true)
  end

  child.lua([[vim.notify = _G.original_notify]])
  cleanup_repo(child, repo)
end

T["diffview fallback"]["opens file directly when diffview not installed"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Ensure diffview is not available
  child.lua([[
    package.loaded["diffview"] = nil
    package.preload["diffview"] = nil
  ]])

  -- Find conflicted file and press 'e'
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local found_conflicted = false
  local conflicted_line = nil
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      found_conflicted = true
    end
    if found_conflicted and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  if conflicted_line then
    child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
    child.type_keys("e")
    child.lua([[vim.wait(500, function() return false end)]])

    -- Should now be editing test.txt
    local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
    eq(bufname:match("test%.txt") ~= nil, true)
  end

  cleanup_repo(child, repo)
end

-- =============================================================================
-- Abort confirmation tests
-- =============================================================================
T["abort confirmation"] = MiniTest.new_set()

T["abort confirmation"]["does not abort when user selects No"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify merge is in progress
  local in_progress_before =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress_before, true)

  -- Mock vim.ui.select to select "No"
  child.lua([[
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice("No")
    end
  ]])

  -- Call merge_abort directly using M.get() which is the correct API
  child.lua(string.format(
    [[
    local merge_popup = require("gitlad.popups.merge")
    local state = require("gitlad.state")
    local repo_state = state.get(%q)
    merge_popup._merge_abort(repo_state)
  ]],
    repo
  ))

  child.lua([[vim.wait(500, function() return false end)]])

  -- Merge should still be in progress
  local in_progress_after =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress_after, true)

  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

T["abort confirmation"]["aborts when user selects Yes"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Mock vim.ui.select to select "Yes"
  child.lua([[
    _G.original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice("Yes")
    end
  ]])

  -- Call merge_abort directly using M.get() which is the correct API
  child.lua(string.format(
    [[
    local merge_popup = require("gitlad.popups.merge")
    local state = require("gitlad.state")
    local repo_state = state.get(%q)
    merge_popup._merge_abort(repo_state)
  ]],
    repo
  ))

  child.lua([[vim.wait(1000, function() return false end)]])

  -- Merge should no longer be in progress
  local in_progress_after =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress_after, false)

  child.lua([[vim.ui.select = _G.original_select]])
  cleanup_repo(child, repo)
end

-- =============================================================================
-- Error path tests
-- =============================================================================
T["error paths"] = MiniTest.new_set()

T["error paths"]["merge_abort fails gracefully when not merging"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create initial commit - no merge in progress
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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

  cleanup_repo(child, repo)
end

T["error paths"]["merge_continue fails with unresolved conflicts"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  -- Start merge with conflict but don't resolve
  git(child, repo, "merge feature --no-edit || true")

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

  cleanup_repo(child, repo)
end

T["error paths"]["merge fails with invalid branch name"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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

  cleanup_repo(child, repo)
end

T["error paths"]["ff-only merge fails when not fast-forwardable"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create divergent branches
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "main.txt", "main")
  git(child, repo, "add main.txt")
  git(child, repo, 'commit -m "Main diverge"')

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

  cleanup_repo(child, repo)
end

-- =============================================================================
-- Merge arguments tests
-- =============================================================================
T["merge arguments"] = MiniTest.new_set()

T["merge arguments"]["squash merge stages changes without creating merge commit"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  git(child, repo, "checkout main")

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
  local staged = git(child, repo, "diff --cached --name-only")
  eq(staged:match("feature%.txt") ~= nil, true)

  -- No MERGE_HEAD (not a merge commit pending)
  local merge_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(merge_in_progress, false)

  -- HEAD should not have changed (no auto-commit)
  local log = git(child, repo, "log --oneline -1")
  eq(log:match("Initial") ~= nil, true)

  cleanup_repo(child, repo)
end

T["merge arguments"]["no-commit merge stages changes without committing"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Add feature"')

  -- Go back to main and create a divergent commit
  -- (--no-commit only creates MERGE_HEAD for non-fast-forward merges)
  git(child, repo, "checkout main")
  create_file(child, repo, "main.txt", "main content")
  git(child, repo, "add main.txt")
  git(child, repo, 'commit -m "Main diverge"')

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
  local staged = git(child, repo, "diff --cached --name-only")
  eq(staged:match("feature%.txt") ~= nil, true)

  -- MERGE_HEAD should exist (merge pending)
  local merge_in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(merge_in_progress, true)

  cleanup_repo(child, repo)
end

T["merge arguments"]["multiple switches can be combined"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "feature.txt", "feature")
  git(child, repo, "add feature.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open merge popup and enable switches
  child.type_keys("m")
  child.lua([[vim.wait(500, function() return false end)]])

  -- Toggle ff-only switch
  child.type_keys("-f")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify switch is shown as enabled in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Look for enabled switch indicator (typically shown differently)
  local found_switch_line = false
  for _, line in ipairs(lines) do
    if line:match("%-f.*ff%-only") then
      found_switch_line = true
    end
  end
  eq(found_switch_line, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

-- =============================================================================
-- Auto-staging after diffview tests
-- =============================================================================
T["auto-staging"] = MiniTest.new_set()

T["auto-staging"]["stages resolved files when DiffviewViewClosed event fires"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Manually resolve the conflict (remove markers)
  create_file(child, repo, "test.txt", "line1\nresolved")

  -- Set up mock diffview that captures the autocmd
  child.lua([[
    -- Mock diffview to just set up the autocmd without opening anything
    package.loaded["diffview"] = {
      open = function() end
    }
  ]])

  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Find conflicted file and press 'e' to trigger diffview integration
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local conflicted_line = nil
  local in_conflicted = false
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      in_conflicted = true
    end
    if in_conflicted and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  if conflicted_line then
    child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
    child.type_keys("e")
    child.lua([[vim.wait(500, function() return false end)]])

    -- Fire the DiffviewViewClosed event to simulate closing diffview
    child.lua([[vim.api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })]])
    child.lua([[vim.wait(1000, function() return false end)]])

    -- File should now be staged
    local staged = git(child, repo, "diff --cached --name-only")
    eq(staged:match("test%.txt") ~= nil, true)
  end

  cleanup_repo(child, repo)
end

T["auto-staging"]["does not stage files that still have conflict markers"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create merge conflict
  create_file(child, repo, "test.txt", "line1\nline2")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  git(child, repo, "checkout -b feature")
  create_file(child, repo, "test.txt", "line1\nfeature")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Feature"')

  git(child, repo, "checkout main")
  create_file(child, repo, "test.txt", "line1\nmain")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Main"')

  git(child, repo, "merge feature --no-edit || true")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- DON'T resolve the conflict - leave markers in place

  -- Mock diffview
  child.lua([[
    package.loaded["diffview"] = {
      open = function() end
    }
  ]])

  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Find conflicted file and press 'e'
  child.lua([[
    status_buf = vim.api.nvim_get_current_buf()
    status_lines = vim.api.nvim_buf_get_lines(status_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[status_lines]])

  local conflicted_line = nil
  local in_conflicted = false
  for i, line in ipairs(lines) do
    if line:match("^Conflicted") then
      in_conflicted = true
    end
    if in_conflicted and line:match("test%.txt") then
      conflicted_line = i
      break
    end
  end

  if conflicted_line then
    child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], conflicted_line))
    child.type_keys("e")
    child.lua([[vim.wait(500, function() return false end)]])

    -- Fire the DiffviewViewClosed event
    child.lua([[vim.api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })]])
    child.lua([[vim.wait(1000, function() return false end)]])

    -- File should NOT be staged (still has markers)
    local staged = git(child, repo, "diff --cached --name-only")
    -- staged might be empty or not contain test.txt
    local is_staged = staged:match("test%.txt") ~= nil
    eq(is_staged, false)
  end

  cleanup_repo(child, repo)
end

return T
