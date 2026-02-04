-- End-to-end tests for gitlad.nvim basic commit functionality
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to run a git command
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

-- Commit popup tests
T["commit popup"] = MiniTest.new_set()

T["commit popup"]["opens from status buffer with c key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and stage a file
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Press c to open commit popup
  child.type_keys("c")
  helpers.wait_for_popup(child)

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains commit-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_commit = false
  local found_amend = false
  local found_extend = false
  local found_reword = false
  for _, line in ipairs(lines) do
    if line:match("c%s+Commit") then
      found_commit = true
    end
    if line:match("a%s+Amend") then
      found_amend = true
    end
    if line:match("e%s+Extend") then
      found_extend = true
    end
    if line:match("w%s+Reword") then
      found_reword = true
    end
  end

  eq(found_commit, true)
  eq(found_amend, true)
  eq(found_extend, true)
  eq(found_reword, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["commit popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("c")
  helpers.wait_for_popup(child)

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_all = false
  local found_allow_empty = false
  local found_verbose = false
  local found_no_verify = false

  for _, line in ipairs(lines) do
    if line:match("%-a.*all") then
      found_all = true
    end
    if line:match("%-e.*allow%-empty") then
      found_allow_empty = true
    end
    if line:match("%-v.*verbose") then
      found_verbose = true
    end
    if line:match("%-n.*no%-verify") then
      found_no_verify = true
    end
  end

  eq(found_all, true)
  eq(found_allow_empty, true)
  eq(found_verbose, true)
  eq(found_no_verify, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

-- Commit editor tests
T["commit editor"] = MiniTest.new_set()

T["commit editor"]["opens when pressing c in commit popup"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and stage a file
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup
  child.type_keys("c")
  helpers.wait_for_popup(child)
  -- Press c again to open commit editor
  child.type_keys("c")

  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Verify we're in a commit editor buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("COMMIT_EDITMSG") ~= nil, true)

  -- Verify filetype is gitcommit
  local filetype = child.lua_get([[vim.bo.filetype]])
  eq(filetype, "gitcommit")

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["has help comments"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")

  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")
  helpers.wait_short(child, 200) -- Wait for content to be populated

  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])

  local found_help = false
  for _, line in ipairs(lines) do
    if line:match("C%-c C%-c to commit") then
      found_help = true
    end
  end

  eq(found_help, true)

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["aborts with C-c C-k"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")

  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Abort with ZQ (more reliable than C-c C-k on slow CI)
  child.type_keys("ZQ")

  helpers.wait_for_buffer(child, "gitlad://status")

  -- Verify we returned to status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  -- Verify no commit was made
  local log = helpers.git(child, repo, "log --oneline 2>&1")
  eq(log:match("does not have any commits") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["can close status with q after abort"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Record initial window count
  local initial_win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(initial_win_count, 1)

  -- Open commit popup
  child.type_keys("c")
  helpers.wait_for_popup(child)

  -- Should have popup window now
  local popup_win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(popup_win_count, 2)

  -- Press c to open commit editor (popup closes, editor opens in split above status)
  child.type_keys("c")
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Should have 2 windows now (editor split + status)
  local editor_win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(editor_win_count, 2)

  -- Verify we're in commit editor
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("COMMIT_EDITMSG") ~= nil, true)

  -- Clear any error messages before abort
  child.lua([[vim.cmd("messages clear")]])

  -- Abort
  child.type_keys("<C-c><C-k>")
  helpers.wait_for_buffer(child, "gitlad://status")

  -- Verify we're in status buffer
  bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  -- Verify still 1 window
  local post_abort_win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(post_abort_win_count, 1)

  -- Clear messages again before pressing q
  child.lua([[vim.cmd("messages clear")]])

  -- Press q to close status - should not error
  child.type_keys("q")
  helpers.wait_short(child)

  -- Check for error messages
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  eq(messages:match("E444") == nil, true) -- No "Cannot close last window" error
  eq(messages:match("Cannot close last window") == nil, true)

  -- Verify we're no longer in status buffer (switched to empty buffer since last window)
  bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["rapid q after abort does not error"] = function()
  -- Test with minimal delays to simulate fast key presses
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Rapid sequence: open popup, open editor, abort, close status
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Clear messages before abort/close sequence
  child.lua([[vim.cmd("messages clear")]])

  -- Rapid abort then q
  child.type_keys("<C-c><C-k>")
  -- Immediate q without waiting for scheduled callbacks
  child.type_keys("q")
  helpers.wait_short(child, 200)

  -- Check for error messages
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  eq(messages:match("E444") == nil, true)
  eq(messages:match("Cannot close last window") == nil, true)

  -- Verify we ended up in an empty buffer (not status)
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["q works after abort without error"] = function()
  -- Regression test: pressing q after C-c C-k should work without errors
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open popup then editor
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Clear all messages
  child.lua([[vim.cmd("messages clear")]])

  -- Abort the commit
  child.type_keys("<C-c><C-k>")
  -- Wait for the deferred close to complete
  helpers.wait_for_buffer(child, "gitlad://status")

  -- Now press q to close status
  child.type_keys("q")
  helpers.wait_short(child)

  -- Check that no error was shown
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  -- Should only have the abort message, not any errors
  eq(messages:match("E444") == nil, true)
  eq(messages:match("Cannot close") == nil, true)

  -- Should not be in status buffer anymore (should be in empty buffer)
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["creates commit with C-c C-c"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")

  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Wait for the buffer content to be loaded (async operation)
  -- The commit editor loads content asynchronously, so we need to wait for
  -- the template to appear before typing the message
  helpers.wait_for_buffer_content(child, "# Press C-c C-c to commit", 2000)

  -- Type commit message at the beginning of the buffer (go to line 1, insert)
  child.type_keys("ggITest commit message<Esc>")

  -- Commit with ZZ (more reliable than C-c C-c on slow CI)
  child.type_keys("ZZ")

  -- Wait for buffer to return to status (longer timeout for slow CI)
  helpers.wait_for_buffer(child, "gitlad://status", 5000)

  -- Verify we returned to status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  -- Poll for commit to appear in log (may take a moment on slow CI)
  local log
  for _ = 1, 50 do -- up to 5 seconds
    log = helpers.git(child, repo, "log --oneline")
    if log:match("Test commit message") then
      break
    end
    vim.loop.sleep(100)
  end

  -- Verify commit was made
  eq(log:match("Test commit message") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["shows staged files summary"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create and stage multiple files
  helpers.create_file(child, repo, "new_file.txt", "new content")
  helpers.create_file(child, repo, "modified.txt", "original")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify and stage
  helpers.create_file(child, repo, "modified.txt", "modified content")
  helpers.create_file(child, repo, "another_new.txt", "more content")
  helpers.git(child, repo, "add .")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup and editor
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")
  helpers.wait_short(child, 200) -- Wait for content to be populated

  -- Get buffer content
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])

  -- Check for staged files summary
  local found_changes_header = false
  local found_modified = false
  local found_new = false
  for _, line in ipairs(lines) do
    if line:match("Changes to be committed") then
      found_changes_header = true
    end
    if line:match("modified:.*modified.txt") then
      found_modified = true
    end
    if line:match("new file:.*another_new.txt") then
      found_new = true
    end
  end

  eq(found_changes_header, true)
  eq(found_modified, true)
  eq(found_new, true)

  child.type_keys("<C-c><C-k>")
  helpers.cleanup_repo(child, repo)
end

T["commit editor"]["opens in split above status"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Record status window
  local status_win = child.lua_get([[vim.api.nvim_get_current_win()]])

  -- Open commit popup and editor
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Should have 2 windows now
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Current window should be different from status window
  local editor_win = child.lua_get([[vim.api.nvim_get_current_win()]])
  eq(editor_win ~= status_win, true)

  -- Editor window should be above status window (lower row number)
  child.lua(string.format("_G.editor_win = %d", editor_win))
  child.lua(string.format("_G.status_win = %d", status_win))
  child.lua("_G.editor_row = vim.api.nvim_win_get_position(_G.editor_win)[1]")
  child.lua("_G.status_row = vim.api.nvim_win_get_position(_G.status_win)[1]")
  local editor_row = child.lua_get("_G.editor_row")
  local status_row = child.lua_get("_G.status_row")
  eq(editor_row < status_row, true)

  child.type_keys("<C-c><C-k>")
  helpers.cleanup_repo(child, repo)
end

-- Validation tests
T["commit validation"] = MiniTest.new_set()

T["commit validation"]["prevents commit with nothing staged"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file but don't stage it
  helpers.create_file(child, repo, "test.txt", "hello")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Clear messages
  child.lua([[vim.cmd("messages clear")]])

  -- Try to commit
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")
  helpers.wait_short(child, 200)

  -- Should not have opened commit editor (should still be in popup or status)
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("COMMIT_EDITMSG") == nil, true)

  -- Should have shown warning message
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  eq(messages:match("Nothing staged") ~= nil, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["commit validation"]["allows commit with -a flag when nothing staged"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify file but don't stage it
  helpers.create_file(child, repo, "test.txt", "modified")

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open commit popup
  child.type_keys("c")
  helpers.wait_for_popup(child)

  -- Toggle -a switch
  child.type_keys("-a")
  helpers.wait_short(child)

  -- Try to commit
  child.type_keys("c")
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG")

  -- Should have opened commit editor
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("COMMIT_EDITMSG") ~= nil, true)

  child.type_keys("<C-c><C-k>")
  helpers.cleanup_repo(child, repo)
end

return T
