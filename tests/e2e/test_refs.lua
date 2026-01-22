-- E2E tests for refs functionality
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to create a test git repository
local function create_test_repo(child_nvim)
  local repo = child_nvim.lua_get("vim.fn.tempname()")
  child_nvim.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init")
    vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")
  ]],
    repo
  ))
  return repo
end

-- Helper to clean up test repo
local function cleanup_test_repo(child_nvim, repo)
  child_nvim.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
end

-- Helper to create a file in the test repo
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

-- Helper to run git command in repo
local function git(child_nvim, repo, args)
  return child_nvim.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
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

-- =============================================================================
-- Refs popup tests
-- =============================================================================

T["refs popup"] = MiniTest.new_set()

T["refs popup"]["opens from status buffer with yr key"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit
  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Open status buffer
  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Press yr to open refs popup
  child.type_keys("yr")
  child.lua("vim.wait(200, function() end)")

  -- Should have a popup window
  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count > 1, true)

  -- Buffer should contain "Show refs" (group heading in refs popup)
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local found_refs = false
  for _, line in ipairs(lines) do
    if line:match("Show refs") then
      found_refs = true
      break
    end
  end
  eq(found_refs, true)

  cleanup_test_repo(child, repo)
end

T["refs popup"]["has correct actions"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("yr")
  child.lua("vim.wait(200, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should have actions
  expect.equality(content:match("Show refs at HEAD") ~= nil, true)
  expect.equality(content:match("Show refs at current") ~= nil, true)
  expect.equality(content:match("Show refs at other") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["refs popup"]["closes with q"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "init.txt", "init")
  git(child, repo, "add init.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  child.type_keys("yr")
  child.lua("vim.wait(200, function() end)")

  local win_count_before = child.lua_get("vim.fn.winnr('$')")

  child.type_keys("q")
  child.lua("vim.wait(200, function() end)")

  local win_count_after = child.lua_get("vim.fn.winnr('$')")

  -- Window should have closed
  eq(win_count_after < win_count_before, true)

  cleanup_test_repo(child, repo)
end

-- =============================================================================
-- Refs view tests
-- =============================================================================

T["refs view"] = MiniTest.new_set()

T["refs view"]["opens when action is triggered"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs popup and trigger "show refs at HEAD" action
  child.type_keys("yr")
  child.lua("vim.wait(200, function() end)")

  child.type_keys("y")
  child.lua("vim.wait(1000, function() end)")

  -- Should now be in refs buffer
  local buf_name = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name:match("gitlad://refs") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["displays local branches"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create another branch
  git(child, repo, "branch feature-branch")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should show Local section
  expect.equality(content:match("Local") ~= nil, true)
  -- Should show branch names
  expect.equality(content:match("master") ~= nil or content:match("main") ~= nil, true)
  expect.equality(content:match("feature%-branch") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["displays tags"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create a tag
  git(child, repo, "tag v1.0.0")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should show Tags section
  expect.equality(content:match("Tags") ~= nil, true)
  -- Should show tag name
  expect.equality(content:match("v1%.0%.0") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["shows current branch with * marker"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create another branch but stay on main/master
  git(child, repo, "branch other-branch")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Find a line with * marker
  local found_head_marker = false
  for _, line in ipairs(lines) do
    if line:match("^%*") or line:match("^%s+%*") then
      found_head_marker = true
      break
    end
  end
  eq(found_head_marker, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["gj/gk keymaps are set up"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that gj and gk keymaps exist
  child.lua([[
    _G.has_gj = false
    _G.has_gk = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "gj" then _G.has_gj = true end
      if km.lhs == "gk" then _G.has_gk = true end
    end
  ]])
  local has_gj = child.lua_get("_G.has_gj")
  local has_gk = child.lua_get("_G.has_gk")
  eq(has_gj, true)
  eq(has_gk, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["closes with q"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Verify in refs buffer
  local buf_name_before = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name_before:match("gitlad://refs") ~= nil, true)

  -- Close with q
  child.type_keys("q")
  child.lua("vim.wait(200, function() end)")

  -- Should be back in status or previous buffer
  local buf_name_after = child.lua_get("vim.api.nvim_buf_get_name(0)")
  eq(buf_name_after:match("gitlad://refs") == nil, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["buffer is not modifiable"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that buffer is not modifiable
  local modifiable = child.lua_get("vim.bo.modifiable")
  eq(modifiable, false)

  cleanup_test_repo(child, repo)
end

T["refs view"]["has popup keymaps (b, A, X, d)"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that popup keymaps exist
  child.lua([[
    _G.popup_keymaps = {}
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "b" then _G.popup_keymaps.branch = true end
      if km.lhs == "A" then _G.popup_keymaps.cherrypick = true end
      if km.lhs == "X" then _G.popup_keymaps.reset = true end
      if km.lhs == "d" then _G.popup_keymaps.diff = true end
    end
  ]])

  local has_branch = child.lua_get("_G.popup_keymaps.branch")
  local has_cherrypick = child.lua_get("_G.popup_keymaps.cherrypick")
  local has_reset = child.lua_get("_G.popup_keymaps.reset")
  local has_diff = child.lua_get("_G.popup_keymaps.diff")

  eq(has_branch, true)
  eq(has_cherrypick, true)
  eq(has_reset, true)
  eq(has_diff, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["has delete keymap x"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that x keymap exists in normal mode
  child.lua([[
    _G.has_delete = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "x" then _G.has_delete = true end
    end
  ]])
  local has_delete = child.lua_get("_G.has_delete")
  eq(has_delete, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["has visual mode delete keymap x"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that x keymap exists in visual mode
  child.lua([[
    _G.has_visual_delete = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'v')
    for _, km in ipairs(keymaps) do
      if km.lhs == "x" then _G.has_visual_delete = true end
    end
  ]])
  local has_visual_delete = child.lua_get("_G.has_visual_delete")
  eq(has_visual_delete, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["has Tab keymap for expansion"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that Tab keymap exists
  child.lua([[
    _G.has_tab = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "<Tab>" then _G.has_tab = true end
    end
  ]])
  local has_tab = child.lua_get("_G.has_tab")
  eq(has_tab, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["has yank keymap y"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  -- Check that y keymap exists
  child.lua([[
    _G.has_yank = false
    local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
    for _, km in ipairs(keymaps) do
      if km.lhs == "y" then _G.has_yank = true end
    end
  ]])
  local has_yank = child.lua_get("_G.has_yank")
  eq(has_yank, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["shows header with base ref"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view at HEAD
  child.type_keys("yry")
  child.lua("vim.wait(1000, function() end)")

  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Should show "References (at HEAD)" in header
  expect.equality(content:match("References %(at HEAD%)") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["cherry commits are displayed without indentation"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit on main
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create feature branch with unique commits (cherries)
  git(child, repo, "checkout -b feature-branch")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, "commit -m 'Add feature file'")

  -- Go back to main
  git(child, repo, "checkout -")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view at HEAD (main)
  child.type_keys("yry")
  child.lua("vim.wait(1500, function() end)") -- Wait for refs and cherry prefetch

  -- Navigate to feature-branch and expand it
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("feature%-branch") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Press Tab to expand cherry commits
  child.type_keys("<Tab>")
  child.lua("vim.wait(500, function() end)")

  -- Get buffer lines and check for cherry commits
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")

  -- Cherry commits should start with + or - (no leading spaces/indentation)
  -- The format should be: +/- <hash> <subject>
  local found_cherry = false
  local cherry_has_no_indent = false
  for _, line in ipairs(lines) do
    -- Look for lines that look like cherry commits (+ or - followed by hash)
    if line:match("^[%+%-] %x%x%x%x%x%x%x ") then
      found_cherry = true
      cherry_has_no_indent = true
      break
    end
    -- Also check if there's a cherry with indentation (which would be wrong)
    if line:match("^%s+[%+%-] %x%x%x%x%x%x%x ") then
      found_cherry = true
      cherry_has_no_indent = false
      break
    end
  end

  eq(found_cherry, true)
  eq(cherry_has_no_indent, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["diff popup on cherry commit shows commit context"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit on main
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create feature branch with unique commits (cherries)
  git(child, repo, "checkout -b feature-branch")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, "commit -m 'Add feature file'")

  -- Go back to main
  git(child, repo, "checkout -")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view at HEAD (main)
  child.type_keys("yry")
  child.lua("vim.wait(1500, function() end)") -- Wait for refs and cherry prefetch

  -- Navigate to feature-branch and expand it
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("feature%-branch") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Press Tab to expand cherry commits
  child.type_keys("<Tab>")
  child.lua("vim.wait(500, function() end)")

  -- Navigate to the cherry commit line
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("^[%+%-] %x%x%x%x%x%x%x ") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Open diff popup on cherry commit line
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  -- Get popup buffer lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Check that the diff popup shows "Show commit" action (indicates commit context)
  eq(content:match("Show commit") ~= nil, true)

  cleanup_test_repo(child, repo)
end

T["refs view"]["diff popup on ref shows three-dot range action"] = function()
  local repo = create_test_repo(child)
  cd(child, repo)

  -- Create initial commit on main
  create_file(child, repo, "file.txt", "content")
  git(child, repo, "add file.txt")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create feature branch
  git(child, repo, "checkout -b feature-branch")
  create_file(child, repo, "feature.txt", "feature content")
  git(child, repo, "add feature.txt")
  git(child, repo, "commit -m 'Add feature file'")

  -- Go back to main
  git(child, repo, "checkout -")

  child.cmd("Gitlad")
  child.lua("vim.wait(500, function() end)")

  -- Open refs view at HEAD (main)
  child.type_keys("yry")
  child.lua("vim.wait(1500, function() end)") -- Wait for refs and cherry prefetch

  -- Navigate to feature-branch ref line
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("feature%-branch") and not line:match("^[%+%-]") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Open diff popup on ref line
  child.type_keys("d")
  child.lua("vim.wait(200, function() end)")

  -- Get popup buffer lines
  local lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  local content = table.concat(lines, "\n")

  -- Check that the diff popup shows the three-dot range action
  eq(content:match("Changes on feature%-branch vs") ~= nil, true)

  cleanup_test_repo(child, repo)
end

return T
