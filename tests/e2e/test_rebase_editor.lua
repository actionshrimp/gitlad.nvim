-- End-to-end tests for gitlad.nvim rebase editor and instant fixup
local MiniTest = require("mini.test")
local expect = MiniTest.expect

-- Helper to create a test git repository
local function create_test_repo(child)
  local repo = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
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

  local result = child.lua_get([[
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

T["commit_select"] = MiniTest.new_set()

T["commit_select"]["module loads in child process"] = function()
  local child = _G.child

  local result = child.lua([[
    local ok, commit_select = pcall(require, "gitlad.ui.views.commit_select")
    return {
      ok = ok,
      has_open = type(commit_select.open) == "function",
      has_close = type(commit_select.close) == "function",
    }
  ]])

  expect.equality(result.ok, true)
  expect.equality(result.has_open, true)
  expect.equality(result.has_close, true)
end

T["commit_popup_instant"] = MiniTest.new_set()

T["commit_popup_instant"]["commit popup has instant fixup action"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

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
  local lines = child.lua_get([[
    local bufnr = vim.api.nvim_get_current_buf()
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])

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
  local repo = create_test_repo(child)

  -- Change to repo and open status
  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  child.lua([[vim.wait(500, function() return false end)]])

  -- Open rebase popup with 'r'
  child.type_keys("r")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Check that the popup contains the interactive action
  local lines = child.lua_get([[
    local bufnr = vim.api.nvim_get_current_buf()
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])

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

return T
