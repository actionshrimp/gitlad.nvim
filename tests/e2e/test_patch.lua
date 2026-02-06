-- End-to-end tests for gitlad.nvim patch functionality
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
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

-- format-patch tests
T["format-patch operations"] = MiniTest.new_set()

T["format-patch operations"]["format_patch creates patch files"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create a second commit
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Create patch for last commit
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.format_patch("-1", { "-o", %q .. "/patches" }, { cwd = %q }, function(success, output, err)
      _G.format_result = { success = success, output = output, err = err }
    end)
  ]],
    repo,
    repo
  ))

  helpers.wait_for_var(child, "_G.format_result")
  local result = child.lua_get([[_G.format_result]])

  eq(result.success, true)
  -- Output should contain the patch filename
  eq(result.output:match("0001%-Add%-feature.patch") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["format-patch operations"]["format_patch with range creates multiple patches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Get the initial commit hash for range
  local initial_hash = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  -- Create two more commits
  helpers.create_file(child, repo, "a.txt", "aaa")
  helpers.git(child, repo, "add a.txt")
  helpers.git(child, repo, 'commit -m "Add a"')

  helpers.create_file(child, repo, "b.txt", "bbb")
  helpers.git(child, repo, "add b.txt")
  helpers.git(child, repo, 'commit -m "Add b"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Create patches for last 2 commits
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.format_patch("-2", { "-o", %q .. "/patches" }, { cwd = %q }, function(success, output, err)
      _G.format_result = { success = success, output = output, err = err }
    end)
  ]],
    repo,
    repo
  ))

  helpers.wait_for_var(child, "_G.format_result")
  local result = child.lua_get([[_G.format_result]])

  eq(result.success, true)
  -- Should have 2 patches
  eq(result.output:match("0001") ~= nil, true)
  eq(result.output:match("0002") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- apply (plain patch) tests
T["apply operations"] = MiniTest.new_set()

T["apply operations"]["apply_patch_file applies a patch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Make a change and create a patch
  helpers.create_file(child, repo, "test.txt", "hello world")
  helpers.git(child, repo, "diff > " .. repo .. "/test.patch")
  -- Reset the change
  helpers.git(child, repo, "checkout -- test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Apply the patch
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.apply_patch_file(%q .. "/test.patch", {}, { cwd = %q }, function(success, output, err)
      _G.apply_result = { success = success, output = output, err = err }
    end)
  ]],
    repo,
    repo
  ))

  helpers.wait_for_var(child, "_G.apply_result")
  local result = child.lua_get([[_G.apply_result]])

  eq(result.success, true)

  -- Verify the file was changed
  local content = child.lua_get(string.format([[vim.fn.readfile(%q .. "/test.txt")]], repo))
  eq(content[1], "hello world")

  helpers.cleanup_repo(child, repo)
end

T["apply operations"]["apply_patch_file with reverse undoes a patch"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Make a change, save the patch, then commit
  helpers.create_file(child, repo, "test.txt", "hello world")
  helpers.git(child, repo, "diff > " .. repo .. "/test.patch")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Add world"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Apply the patch in reverse
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.apply_patch_file(%q .. "/test.patch", { "--reverse" }, { cwd = %q }, function(success, output, err)
      _G.apply_result = { success = success, output = output, err = err }
    end)
  ]],
    repo,
    repo
  ))

  helpers.wait_for_var(child, "_G.apply_result")
  local result = child.lua_get([[_G.apply_result]])

  eq(result.success, true)

  -- Verify the file was reverted
  local content = child.lua_get(string.format([[vim.fn.readfile(%q .. "/test.txt")]], repo))
  eq(content[1], "hello")

  helpers.cleanup_repo(child, repo)
end

-- git am tests
T["am operations"] = MiniTest.new_set()

T["am operations"]["am applies a format-patch and creates a commit"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a branch with a commit
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature content")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature file"')

  -- Create patch from that commit
  helpers.git(child, repo, "format-patch -1 -o " .. repo .. "/patches")

  -- Go back to main
  helpers.git(child, repo, "checkout main")

  -- Verify feature.txt doesn't exist on main
  local exists_before =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_before, 0)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Apply the patch via git am
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.am({ %q .. "/patches/0001-Add-feature-file.patch" }, {}, { cwd = %q }, function(success, output, err)
      _G.am_result = { success = success, output = output, err = err }
    end)
  ]],
    repo,
    repo
  ))

  helpers.wait_for_var(child, "_G.am_result")
  local result = child.lua_get([[_G.am_result]])

  eq(result.success, true)

  -- Verify the commit was created
  local log = helpers.git(child, repo, "log --oneline -1")
  eq(log:match("Add feature file") ~= nil, true)

  -- Verify the file exists
  local exists_after =
    child.lua_get(string.format([[vim.fn.filereadable(%q .. "/feature.txt")]], repo))
  eq(exists_after, 1)

  helpers.cleanup_repo(child, repo)
end

T["am operations"]["am_abort aborts in-progress am"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello\nworld")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a branch with a conflicting change
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "test.txt", "hello\nfeature")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Create patch
  helpers.git(child, repo, "format-patch -1 -o " .. repo .. "/patches")

  -- Go back to main and make conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "test.txt", "hello\nmain")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  local head_before = helpers.git(child, repo, "rev-parse HEAD"):gsub("%s+", "")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Apply patch (should conflict)
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.am({ %q .. "/patches/0001-Feature-change.patch" }, {}, { cwd = %q }, function(success, output, err)
      _G.am_result = { success = success, output = output, err = err }
    end)
  ]],
    repo,
    repo
  ))

  helpers.wait_for_var(child, "_G.am_result")
  local result = child.lua_get([[_G.am_result]])
  eq(result.success, false)

  -- Abort
  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    git.am_abort({ cwd = %q }, function(success, err)
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

-- Sequencer state detection
T["am state detection"] = MiniTest.new_set()

T["am state detection"]["detects am not in progress"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

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

  eq(seq_state.am_in_progress, false)

  helpers.cleanup_repo(child, repo)
end

-- Popup UI tests
T["patch popup UI"] = MiniTest.new_set()

T["patch popup UI"]["opens from status buffer with W key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Press W to open patch popup
  child.type_keys("W")
  helpers.wait_for_popup(child)

  -- Verify popup window exists
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains patch-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_create = false
  local found_apply = false
  local found_save = false
  for _, line in ipairs(lines) do
    if line:match("c%s+Create patches") then
      found_create = true
    end
    if line:match("a%s+Apply plain patch") then
      found_apply = true
    end
    if line:match("s%s+Save diff as patch") then
      found_save = true
    end
  end

  eq(found_create, true)
  eq(found_apply, true)
  eq(found_save, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["patch popup UI"]["W keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")
  helpers.wait_for_popup(child)

  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_patch = false
  local found_am = false
  for _, line in ipairs(lines) do
    if line:match("W%s+Patch") then
      found_patch = true
    end
    if line:match("w%s+Apply patches") then
      found_am = true
    end
  end

  eq(found_patch, true)
  eq(found_am, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["patch popup UI"]["am popup opens from status buffer with w key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Press w to open am popup
  child.type_keys("w")
  helpers.wait_for_popup(child)

  -- Verify popup window exists
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains am-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_apply = false
  local found_maildir = false
  for _, line in ipairs(lines) do
    if line:match("w%s+Apply patch file") then
      found_apply = true
    end
    if line:match("m%s+Apply maildir") then
      found_maildir = true
    end
  end

  eq(found_apply, true)
  eq(found_maildir, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["patch popup UI"]["patch popup closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open and close patch popup
  child.type_keys("W")
  helpers.wait_for_popup(child)
  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  child.type_keys("q")
  helpers.wait_for_popup_closed(child)

  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

return T
