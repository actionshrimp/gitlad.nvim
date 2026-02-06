-- End-to-end tests for gitlad.nvim worktree status section
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to get status buffer lines
local function get_status_lines(child)
  return child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
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

-- Worktree status tests
T["worktree status section"] = MiniTest.new_set()

T["worktree status section"]["hidden when only main worktree exists"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (required for worktrees)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Get status lines
  local lines = get_status_lines(child)

  -- Verify Worktrees section is NOT present (only 1 worktree)
  local found_worktrees = false
  for _, line in ipairs(lines) do
    if line:match("^Worktrees") then
      found_worktrees = true
      break
    end
  end

  eq(found_worktrees, false)

  helpers.cleanup_repo(child, repo)
end

T["worktree status section"]["shown when 2+ worktrees exist"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (required for worktrees)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second worktree
  local worktree_path = child.lua_get("vim.fn.tempname()")
  helpers.git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Get status lines
  local lines = get_status_lines(child)

  -- Verify Worktrees section IS present (2 worktrees now)
  local found_worktrees = false
  for _, line in ipairs(lines) do
    if line:match("^Worktrees") then
      found_worktrees = true
      break
    end
  end

  eq(found_worktrees, true)

  -- Cleanup
  helpers.git(child, repo, string.format("worktree remove %s", worktree_path))
  helpers.cleanup_repo(child, repo)
end

T["worktree status section"]["shows current worktree with marker"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (required for worktrees)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second worktree
  local worktree_path = child.lua_get("vim.fn.tempname()")
  helpers.git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Get status lines and find the current worktree line
  local lines = get_status_lines(child)

  -- Find the line number of the current worktree (the main branch in this repo)
  local current_wt_line = nil
  local in_worktrees_section = false
  for i, line in ipairs(lines) do
    if line:match("^Worktrees") then
      in_worktrees_section = true
    elseif in_worktrees_section then
      if line == "" then
        break
      end
      -- The main branch worktree is the current one (we cd'd into it)
      if line:match("^main%s") or line:match("^master%s") then
        current_wt_line = i
        break
      end
    end
  end

  -- Verify the current worktree has a "*" sign in the gutter (via extmark)
  child.lua(string.format(
    [[
    local ns = vim.api.nvim_get_namespaces()["gitlad_signs"]
    _G._test_found_sign = false
    if ns then
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, {%d, 0}, {%d, 0}, { details = true })
      for _, mark in ipairs(marks) do
        if mark[4] and mark[4].sign_text and vim.trim(mark[4].sign_text) == "*" then
          _G._test_found_sign = true
        end
      end
    end
  ]],
    current_wt_line - 1,
    current_wt_line - 1
  ))
  local found_current_sign = child.lua_get("_G._test_found_sign")

  eq(found_current_sign, true)

  -- Cleanup
  helpers.git(child, repo, string.format("worktree remove %s", worktree_path))
  helpers.cleanup_repo(child, repo)
end

T["worktree status section"]["can be collapsed and expanded"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit (required for worktrees)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create a second worktree
  local worktree_path = child.lua_get("vim.fn.tempname()")
  helpers.git(child, repo, string.format("worktree add -b feature %s", worktree_path))

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  helpers.wait_for_status(child)

  -- Find and go to Worktrees section header
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("^Worktrees") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Count lines before collapse
  local lines_before = get_status_lines(child)
  local worktree_lines_before = 0
  local in_worktrees_section = false
  for _, line in ipairs(lines_before) do
    if line:match("^Worktrees") then
      in_worktrees_section = true
    elseif in_worktrees_section then
      if line == "" then
        break
      end
      worktree_lines_before = worktree_lines_before + 1
    end
  end

  -- Press TAB to collapse
  child.type_keys("<Tab>")
  helpers.wait_short(child, 200)

  -- Count lines after collapse
  local lines_after = get_status_lines(child)
  local worktree_lines_after = 0
  in_worktrees_section = false
  for _, line in ipairs(lines_after) do
    if line:match("^Worktrees") then
      in_worktrees_section = true
    elseif in_worktrees_section then
      if line == "" then
        break
      end
      worktree_lines_after = worktree_lines_after + 1
    end
  end

  -- After collapse, there should be fewer worktree lines
  eq(worktree_lines_after < worktree_lines_before, true)

  -- Press TAB again to expand
  child.type_keys("<Tab>")
  helpers.wait_short(child, 200)

  -- Count lines after expand
  local lines_expanded = get_status_lines(child)
  local worktree_lines_expanded = 0
  in_worktrees_section = false
  for _, line in ipairs(lines_expanded) do
    if line:match("^Worktrees") then
      in_worktrees_section = true
    elseif in_worktrees_section then
      if line == "" then
        break
      end
      worktree_lines_expanded = worktree_lines_expanded + 1
    end
  end

  -- After expand, should be back to original count
  eq(worktree_lines_expanded, worktree_lines_before)

  -- Cleanup
  helpers.git(child, repo, string.format("worktree remove %s", worktree_path))
  helpers.cleanup_repo(child, repo)
end

return T
