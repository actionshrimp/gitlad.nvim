-- End-to-end tests for gitlad.nvim rebase editor and instant fixup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local expect = MiniTest.expect

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

T["rebase_editor"] = MiniTest.new_set()

T["rebase_editor"]["module loads in child process"] = function()
  local child = _G.child

  local result = child.lua([[
    local ok, rebase_editor = pcall(require, "gitlad.ui.views.rebase_editor")
    return { ok = ok, has_open = type(rebase_editor.open) == "function" }
  ]])

  expect.equality(result.ok, true)
  expect.equality(result.has_open, true)
end

T["rebase_editor"]["is_active returns false initially"] = function()
  local child = _G.child

  local result = child.lua([[
    local rebase_editor = require("gitlad.ui.views.rebase_editor")
    return rebase_editor.is_active()
  ]])

  expect.equality(result, false)
end

T["client"] = MiniTest.new_set()

T["client"]["get_envs_git_editor returns valid env table"] = function()
  local child = _G.child

  local result = child.lua([[
    local client = require("gitlad.client")
    local env = client.get_envs_git_editor()
    return {
      has_seq_editor = env.GIT_SEQUENCE_EDITOR ~= nil,
      has_editor = env.GIT_EDITOR ~= nil,
      seq_contains_nvim = env.GIT_SEQUENCE_EDITOR:find("nvim") ~= nil,
      seq_contains_headless = env.GIT_SEQUENCE_EDITOR:find("headless") ~= nil,
    }
  ]])

  expect.equality(result.has_seq_editor, true)
  expect.equality(result.has_editor, true)
  expect.equality(result.seq_contains_nvim, true)
  expect.equality(result.seq_contains_headless, true)
end

T["prompt"] = MiniTest.new_set()

T["prompt"]["module loads in child process"] = function()
  local child = _G.child

  local result = child.lua([[
    local ok, prompt = pcall(require, "gitlad.utils.prompt")
    return {
      ok = ok,
      has_prompt_for_ref = type(prompt.prompt_for_ref) == "function",
      has_global_completion = type(_G.gitlad_complete_refs) == "function",
    }
  ]])

  expect.equality(result.ok, true)
  expect.equality(result.has_prompt_for_ref, true)
  expect.equality(result.has_global_completion, true)
end

T["commit_popup_instant"] = MiniTest.new_set()

T["commit_popup_instant"]["commit popup has instant fixup action"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a file and commit it
  create_file(child, repo, "file.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Initial commit'")

  -- Change to repo and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open commit popup with 'c'
  child.type_keys("c")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Check that the popup contains the instant fixup action
  child.lua([[
    _test_popup_bufnr = vim.api.nvim_get_current_buf()
    _test_popup_lines = vim.api.nvim_buf_get_lines(_test_popup_bufnr, 0, -1, false)
  ]])
  local lines = child.lua_get([[_test_popup_lines]])

  local found_instant_fixup = false
  local found_instant_squash = false
  for _, line in ipairs(lines) do
    if line:find("Instant fixup") then
      found_instant_fixup = true
    end
    if line:find("Instant squash") then
      found_instant_squash = true
    end
  end

  expect.equality(found_instant_fixup, true, "Should have Instant fixup action")
  expect.equality(found_instant_squash, true, "Should have Instant squash action")

  cleanup_repo(child, repo)
end

T["rebase_popup"] = MiniTest.new_set()

T["rebase_popup"]["has interactive action"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Change to repo and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open rebase popup with 'r'
  child.type_keys("r")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Check that the popup contains the interactive action
  child.lua([[
    _test_popup_bufnr = vim.api.nvim_get_current_buf()
    _test_popup_lines = vim.api.nvim_buf_get_lines(_test_popup_bufnr, 0, -1, false)
  ]])
  local lines = child.lua_get([[_test_popup_lines]])

  local found_interactive = false
  for _, line in ipairs(lines) do
    if line:find("interactively") then
      found_interactive = true
      break
    end
  end

  expect.equality(found_interactive, true, "Should have interactively action")

  cleanup_repo(child, repo)
end

T["commit_at_point"] = MiniTest.new_set()

-- Helper to setup repo with multiple commits and staged changes for instant operations
local function setup_repo_for_instant_op(child)
  local repo = helpers.create_test_repo(child)

  -- Create multiple commits so we have unpushed commits to target
  create_file(child, repo, "file1.txt", "content1")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'First commit'")

  create_file(child, repo, "file2.txt", "content2")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Second commit'")

  create_file(child, repo, "file3.txt", "content3")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Third commit'")

  -- Stage changes for the instant fixup/squash
  create_file(child, repo, "fixup_file.txt", "fixup content")
  git(child, repo, "add .")

  return repo
end

T["commit_at_point"]["instant fixup uses commit at point in status view"] = function()
  local child = _G.child
  local repo = setup_repo_for_instant_op(child)

  -- Change to repo and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Navigate to the Recent commits section and find a commit line
  -- Search for "First commit" which should be in the recent commits
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:find("First commit") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.lua([[vim.wait(100, function() return false end)]])

  -- Verify we're on a commit line by checking line content
  local current_line = child.lua_get([[vim.api.nvim_get_current_line()]])
  expect.equality(current_line:find("First commit") ~= nil, true, "Should be on First commit line")

  -- Open commit popup
  child.type_keys("c")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press F for instant fixup - should NOT open the commit selector since we have commit at point
  child.type_keys("F")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Check that we didn't open a commit selector (no floating window with commit list)
  -- The instant fixup should have started directly, so we should see a notification
  local messages = child.lua_get([[vim.fn.execute("messages")]])

  -- Should see "Creating fixup commit" message, not a commit selector popup
  -- (commit selector would have title "Fixup commit" but wouldn't show "Creating" message)
  expect.equality(
    messages:find("Creating fixup commit") ~= nil or messages:find("fixup applied") ~= nil,
    true,
    "Instant fixup should execute directly without commit selector"
  )

  cleanup_repo(child, repo)
end

T["commit_at_point"]["instant fixup uses commit at point in log view"] = function()
  local child = _G.child
  local repo = setup_repo_for_instant_op(child)

  -- Change to repo and open status first to get repo_state
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open log view via the popup
  child.type_keys("l")
  child.lua([[vim.wait(100, function() return false end)]])
  child.type_keys("l") -- Press 'l' again to show log
  child.lua([[vim.wait(500, function() return false end)]])

  -- Navigate to a commit line (should start on first commit)
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:find("First commit") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.lua([[vim.wait(100, function() return false end)]])

  -- Open commit popup
  child.type_keys("c")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press F for instant fixup
  child.type_keys("F")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Should see fixup execution message, not a selector
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  expect.equality(
    messages:find("Creating fixup commit") ~= nil or messages:find("fixup applied") ~= nil,
    true,
    "Instant fixup should execute directly from log view"
  )

  cleanup_repo(child, repo)
end

T["commit_at_point"]["instant squash uses commit at point in status view"] = function()
  local child = _G.child
  local repo = setup_repo_for_instant_op(child)

  -- Change to repo and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Navigate to a commit line
  child.lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:find("Second commit") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        break
      end
    end
  ]])
  child.lua([[vim.wait(100, function() return false end)]])

  -- Open commit popup
  child.type_keys("c")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press S for instant squash
  child.type_keys("S")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Should see squash execution message, not a selector
  local messages = child.lua_get([[vim.fn.execute("messages")]])
  expect.equality(
    messages:find("Creating squash commit") ~= nil or messages:find("squash applied") ~= nil,
    true,
    "Instant squash should execute directly without commit selector"
  )

  cleanup_repo(child, repo)
end

T["commit_at_point"]["instant fixup falls back to prompt when no commit at point"] = function()
  local child = _G.child
  local repo = setup_repo_for_instant_op(child)

  -- Change to repo and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Stay at top of buffer (header area, not on a commit)
  child.type_keys("gg")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Mock pickers to track if prompt was triggered
  -- Disable snacks and mini.pick to test vim.ui.input fallback
  child.lua([[
    _G.prompt_called = false
    _G.prompt_opts = nil

    -- Make snacks unavailable
    package.loaded["snacks"] = nil
    package.preload["snacks"] = function() error("snacks not available") end

    -- Make mini.pick unavailable
    package.loaded["mini.pick"] = nil
    package.preload["mini.pick"] = function() error("mini.pick not available") end

    -- Clear the prompt module cache to pick up the mocked dependencies
    package.loaded["gitlad.utils.prompt"] = nil

    -- Mock vim.ui.input
    local original_input = vim.ui.input
    vim.ui.input = function(opts, callback)
      _G.prompt_called = true
      _G.prompt_opts = opts
      -- Don't call callback (simulates user cancelling)
    end
  ]])

  -- Open commit popup
  child.type_keys("c")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Press F for instant fixup - should open prompt since not on a commit
  child.type_keys("F")
  child.lua([[vim.wait(200, function() return false end)]])

  -- vim.ui.input should have been called (fallback)
  local prompt_called = child.lua_get([[_G.prompt_called]])
  expect.equality(prompt_called, true, "Should prompt for ref when no commit at point")

  -- Check the prompt text
  local prompt = child.lua_get([[_G.prompt_opts and _G.prompt_opts.prompt or ""]])
  expect.equality(prompt:find("Fixup") ~= nil, true, "Prompt should mention fixup")

  -- Close status buffer
  child.type_keys("q")

  cleanup_repo(child, repo)
end

return T
