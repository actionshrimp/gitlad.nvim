-- End-to-end tests for gitlad.nvim worktree popup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

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

-- Worktree popup tests
T["worktree popup"] = MiniTest.new_set()

T["worktree popup"]["opens from status buffer with % key"] = function()
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
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Wait for popup to appear
  child.lua([[vim.wait(200, function() return false end)]])

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains worktree-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_create = false
  local found_delete = false
  local found_visit = false
  local found_create_new = false
  for _, line in ipairs(lines) do
    if line:match("Create new") then
      found_create_new = true
    end
    if line:match("b%s+worktree") then
      found_create = true
    end
    if line:match("k%s+Delete") then
      found_delete = true
    end
    if line:match("g%s+Visit") then
      found_visit = true
    end
  end

  eq(found_create_new, true)
  eq(found_create, true)
  eq(found_delete, true)
  eq(found_visit, true)

  helpers.cleanup_repo(child, repo)
end

T["worktree popup"]["has correct switches"] = function()
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
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Verify popup contains worktree switches
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_force = false
  local found_detach = false
  local found_lock = false
  for _, line in ipairs(lines) do
    if line:match("%-f") and line:match("Force") then
      found_force = true
    end
    if line:match("%-d") and line:match("Detach") then
      found_detach = true
    end
    if line:match("%-l") and line:match("Lock") then
      found_lock = true
    end
  end

  eq(found_force, true)
  eq(found_detach, true)
  eq(found_lock, true)

  helpers.cleanup_repo(child, repo)
end

T["worktree popup"]["closes on q key"] = function()
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
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Verify popup is open
  local win_count_before = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_before, 2)

  -- Press q to close
  child.type_keys("q")

  -- Verify popup is closed
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  helpers.cleanup_repo(child, repo)
end

T["worktree popup"]["context-aware when cursor on worktree entry"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
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
  child.lua([[vim.wait(1000, function() return false end)]])

  -- Navigate to Worktrees section
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("^Worktrees") then
        -- Move to the first worktree entry (line after section header)
        vim.api.nvim_win_set_cursor(0, {i + 1, 0})
        break
      end
    end
  ]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Verify popup is open
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Cleanup
  child.type_keys("q")
  helpers.git(child, repo, string.format("worktree remove %s", worktree_path))
  helpers.cleanup_repo(child, repo)
end

T["worktree popup"]["shows all action groups"] = function()
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
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Verify popup contains all action groups
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_create_new = false
  local found_commands = false
  local found_lock_heading = false
  local found_maintenance = false
  for _, line in ipairs(lines) do
    if line:match("Create new") then
      found_create_new = true
    end
    if line:match("Commands") then
      found_commands = true
    end
    if line:match("^Lock") then
      found_lock_heading = true
    end
    if line:match("Maintenance") then
      found_maintenance = true
    end
  end

  eq(found_create_new, true)
  eq(found_commands, true)
  eq(found_lock_heading, true)
  eq(found_maintenance, true)

  helpers.cleanup_repo(child, repo)
end

T["worktree popup"]["branch and worktree action available"] = function()
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
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Verify popup contains branch and worktree action
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_branch_and_worktree = false
  for _, line in ipairs(lines) do
    if line:match("c%s+branch and worktree") then
      found_branch_and_worktree = true
      break
    end
  end

  eq(found_branch_and_worktree, true)

  helpers.cleanup_repo(child, repo)
end

T["worktree popup"]["prune action available"] = function()
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
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press % to open worktree popup
  child.type_keys("%")

  -- Verify popup contains prune action
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_prune = false
  for _, line in ipairs(lines) do
    if line:match("p%s+Prune") then
      found_prune = true
      break
    end
  end

  eq(found_prune, true)

  helpers.cleanup_repo(child, repo)
end

return T
