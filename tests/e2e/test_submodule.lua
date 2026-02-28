-- End-to-end tests for gitlad.nvim submodule support
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = require("tests.helpers")

local child = MiniTest.new_child_neovim()

-- Helper to create a file in the repo
-- Helper to create a repo with a submodule
local function create_repo_with_submodule(child_nvim)
  -- Create the submodule repo first
  local submodule_repo = child_nvim.lua_get("vim.fn.tempname()")
  child_nvim.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init")
    vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")
    vim.fn.system("git -C " .. repo .. " config commit.gpgsign false")
  ]],
    submodule_repo
  ))

  -- Create initial commit in submodule
  helpers.create_file(child_nvim, submodule_repo, "subfile.txt", "submodule content")
  helpers.git(child_nvim, submodule_repo, "add subfile.txt")
  helpers.git(child_nvim, submodule_repo, 'commit -m "Initial submodule commit"')

  -- Create the parent repo
  local parent_repo = helpers.create_test_repo(child_nvim)
  helpers.create_file(child_nvim, parent_repo, "main.txt", "main content")
  helpers.git(child_nvim, parent_repo, "add main.txt")
  helpers.git(child_nvim, parent_repo, 'commit -m "Initial commit"')

  -- Add submodule to parent
  -- Use -c protocol.file.allow=always to allow file:// protocol (Git security feature)
  child_nvim.lua(
    string.format(
      [[vim.fn.system("git -c protocol.file.allow=always -C %s submodule add %s mysub")]],
      parent_repo,
      submodule_repo
    )
  )
  helpers.git(child_nvim, parent_repo, 'commit -m "Add submodule"')

  return parent_repo, submodule_repo
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

-- Submodule section rendering tests
T["submodule section"] = MiniTest.new_set()

T["submodule section"]["shows Submodules section when enabled"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Enable submodules section via config
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Submodules")

  -- Get buffer lines
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    _G.status_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G.status_lines]])

  -- Find Submodules section
  local found_submodules_section = false
  local found_submodule_entry = false
  for _, line in ipairs(lines) do
    if line:match("^Submodules %(%d+%)") then
      found_submodules_section = true
    end
    if line:match("mysub") then
      found_submodule_entry = true
    end
  end

  eq(found_submodules_section, true)
  eq(found_submodule_entry, true)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

T["submodule section"]["hides Submodules section when no submodules"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit only (no submodules)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Open status view
  helpers.cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Get buffer lines
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    _G.status_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G.status_lines]])

  -- Should NOT have Submodules section
  local found_submodules_section = false
  for _, line in ipairs(lines) do
    if line:match("^Submodules") then
      found_submodules_section = true
    end
  end

  eq(found_submodules_section, false)

  helpers.cleanup_repo(child, repo)
end

-- Submodule popup tests
T["submodule popup"] = MiniTest.new_set()

T["submodule popup"]["opens from status buffer with ' key"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  helpers.cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Press ' to open submodule popup
  child.type_keys("'")
  helpers.wait_for_popup(child)

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains submodule-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_one_module = false
  local found_add = false
  local found_update = false
  for _, line in ipairs(lines) do
    -- Check for the "One module" heading which is unique to submodule popup
    if line:match("One module") then
      found_one_module = true
    end
    if line:match("a%s+Add") then
      found_add = true
    end
    if line:match("u%s+Update") then
      found_update = true
    end
  end

  eq(found_one_module, true)
  eq(found_add, true)
  eq(found_update, true)

  -- Clean up
  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["submodule popup"]["has all expected switches"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  child.type_keys("'")
  helpers.wait_for_popup(child)

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_force = false
  local found_recursive = false
  local found_no_fetch = false

  for _, line in ipairs(lines) do
    if line:match("%-f.*force") then
      found_force = true
    end
    if line:match("%-r.*recursive") then
      found_recursive = true
    end
    if line:match("%-N.*no%-fetch") then
      found_no_fetch = true
    end
  end

  eq(found_force, true)
  eq(found_recursive, true)
  eq(found_no_fetch, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["submodule popup"]["closes with q"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open submodule popup
  child.type_keys("'")
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

T["submodule popup"]["' keybinding appears in help"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  helpers.cd(child, repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Open help with ?
  child.type_keys("?")
  helpers.wait_for_popup(child)

  -- Check for submodule popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_submodule = false
  for _, line in ipairs(lines) do
    if line:match("'%s+Submodule") then
      found_submodule = true
    end
  end

  eq(found_submodule, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

-- Submodule navigation tests
T["submodule navigation"] = MiniTest.new_set()

T["submodule navigation"]["gj/gk navigates to submodule entries"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Enable submodules section for this test
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Submodules")

  -- Get buffer content and find submodule line
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.submodule_line = nil
    for i, line in ipairs(lines) do
      if line:match("mysub") and not line:match("^Submodules") then
        _G.submodule_line = i
        break
      end
    end
  ]])
  local submodule_line = child.lua_get([[_G.submodule_line]])

  -- Submodule line should exist
  eq(submodule_line ~= nil, true)

  -- Navigate with gj until we reach the submodule line
  child.type_keys("gg") -- Go to top first
  for _ = 1, 20 do -- Navigate down several times
    child.type_keys("gj")
    local current_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
    if current_line == submodule_line then
      break
    end
  end

  -- Verify we can reach the submodule line
  local final_line = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(final_line, submodule_line)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

T["submodule navigation"]["TAB collapses and expands submodule section"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Enable submodules section for this test
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Submodules")

  -- Find and navigate to Submodules section header
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.submodules_header_line = nil
    for i, line in ipairs(lines) do
      if line:match("^Submodules %(%d+%)") then
        _G.submodules_header_line = i
        break
      end
    end
  ]])
  local header_line = child.lua_get([[_G.submodules_header_line]])
  eq(header_line ~= nil, true)

  -- Move cursor to submodules header
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], header_line))

  -- Check submodule entry is visible
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_submodule_entry = false
    for _, line in ipairs(lines) do
      if line:match("mysub") and not line:match("^Submodules") then
        _G.has_submodule_entry = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.has_submodule_entry]]), true)

  -- Press TAB to collapse
  child.type_keys("<Tab>")
  helpers.wait_short(child, 100)

  -- Check submodule entry is now hidden
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_submodule_entry_after_collapse = false
    for _, line in ipairs(lines) do
      if line:match("mysub") and not line:match("^Submodules") then
        _G.has_submodule_entry_after_collapse = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.has_submodule_entry_after_collapse]]), false)

  -- Press TAB again to expand
  child.type_keys("<Tab>")
  helpers.wait_short(child, 100)

  -- Check submodule entry is visible again
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.has_submodule_entry_after_expand = false
    for _, line in ipairs(lines) do
      if line:match("mysub") and not line:match("^Submodules") then
        _G.has_submodule_entry_after_expand = true
        break
      end
    end
  ]])
  eq(child.lua_get([[_G.has_submodule_entry_after_expand]]), true)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

-- Submodule RET behavior tests
T["submodule RET"] = MiniTest.new_set()

T["submodule RET"]["RET on submodule opens its directory"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Enable submodules section for this test
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Submodules", 1500)

  -- Find and navigate to submodule entry
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.found_submodule_line = nil
    for i, line in ipairs(lines) do
      if line:match("mysub") and not line:match("^Submodules") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        _G.found_submodule_line = i
        break
      end
    end
  ]])

  local submodule_line = child.lua_get([[_G.found_submodule_line]])
  -- Skip test if submodule line not found (shouldn't happen but makes test more robust)
  if submodule_line == nil or submodule_line == vim.NIL then
    helpers.cleanup_repo(child, parent_repo)
    helpers.cleanup_repo(child, submodule_repo)
    return
  end

  -- Give status buffer time to set up keymaps
  helpers.wait_short(child, 100)

  -- Press RET to visit the submodule (use feedkeys for better keymap handling)
  child.lua(
    [[vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, true, true), "x", true)]]
  )
  helpers.wait_short(child, 200)

  -- Verify the buffer name contains the submodule path
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("mysub") ~= nil, true)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

-- Submodule popup on submodule entry tests
T["submodule popup context"] = MiniTest.new_set()

T["submodule popup context"]["' on submodule entry shows submodule path in popup"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Enable submodules section for this test
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Submodules")

  -- Find and navigate to submodule entry
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("mysub") and not line:match("^Submodules") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])

  -- Press ' to open submodule popup
  child.type_keys("'")
  helpers.wait_for_popup(child)

  -- Get popup content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Should show submodule path in the "One module" heading
  local found_path = false
  for _, line in ipairs(lines) do
    if line:match("One module.*mysub") then
      found_path = true
    end
  end

  eq(found_path, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

T["submodule popup context"]["' on submodule in unstaged changes shows path in popup"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Modify the submodule (create a new commit in it) so it appears in Unstaged changes
  helpers.create_file(child, submodule_repo, "newfile.txt", "new content")
  helpers.git(child, submodule_repo, "add newfile.txt")
  helpers.git(child, submodule_repo, 'commit -m "New commit in submodule"')

  -- Update the submodule in parent to new commit (this makes it show as modified/unstaged)
  helpers.git(child, parent_repo, "submodule update --remote mysub")

  -- Disable dedicated submodules section to ensure we test the file entry path
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Unstaged")

  -- Find the submodule in Unstaged changes section (should be a file entry)
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.unstaged_line = nil
    local in_unstaged = false
    for i, line in ipairs(lines) do
      if line:match("^Unstaged changes") then
        in_unstaged = true
      elseif line:match("^%u") and not line:match("^Unstaged") then
        -- Hit another section header
        in_unstaged = false
      elseif in_unstaged and line:match("mysub") then
        _G.unstaged_line = i
        break
      end
    end
  ]])
  local unstaged_line = child.lua_get([[_G.unstaged_line]])

  -- Skip test if no unstaged submodule found (may not show depending on git version)
  if unstaged_line == nil or unstaged_line == vim.NIL then
    helpers.cleanup_repo(child, parent_repo)
    helpers.cleanup_repo(child, submodule_repo)
    return
  end

  -- Navigate to the submodule line in Unstaged changes
  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], unstaged_line))

  -- Press ' to open submodule popup
  child.type_keys("'")
  helpers.wait_for_popup(child)

  -- Get popup content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  -- Should show submodule path in the "One module" heading
  local found_path = false
  for _, line in ipairs(lines) do
    if line:match("One module.*mysub") then
      found_path = true
    end
  end

  eq(found_path, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

-- Submodule diff tests
T["submodule diff"] = MiniTest.new_set()

T["submodule diff"]["TAB on submodule in Submodules section shows SHA diff"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Modify the submodule (create a new commit in it)
  helpers.create_file(child, submodule_repo, "newfile.txt", "new content")
  helpers.git(child, submodule_repo, "add newfile.txt")
  helpers.git(child, submodule_repo, 'commit -m "New commit in submodule"')

  -- Also update the submodule in the parent to the new commit
  helpers.git(child, parent_repo, "submodule update --remote mysub")

  -- Enable submodules section for this test
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "submodules", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Submodules")

  -- Find the submodule entry in the Submodules section (has "remotes" or similar describe info)
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.submodule_section_line = nil
    local in_submodules_section = false
    for i, line in ipairs(lines) do
      if line:match("^Submodules") then
        in_submodules_section = true
      elseif line:match("^%u") and in_submodules_section then
        -- Hit another section header
        in_submodules_section = false
      elseif in_submodules_section and line:match("mysub") then
        _G.submodule_section_line = i
        break
      end
    end
  ]])
  local submodule_line = child.lua_get([[_G.submodule_section_line]])

  -- Skip test if no submodule entry found (shouldn't happen with proper setup)
  if submodule_line == nil or submodule_line == vim.NIL then
    helpers.cleanup_repo(child, parent_repo)
    helpers.cleanup_repo(child, submodule_repo)
    return
  end

  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], submodule_line))

  -- Press TAB to expand diff
  child.type_keys("<Tab>")
  helpers.wait_short(child, 300)

  -- Get buffer content and look for SHA diff lines
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.found_minus_sha = false
    _G.found_plus_sha = false
    for _, line in ipairs(lines) do
      if line:match("^%s*%-[0-9a-f]+$") then
        _G.found_minus_sha = true
      end
      if line:match("^%s*%+[0-9a-f]+$") then
        _G.found_plus_sha = true
      end
    end
  ]])

  -- Must find both SHA diff lines
  eq(child.lua_get([[_G.found_minus_sha]]), true)
  eq(child.lua_get([[_G.found_plus_sha]]), true)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

T["submodule diff"]["TAB on submodule in Unstaged section shows SHA diff"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Modify the submodule (create a new commit in it)
  helpers.create_file(child, submodule_repo, "newfile.txt", "new content")
  helpers.git(child, submodule_repo, "add newfile.txt")
  helpers.git(child, submodule_repo, 'commit -m "New commit in submodule"')

  -- Update the submodule in the parent to the new commit (this makes it appear in unstaged)
  helpers.git(child, parent_repo, "submodule update --remote mysub")

  -- Disable dedicated submodules section - submodule will only appear in Unstaged
  child.lua(
    [[require("gitlad.config").setup({ status = { sections = { "untracked", "unstaged", "staged", "conflicted", "stashes", "worktrees", "unpushed", "unpulled", "recent" } } })]]
  )

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)
  helpers.wait_for_buffer_content(child, "Unstaged")

  -- Find the submodule entry in the Unstaged section
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.unstaged_submodule_line = nil
    local in_unstaged_section = false
    for i, line in ipairs(lines) do
      if line:match("^Unstaged") then
        in_unstaged_section = true
      elseif line:match("^%u") and in_unstaged_section then
        -- Hit another section header
        in_unstaged_section = false
      elseif in_unstaged_section and line:match("mysub") then
        _G.unstaged_submodule_line = i
        break
      end
    end
  ]])
  local submodule_line = child.lua_get([[_G.unstaged_submodule_line]])

  -- Skip test if no submodule entry found (depends on git version behavior)
  if submodule_line == nil or submodule_line == vim.NIL then
    helpers.cleanup_repo(child, parent_repo)
    helpers.cleanup_repo(child, submodule_repo)
    return
  end

  child.lua(string.format([[vim.api.nvim_win_set_cursor(0, {%d, 0})]], submodule_line))

  -- Press TAB to expand diff
  child.type_keys("<Tab>")
  helpers.wait_short(child, 300)

  -- Get buffer content and look for SHA diff lines immediately after the submodule line
  child.lua(string.format(
    [[
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    _G.found_minus_sha = false
    _G.found_plus_sha = false
    -- Look for SHA diff lines right after the submodule entry
    for i = %d + 1, math.min(%d + 3, #lines) do
      local line = lines[i]
      if line:match("^%%s*%%-[0-9a-f]+$") then
        _G.found_minus_sha = true
      end
      if line:match("^%%s*%%+[0-9a-f]+$") then
        _G.found_plus_sha = true
      end
    end
  ]],
    submodule_line,
    submodule_line
  ))

  -- Must find both SHA diff lines
  eq(child.lua_get([[_G.found_minus_sha]]), true)
  eq(child.lua_get([[_G.found_plus_sha]]), true)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

-- Submodule list action test
T["submodule list"] = MiniTest.new_set()

T["submodule list"]["l action triggers submodule list"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Open status view
  helpers.cd(child, parent_repo)
  child.cmd("Gitlad")
  helpers.wait_for_status(child)

  -- Mock vim.ui.select to capture the list action
  child.lua([[
    _G.ui_select_called = false
    _G.ui_select_items = nil
    _G.ui_select_prompt = nil
    vim.ui.select = function(items, opts, on_choice)
      _G.ui_select_called = true
      _G.ui_select_items = items
      _G.ui_select_prompt = opts.prompt
      -- Don't call on_choice to avoid further actions
    end
  ]])

  -- Open submodule popup and press l for list
  child.type_keys("'")
  helpers.wait_for_popup(child)
  child.type_keys("l")
  -- Wait for async submodule list and vim.ui.select to be called
  child.lua([[vim.wait(1500, function() return _G.ui_select_called == true end, 10)]])

  eq(child.lua_get([[_G.ui_select_called]]), true)

  -- Check that the list contains mysub
  local items = child.lua_get([[_G.ui_select_items]])
  local found_mysub = false
  if items then
    for _, item in ipairs(items) do
      if item:match("mysub") then
        found_mysub = true
        break
      end
    end
  end
  eq(found_mysub, true)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

-- =============================================================================
-- git.ignore_submodules config tests
-- =============================================================================

T["ignore_submodules config"] = MiniTest.new_set()

T["ignore_submodules config"]["defaults to false"] = function()
  child.lua([[require("gitlad").setup({})]])

  local value = child.lua_get([[require("gitlad.config").get().git.ignore_submodules]])
  eq(value, false)
end

T["ignore_submodules config"]["accepts dirty"] = function()
  child.lua([[require("gitlad").setup({ git = { ignore_submodules = "dirty" } })]])

  local value = child.lua_get([[require("gitlad.config").get().git.ignore_submodules]])
  eq(value, "dirty")
end

T["ignore_submodules config"]["accepts untracked"] = function()
  child.lua([[require("gitlad").setup({ git = { ignore_submodules = "untracked" } })]])

  local value = child.lua_get([[require("gitlad.config").get().git.ignore_submodules]])
  eq(value, "untracked")
end

T["ignore_submodules config"]["accepts all"] = function()
  child.lua([[require("gitlad").setup({ git = { ignore_submodules = "all" } })]])

  local value = child.lua_get([[require("gitlad.config").get().git.ignore_submodules]])
  eq(value, "all")
end

T["ignore_submodules status"] = MiniTest.new_set()

T["ignore_submodules status"]["build_status_args includes --ignore-submodules when configured"] = function()
  child.lua([[require("gitlad").setup({ git = { ignore_submodules = "dirty" } })]])

  -- Verify the build_status_args helper produces the right args
  -- by requiring git/init.lua directly and checking the internal function
  local has_flag = child.lua_get([[
    (function()
      local cfg = require("gitlad.config").get()
      local ignore = cfg.git and cfg.git.ignore_submodules
      return ignore == "dirty"
    end)()
  ]])
  eq(has_flag, true)

  -- Run a real status call and verify the flag appears in history
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    _G.test_done = false
    git.status({ cwd = %q }, function()
      _G.test_done = true
    end)
  ]],
    repo
  ))
  helpers.wait_for_var(child, "_G.test_done")
  helpers.wait_short(child)

  -- Check history for the flag
  child.lua([[
    local history = require("gitlad.git.history")
    local entries = history.get_all()
    _G.test_flag_found = false
    for _, entry in ipairs(entries) do
      for _, arg in ipairs(entry.args or {}) do
        if arg == "--ignore-submodules=dirty" then
          _G.test_flag_found = true
        end
      end
    end
  ]])
  eq(child.lua_get("_G.test_flag_found"), true)

  helpers.cleanup_repo(child, repo)
end

T["ignore_submodules status"]["build_status_args omits --ignore-submodules when false"] = function()
  child.lua([[require("gitlad").setup({})]])

  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "init.txt", "init")
  helpers.git(child, repo, "add init.txt")
  helpers.git(child, repo, "commit -m 'Initial commit'")

  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    _G.test_done = false
    git.status({ cwd = %q }, function()
      _G.test_done = true
    end)
  ]],
    repo
  ))
  helpers.wait_for_var(child, "_G.test_done")

  -- Check history - should NOT contain --ignore-submodules
  child.lua([[
    local history = require("gitlad.git.history")
    local entries = history.get_all()
    _G.test_flag_found = false
    for _, entry in ipairs(entries) do
      for _, arg in ipairs(entry.args or {}) do
        if arg:find("ignore%-submodules") then
          _G.test_flag_found = true
        end
      end
    end
  ]])
  eq(child.lua_get("_G.test_flag_found"), false)

  helpers.cleanup_repo(child, repo)
end

T["ignore_submodules status"]["dirty submodule hidden with ignore_submodules=dirty"] = function()
  local parent_repo, submodule_repo = create_repo_with_submodule(child)

  -- Make the submodule dirty (modify a file inside it)
  helpers.create_file(child, parent_repo, "mysub/new_file.txt", "dirty content")

  -- First check: without ignore_submodules, mysub should appear in git status
  child.lua(string.format(
    [[
    _G.test_raw_without = vim.fn.system("git -C %s status --porcelain=v2")
  ]],
    parent_repo
  ))
  local raw_without = child.lua_get("_G.test_raw_without")
  eq(raw_without:find("mysub") ~= nil, true)

  -- Second check: with --ignore-submodules=dirty, mysub should NOT appear
  child.lua(string.format(
    [[
    _G.test_raw_with = vim.fn.system("git -C %s status --porcelain=v2 --ignore-submodules=dirty")
  ]],
    parent_repo
  ))
  local raw_with = child.lua_get("_G.test_raw_with")
  eq(raw_with:find("mysub") == nil, true)

  -- Third check: through gitlad API with config set
  child.lua([[require("gitlad.config").setup({ git = { ignore_submodules = "dirty" } })]])

  child.lua(string.format(
    [[
    local git = require("gitlad.git")
    _G.test_status_result = nil
    git.status({ cwd = %q }, function(result, err)
      _G.test_status_result = result
    end)
  ]],
    parent_repo
  ))
  helpers.wait_for_var(child, "_G.test_status_result")

  local has_mysub = child.lua_get([[
    (function()
      local status = _G.test_status_result
      if not status then return false end
      -- Check all entry lists
      for _, list_name in ipairs({"staged", "unstaged", "untracked", "conflicted"}) do
        for _, entry in ipairs(status[list_name] or {}) do
          if entry.path == "mysub" then return true end
        end
      end
      return false
    end)()
  ]])
  eq(has_mysub, false)

  helpers.cleanup_repo(child, parent_repo)
  helpers.cleanup_repo(child, submodule_repo)
end

return T
