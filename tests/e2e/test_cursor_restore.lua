-- End-to-end tests for cursor position and expansion state preservation across refreshes
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")

local function assert_truthy(val, msg)
  if not val then
    error(msg or ("Expected truthy value, got: " .. tostring(val)), 2)
  end
end

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

local function get_buffer_lines(child)
  return child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
end

local function find_line_with(lines, pattern)
  for i, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return i, line
    end
  end
  return nil, nil
end

local function open_gitlad(child, repo, expected_content)
  child.cmd("cd " .. repo)
  child.cmd("Gitlad")
  if expected_content then
    helpers.wait_for_status_content(child, expected_content)
  else
    helpers.wait_for_status(child)
  end
end

--- Trigger a refresh by calling repo_state:refresh_status(true) directly
--- Then wait for the status buffer to finish rendering
local function trigger_refresh(child)
  child.lua([[
    local state = require("gitlad.state")
    local rs = state.get()
    if rs then rs:refresh_status(true) end
  ]])
  -- Wait for the refresh to complete (status buffer re-renders with Head: line)
  helpers.wait_for_status(child)
  -- Small delay for cursor restore to complete
  helpers.wait_short(child, 300)
end

-- =============================================================================
-- Refresh preserves cursor position
-- =============================================================================

T["cursor restore"] = MiniTest.new_set()

T["cursor restore"]["refresh preserves cursor on same file"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.txt", "original\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.create_file(child, repo, "aaa.txt", "aaa\n")
  helpers.create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo, "file.txt")

  -- Navigate to file.txt specifically
  local file_line = helpers.goto_line_with(child, "file.txt")
  assert_truthy(file_line, "Should find file.txt")

  -- Trigger refresh
  trigger_refresh(child)

  -- Cursor should still be on file.txt after refresh
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  local lines = get_buffer_lines(child)
  local current_text = lines[cursor_line]
  assert_truthy(
    current_text and current_text:find("file.txt", 1, true),
    "Cursor should be on file.txt line after refresh, got: " .. tostring(current_text)
  )
end

T["cursor restore"]["refresh preserves diff expansion"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.txt", "line1\nline2\nline3\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.create_file(child, repo, "file.txt", "line1\nline2 modified\nline3\n")

  open_gitlad(child, repo, "file.txt")

  -- Expand diff
  local file_line = helpers.goto_line_with(child, "file.txt")
  assert_truthy(file_line, "Should find file.txt")
  child.type_keys("<Tab>")
  helpers.wait_for_diff_expanded(child)

  -- Verify diff is expanded
  local lines = get_buffer_lines(child)
  assert_truthy(find_line_with(lines, "@@"), "Diff should be expanded before refresh")

  -- Trigger refresh
  trigger_refresh(child)

  -- Diff should still be expanded after refresh
  lines = get_buffer_lines(child)
  assert_truthy(find_line_with(lines, "@@"), "Diff should still be expanded after refresh")
  assert_truthy(
    find_line_with(lines, "+line2 modified"),
    "Diff content should still be visible after refresh"
  )
end

-- =============================================================================
-- Staging preserves other expansions
-- =============================================================================

T["staging preserves expansion"] = MiniTest.new_set()

T["staging preserves expansion"]["staging file B does not collapse expanded diff on file A"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "a.txt", "aaa\n")
  helpers.create_file(child, repo, "b.txt", "bbb\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Modify both files
  helpers.create_file(child, repo, "a.txt", "aaa modified\n")
  helpers.create_file(child, repo, "b.txt", "bbb modified\n")

  open_gitlad(child, repo, "a.txt")

  -- Navigate to a.txt and expand its diff
  local a_line = helpers.goto_line_with(child, "a.txt")
  assert_truthy(a_line, "Should find a.txt")
  child.type_keys("<Tab>")
  helpers.wait_for_diff_expanded(child)

  -- Verify a.txt diff is expanded
  local lines = get_buffer_lines(child)
  assert_truthy(find_line_with(lines, "+aaa modified"), "a.txt diff should be visible")

  -- Now navigate to b.txt and stage it
  local b_line = helpers.goto_line_with(child, "b.txt")
  assert_truthy(b_line, "Should find b.txt")
  child.type_keys("s")

  -- Wait for staging to complete
  helpers.wait_for_status_content(child, "Staged")
  helpers.wait_short(child, 300)

  -- a.txt diff should still be expanded
  lines = get_buffer_lines(child)
  assert_truthy(
    find_line_with(lines, "+aaa modified"),
    "a.txt diff should still be visible after staging b.txt"
  )
end

-- =============================================================================
-- Post-commit cursor position
-- =============================================================================

T["post-commit cursor"] = MiniTest.new_set()

T["post-commit cursor"]["after commit cursor lands on reasonable position"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.txt", "content\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Stage a new file
  helpers.create_file(child, repo, "new.txt", "new content\n")
  helpers.git(child, repo, "add new.txt")

  -- Also create an unstaged file so buffer isn't empty after commit
  helpers.create_file(child, repo, "unstaged.txt", "unstaged\n")

  open_gitlad(child, repo, "new.txt")

  -- Navigate to the staged file
  local staged_line = helpers.goto_line_with(child, "new.txt")
  assert_truthy(staged_line, "Should find new.txt in staged")

  -- Commit via git directly and then refresh
  helpers.git(child, repo, 'commit -m "Add new file"')
  trigger_refresh(child)

  -- Cursor should not be on line 0 or invalid - it should be somewhere reasonable
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(
    cursor_line >= 1,
    "Cursor should be on a valid line, got: " .. tostring(cursor_line)
  )

  -- Buffer should show the unstaged file
  local lines = get_buffer_lines(child)
  assert_truthy(find_line_with(lines, "unstaged.txt"), "Should show unstaged file after commit")
end

-- =============================================================================
-- Section header cursor preservation
-- =============================================================================

T["section header cursor"] = MiniTest.new_set()

T["section header cursor"]["cursor on section header survives refresh"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.txt", "original\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.create_file(child, repo, "file.txt", "modified\n")

  open_gitlad(child, repo, "Unstaged")

  -- Navigate to the Unstaged section header
  local section_line = helpers.goto_line_with(child, "Unstaged")
  assert_truthy(section_line, "Should find Unstaged section header")

  -- Verify cursor is on section header
  local lines = get_buffer_lines(child)
  local cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  assert_truthy(lines[cursor_line]:find("Unstaged", 1, true), "Cursor should be on Unstaged header")

  -- Trigger refresh
  trigger_refresh(child)

  -- Cursor should still be on Unstaged section header
  cursor_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  lines = get_buffer_lines(child)
  assert_truthy(
    lines[cursor_line] and lines[cursor_line]:find("Unstaged", 1, true),
    "Cursor should still be on Unstaged header after refresh, got: " .. tostring(lines[cursor_line])
  )
end

return T
