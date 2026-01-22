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

return T
