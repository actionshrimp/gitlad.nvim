-- End-to-end tests for gitlad.nvim cherry-pick functionality
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

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

-- Cherry-pick git operations tests
T["cherry-pick operations"] = MiniTest.new_set()

T["cherry-pick operations"]["cherry_pick picks a commit"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second branch and add a commit
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  -- Get the commit hash of the feature commit
  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to main
  helpers.git(child, repo, "checkout main")

  -- Verify feature.txt doesn't exist on main
  local exists_before =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_before, 0)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Cherry-pick the feature commit
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.cherry_pick({ %q }, {}, { cwd = %q }, function(success, output, err)
      _G.cherrypick_result = { success = success, output = output, err = err }
    end)
  ]],
    feature_hash,
    repo
  ))

  helpers.wait_for_var(child, "_G.cherrypick_result")
  local result = child.lua_get([[_G.cherrypick_result]])

  eq(result.success, true)

  -- Verify feature.txt now exists on main
  local exists_after =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_after, 1)

  -- Verify a new commit was created
  local log = helpers.git(child, repo, "log --oneline -1")
  eq(log:match("Add feature") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["cherry-pick operations"]["cherry_pick with -x adds reference"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second branch and add a commit
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to main
  helpers.git(child, repo, "checkout main")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Cherry-pick with -x flag
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.cherry_pick({ %q }, { "-x" }, { cwd = %q }, function(success, output, err)
      _G.cherrypick_result = { success = success, output = output, err = err }
    end)
  ]],
    feature_hash,
    repo
  ))

  helpers.wait_for_var(child, "_G.cherrypick_result")
  local result = child.lua_get([[_G.cherrypick_result]])

  eq(result.success, true)

  -- Verify commit message contains cherry-picked from reference
  local log = helpers.git(child, repo, "log -1 --format=%B")
  eq(log:match("cherry picked from commit") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["cherry-pick operations"]["cherry_pick_continue continues after conflict resolution"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello\nworld")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "hello\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "hello\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Cherry-pick should fail with conflict
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.cherry_pick({ %q }, {}, { cwd = %q }, function(success, output, err)
      _G.cherrypick_result = { success = success, output = output, err = err }
    end)
  ]],
    feature_hash,
    repo
  ))

  helpers.wait_for_var(child, "_G.cherrypick_result")
  local result = child.lua_get([[_G.cherrypick_result]])

  -- Should fail due to conflict
  eq(result.success, false)

  -- Check that CHERRY_PICK_HEAD exists (in progress)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      _G.seq_state = state
    end)
  ]],
    repo
  ))
  helpers.wait_for_var(child, "_G.seq_state")
  local seq_state = child.lua_get([[_G.seq_state]])
  eq(seq_state.cherry_pick_in_progress, true)

  -- Resolve conflict manually
  helpers.create_file(child, repo, "test.txt", "hello\nresolved")
  helpers.git(child, repo, "add test.txt")

  -- Continue cherry-pick
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.cherry_pick_continue({ cwd = %q }, function(success, err)
      _G.continue_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.continue_result")
  local continue_result = child.lua_get([[_G.continue_result]])

  eq(continue_result.success, true)

  -- Verify cherry-pick is no longer in progress
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      _G.seq_state_after = state
    end)
  ]],
    repo
  ))
  helpers.wait_for_var(child, "_G.seq_state_after")
  local seq_state_after = child.lua_get([[_G.seq_state_after]])
  eq(seq_state_after.cherry_pick_in_progress, false)

  helpers.cleanup_repo(child, repo)
end

T["cherry-pick operations"]["cherry_pick_abort aborts in-progress cherry-pick"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "test.txt", "hello\nworld")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a feature branch with conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "hello\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "hello\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  local main_head = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Cherry-pick should fail with conflict
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.cherry_pick({ %q }, {}, { cwd = %q }, function(success, output, err)
      _G.cherrypick_result = { success = success, output = output, err = err }
    end)
  ]],
    feature_hash,
    repo
  ))

  helpers.wait_for_var(child, "_G.cherrypick_result")

  -- Abort cherry-pick
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.cherry_pick_abort({ cwd = %q }, function(success, err)
      _G.abort_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.abort_result")
  local abort_result = child.lua_get([[_G.abort_result]])

  eq(abort_result.success, true)

  -- Verify HEAD is back to where it was
  local head_after = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")
  eq(head_after, main_head)

  -- Verify cherry-pick is no longer in progress
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      _G.seq_state = state
    end)
  ]],
    repo
  ))
  helpers.wait_for_var(child, "_G.seq_state")
  local seq_state = child.lua_get([[_G.seq_state]])
  eq(seq_state.cherry_pick_in_progress, false)

  helpers.cleanup_repo(child, repo)
end

-- Revert git operations tests
T["revert operations"] = MiniTest.new_set()

T["revert operations"]["revert reverts a commit"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second commit to revert
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  local feature_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Verify feature.txt exists
  local exists_before =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_before, 1)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Revert the feature commit
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.revert({ %q }, { "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.revert_result = { success = success, output = output, err = err }
    end)
  ]],
    feature_hash,
    repo
  ))

  helpers.wait_for_var(child, "_G.revert_result")
  local result = child.lua_get([[_G.revert_result]])

  eq(result.success, true)

  -- Verify feature.txt is now deleted
  local exists_after =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_after, 0)

  -- Verify a revert commit was created
  local log = helpers.git(child, repo, "log --oneline -1")
  eq(log:match('Revert "Add feature"') ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["revert operations"]["revert_abort aborts in-progress revert"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "line1\nline2")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a commit that modifies the file
  helpers.create_file(child, repo, "test.txt", "line1\nmodified")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Modify file"')

  local modify_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Create another commit that conflicts with reverting the previous
  helpers.create_file(child, repo, "test.txt", "line1\nmodified\nmore")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Add more"')

  local head_before = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Revert the middle commit (should conflict)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.revert({ %q }, { "--no-edit" }, { cwd = %q }, function(success, output, err)
      _G.revert_result = { success = success, output = output, err = err }
    end)
  ]],
    modify_hash,
    repo
  ))

  helpers.wait_for_var(child, "_G.revert_result")
  local result = child.lua_get([[_G.revert_result]])

  -- Should fail due to conflict
  eq(result.success, false)

  -- Check that revert is in progress
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      _G.seq_state = state
    end)
  ]],
    repo
  ))
  helpers.wait_for_var(child, "_G.seq_state")
  local seq_state = child.lua_get([[_G.seq_state]])
  eq(seq_state.revert_in_progress, true)

  -- Abort revert
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.revert_abort({ cwd = %q }, function(success, err)
      _G.abort_result = { success = success, err = err }
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.abort_result")
  local abort_result = child.lua_get([[_G.abort_result]])

  eq(abort_result.success, true)

  -- Verify HEAD is back to where it was
  local head_after = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")
  eq(head_after, head_before)

  helpers.cleanup_repo(child, repo)
end

T["revert operations"]["get_sequencer_state returns correct state"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Check sequencer state when nothing in progress
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.get_sequencer_state({ cwd = %q }, function(state)
      _G.seq_state = state
    end)
  ]],
    repo
  ))

  helpers.wait_for_var(child, "_G.seq_state")
  local seq_state = child.lua_get([[_G.seq_state]])

  eq(seq_state.cherry_pick_in_progress, false)
  eq(seq_state.revert_in_progress, false)
  -- sequencer_head_oid is nil when no sequencer is in progress
  -- lua_get returns vim.NIL for nil values from child, so check both
  local oid_is_nil = seq_state.sequencer_head_oid == nil or seq_state.sequencer_head_oid == vim.NIL
  eq(oid_is_nil, true)

  helpers.cleanup_repo(child, repo)
end

-- Cherry-pick popup UI tests
T["cherrypick popup"] = MiniTest.new_set()

T["cherrypick popup"]["opens from status buffer with A key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Press A to open cherry-pick popup
  child.type_keys("A")

  -- Wait for async popup to open
  helpers.wait_for_popup(child)

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains cherry-pick-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_pick = false
  local found_apply = false
  for _, line in ipairs(lines) do
    if line:match("A%s+Pick") then
      found_pick = true
    end
    if line:match("a%s+Apply") then
      found_apply = true
    end
  end

  eq(found_pick, true)
  eq(found_apply, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["cherrypick popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("A")
  helpers.wait_for_popup(child)

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_x = false
  local found_edit = false
  local found_signoff = false

  for _, line in ipairs(lines) do
    if line:match("%-x%s") then
      found_x = true
    end
    if line:match("%-e.*edit") then
      found_edit = true
    end
    if line:match("%-s.*signoff") then
      found_signoff = true
    end
  end

  eq(found_x, true)
  eq(found_edit, true)
  eq(found_signoff, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["cherrypick popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open cherry-pick popup
  child.type_keys("A")
  helpers.wait_for_popup(child)
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  helpers.wait_for_popup_closed(child)

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["cherrypick popup"]["A keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")
  helpers.wait_for_popup(child)

  -- Check for cherry-pick in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_cherrypick = false
  for _, line in ipairs(lines) do
    if line:match("A%s+Cherry%-pick") then
      found_cherrypick = true
    end
  end

  eq(found_cherrypick, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

-- Revert popup UI tests
T["revert popup"] = MiniTest.new_set()

T["revert popup"]["opens from status buffer with O key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Press V to open revert popup
  child.type_keys("_")

  -- Wait for async popup to open
  helpers.wait_for_popup(child)

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains revert-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_revert = false
  local found_no_commit = false
  for _, line in ipairs(lines) do
    -- Action key in popup is 'V' for Revert
    if line:match("V%s+Revert") then
      found_revert = true
    end
    if line:match("v%s+Revert changes") then
      found_no_commit = true
    end
  end

  eq(found_revert, true)
  eq(found_no_commit, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["revert popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("_")
  helpers.wait_for_popup(child)

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_edit = false
  local found_no_edit = false
  local found_signoff = false

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
  end

  eq(found_edit, true)
  eq(found_no_edit, true)
  eq(found_signoff, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["revert popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open revert popup
  child.type_keys("_")
  helpers.wait_for_popup(child)
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  helpers.wait_for_popup_closed(child)

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["revert popup"]["O keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")
  helpers.wait_for_popup(child)

  -- Check for revert in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_revert = false
  for _, line in ipairs(lines) do
    if line:match("_%s+Revert") then
      found_revert = true
    end
  end

  eq(found_revert, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

return T
