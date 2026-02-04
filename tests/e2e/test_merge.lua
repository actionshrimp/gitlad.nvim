-- End-to-end tests for gitlad.nvim merge popup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

-- Helper to create a file in the repo
local function create_file(child, repo, filename, content)
  child.lua(string.format(
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
local function git(child, repo, args)
  return child.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo .. " " .. args))
end

-- Helper to cleanup repo
local function cleanup_repo(child, repo)
  child.lua(string.format([[vim.fn.delete(%q, "rf")]], repo))
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

-- Merge popup tests
T["merge popup"] = MiniTest.new_set()

T["merge popup"]["opens from status buffer with m key"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  -- Change to repo directory and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])

  -- Wait for status to load
  child.lua([[vim.wait(500, function() return false end)]])

  -- Press m to open merge popup
  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup contains merge-related content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_merge_action = false
  local found_squash = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge") then
      found_merge_action = true
    end
    if line:match("s%s+Squash") then
      found_squash = true
    end
  end

  eq(found_merge_action, true)
  eq(found_squash, true)

  -- Clean up
  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["has all expected switches"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Check for switches in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_ff_only = false
  local found_no_ff = false
  local found_ignore_space = false
  local found_ignore_all_space = false
  local found_gpg_sign = false

  for _, line in ipairs(lines) do
    if line:match("%-f.*ff%-only") then
      found_ff_only = true
    end
    if line:match("%-n.*no%-ff") then
      found_no_ff = true
    end
    if line:match("%-b.*Xignore%-space%-change") then
      found_ignore_space = true
    end
    if line:match("%-w.*Xignore%-all%-space") then
      found_ignore_all_space = true
    end
    if line:match("%-S.*gpg%-sign") then
      found_gpg_sign = true
    end
  end

  eq(found_ff_only, true)
  eq(found_no_ff, true)
  eq(found_ignore_space, true)
  eq(found_ignore_all_space, true)
  eq(found_gpg_sign, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["has choice options for strategy"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Check for option in popup
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_strategy = false
  local found_strategy_option = false
  local found_diff_algorithm = false

  for _, line in ipairs(lines) do
    if line:match("=s.*Strategy.*strategy") then
      found_strategy = true
    end
    if line:match("=X.*Strategy option.*strategy%-option") then
      found_strategy_option = true
    end
    if line:match("=A.*Diff algorithm.*Xdiff%-algorithm") then
      found_diff_algorithm = true
    end
  end

  eq(found_strategy, true)
  eq(found_strategy_option, true)
  eq(found_diff_algorithm, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["ff-only and no-ff are mutually exclusive"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Get popup buffer
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
  ]])

  -- Helper to check switch states
  local function get_switch_states()
    child.lua([[
      popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
    ]])
    local lines = child.lua_get([[popup_lines]])

    local ff_enabled = false
    local no_ff_enabled = false
    for _, line in ipairs(lines) do
      if line:match("%*%-f.*ff%-only") then
        ff_enabled = true
      end
      if line:match("%*%-n.*no%-ff") then
        no_ff_enabled = true
      end
    end
    return ff_enabled, no_ff_enabled
  end

  -- Initially neither should be enabled
  local ff1, noff1 = get_switch_states()
  eq(ff1, false)
  eq(noff1, false)

  -- Enable ff-only
  child.type_keys("-f")
  child.lua([[vim.wait(50, function() return false end)]])

  local ff2, noff2 = get_switch_states()
  eq(ff2, true)
  eq(noff2, false)

  -- Enable no-ff - should disable ff-only
  child.type_keys("-n")
  child.lua([[vim.wait(50, function() return false end)]])

  local ff3, noff3 = get_switch_states()
  eq(ff3, false) -- ff-only should be disabled
  eq(noff3, true) -- no-ff should be enabled

  -- Enable ff-only again - should disable no-ff
  child.type_keys("-f")
  child.lua([[vim.wait(50, function() return false end)]])

  local ff4, noff4 = get_switch_states()
  eq(ff4, true) -- ff-only should be enabled
  eq(noff4, false) -- no-ff should be disabled

  child.type_keys("q")
  cleanup_repo(child, repo)
end

T["merge popup"]["closes with q"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open merge popup
  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  local win_count_popup = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_popup, 2)

  -- Close with q
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count_after, 1)

  -- Should be in status buffer
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  eq(bufname:match("gitlad://status") ~= nil, true)

  cleanup_repo(child, repo)
end

T["merge popup"]["m keybinding appears in help"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit
  create_file(child, repo, "test.txt", "hello")
  git(child, repo, "add test.txt")
  git(child, repo, 'commit -m "Initial"')

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open help with ?
  child.type_keys("?")

  -- Check for merge popup in help
  child.lua([[
    help_buf = vim.api.nvim_get_current_buf()
    help_lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[help_lines]])

  local found_merge = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge") then
      found_merge = true
    end
  end

  eq(found_merge, true)

  child.type_keys("q")
  cleanup_repo(child, repo)
end

return T
