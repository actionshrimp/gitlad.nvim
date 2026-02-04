-- End-to-end tests for gitlad.nvim merge conflict handling
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

local child = MiniTest.new_child_neovim()

-- Helper to create a test git repository
local function create_test_repo(child_nvim)
  local repo = child_nvim.lua_get("vim.fn.tempname()")
  child_nvim.lua(string.format(
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
local function create_file(child_nvim, repo, filename, content)
  child_nvim.lua(string.format(
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
local function git(child_nvim, repo, args)
  return child_nvim.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
end

-- Helper to cleanup repo
local function cleanup_repo(child_nvim, repo)
  child_nvim.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

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

  helpers.wait_for_var(child, "_G.continue_result", 2000)
  local continue_result = child.lua_get([[_G.continue_result]])

  eq(continue_result.success, true)

  -- Verify merge is complete
  local in_progress =
    child.lua_get(string.format([[require("gitlad.git").merge_in_progress({ cwd = %q })]], repo))
  eq(in_progress, false)

  cleanup_repo(child, repo)
end

T["staging conflicted files"]["s on Conflicted section header stages all conflicted files"] = function()
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
  local staged_status = git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("file1%.txt") ~= nil, true)
  eq(staged_status:match("file2%.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Conflict marker safeguard tests
T["conflict marker safeguard"] = MiniTest.new_set()

T["conflict marker safeguard"]["s on file with conflict markers shows confirmation prompt"] = function()
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
  cleanup_repo(child, repo)
end

T["conflict marker safeguard"]["s on resolved file without markers stages immediately"] = function()
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
  local staged_status = git(child, repo, "diff --cached --name-only")
  eq(staged_status:match("test%.txt") ~= nil, true)

  cleanup_repo(child, repo)
end

-- Diffview integration tests
T["diffview integration"] = MiniTest.new_set()

T["diffview integration"]["e keybinding is mapped in status buffer"] = function()
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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

  cleanup_repo(child, repo)
end

T["diffview integration"]["e keybinding appears in help"] = function()
  local repo = create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

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
  cleanup_repo(child, repo)
end

-- Diffview fallback tests
T["diffview fallback"] = MiniTest.new_set()

T["diffview fallback"]["shows message when diffview not installed"] = function()
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

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
    helpers.wait_short(child, 200)

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

  cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
    helpers.wait_for_buffer(child, "test%.txt")

    -- Should now be editing test.txt
    local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
    eq(bufname:match("test%.txt") ~= nil, true)
  end

  cleanup_repo(child, repo)
end

-- Auto-staging after diffview tests
T["auto-staging"] = MiniTest.new_set()

T["auto-staging"]["stages resolved files when DiffviewViewClosed event fires"] = function()
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

  cd(child, repo)

  -- Manually resolve the conflict (remove markers)
  create_file(child, repo, "test.txt", "line1\nresolved")

  -- Set up mock diffview that captures the autocmd
  child.lua([[
    -- Mock diffview to just set up the autocmd without opening anything
    package.loaded["diffview"] = {
      open = function() end
    }
  ]])

  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
    helpers.wait_short(child, 200)

    -- Fire the DiffviewViewClosed event to simulate closing diffview
    child.lua([[vim.api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })]])
    helpers.wait_short(child, 500)

    -- File should now be resolved (no longer in unmerged list)
    -- When a file is staged during merge, it's removed from the unmerged list
    local unmerged = git(child, repo, "ls-files -u")
    local is_still_unmerged = unmerged:match("test%.txt") ~= nil
    eq(is_still_unmerged, false)
  end

  cleanup_repo(child, repo)
end

T["auto-staging"]["does not stage files that still have conflict markers"] = function()
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

  cd(child, repo)

  -- DON'T resolve the conflict - leave markers in place

  -- Mock diffview
  child.lua([[
    package.loaded["diffview"] = {
      open = function() end
    }
  ]])

  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Conflicted")

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
    helpers.wait_short(child, 200)

    -- Fire the DiffviewViewClosed event
    child.lua([[vim.api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })]])
    helpers.wait_short(child, 500)

    -- File should still be unmerged (not resolved) since it has conflict markers
    -- Use git ls-files -u to check if file is still unmerged
    -- If file is in ls-files -u output, it's still conflicted (not resolved/staged)
    local unmerged = git(child, repo, "ls-files -u")
    local is_still_unmerged = unmerged:match("test%.txt") ~= nil
    eq(is_still_unmerged, true)
  end

  cleanup_repo(child, repo)
end

return T
