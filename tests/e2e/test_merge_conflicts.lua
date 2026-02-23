-- End-to-end tests for gitlad.nvim merge conflict handling
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

local child = MiniTest.new_child_neovim()

-- Helper to create a file in the repo
-- Helper to change directory
local function cd(child_nvim, dir)
  child_nvim.lua(string.format([[vim.cmd("cd %s")]], dir))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[require("gitlad").setup({})]])
    end,
    post_once = child.stop,
  },
})

-- Staging conflicted files tests
T["staging conflicted files"] = MiniTest.new_set()

T["staging conflicted files"]["s on conflicted file stages it (marks as resolved)"] = function()
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

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
  helpers.wait_for_var(child, "_G.gitlad_stage_complete", 1000)

  -- Verify file is now staged (in git status)
  local staged_status = helpers.git(child, repo, "diff --cached --name-only")
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

  helpers.wait_for_var(child, "_G.continue_result", 2000)
  local continue_result = child.lua_get([[_G.continue_result]])

  eq(continue_result.success, true)

  -- Verify merge is complete
  local in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress, false)

  helpers.cleanup_repo(child, repo)
end

T["staging conflicted files"]["s on Conflicted section header stages all conflicted files"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main with two files
  helpers.create_file(child, repo, "file1.txt", "content1")
  helpers.create_file(child, repo, "file2.txt", "content2")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch with conflicting changes
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "file1.txt", "feature1")
  helpers.create_file(child, repo, "file2.txt", "feature2")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Feature changes"')

  -- Go back to main and make conflicting changes
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "file1.txt", "main1")
  helpers.create_file(child, repo, "file2.txt", "main2")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Main changes"')

  -- Start merge with conflict
  helpers.git(child, repo, "merge feature --no-edit || true")

  -- Resolve conflicts manually
  helpers.create_file(child, repo, "file1.txt", "resolved1")
  helpers.create_file(child, repo, "file2.txt", "resolved2")

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
  helpers.wait_for_var(child, "_G.gitlad_stage_complete", 1000)

  -- Verify both files are now staged
  local staged_status = helpers.git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("file1%.txt") ~= nil, true)
  eq(staged_status:match("file2%.txt") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- Conflict marker safeguard tests
T["conflict marker safeguard"] = MiniTest.new_set()

T["conflict marker safeguard"]["s on file with conflict markers shows confirmation prompt"] = function()
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

  -- Start merge with conflict (file will have conflict markers)
  helpers.git(child, repo, "merge feature --no-edit || true")

  -- Verify the file has conflict markers
  local file_content = helpers.git(child, repo, "cat test.txt || cat " .. repo .. "/test.txt")
  eq(file_content:match("<<<<<<<") ~= nil, true)

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
  helpers.wait_short(child, 200)

  -- Check if vim.ui.select was called
  local ui_select_called = child.lua_get([[_G.ui_select_called]])
  eq(ui_select_called, true)

  -- Restore
  child.lua([[vim.ui.select = _G.original_ui_select]])
  helpers.cleanup_repo(child, repo)
end

T["conflict marker safeguard"]["s on resolved file without markers stages immediately"] = function()
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

  -- Resolve conflict by writing clean content (no conflict markers)
  helpers.create_file(child, repo, "test.txt", "resolved content")

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
  helpers.wait_for_var(child, "_G.gitlad_stage_complete", 1000)

  -- File should be staged since there were no conflict markers
  local staged_status = helpers.git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("test%.txt") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

-- Diffview integration tests
T["diffview integration"] = MiniTest.new_set()

T["diffview integration"]["e keybinding is mapped in status buffer"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

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

  helpers.cleanup_repo(child, repo)
end

T["diffview integration"]["e keybinding appears in help"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")
  helpers.wait_for_popup(child)

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
  helpers.cleanup_repo(child, repo)
end

-- Note: diffview fallback and auto-staging tests were removed when the
-- external diffview.nvim dependency was replaced by the native diff viewer.
-- The native merge viewer is tested via test_diff_view.lua.

return T
