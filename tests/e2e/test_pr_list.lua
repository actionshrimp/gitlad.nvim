-- End-to-end tests for gitlad.nvim PR list view
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality
local expect = MiniTest.expect

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

--- Helper: open PR list with mock provider and data (no real HTTP)
---@param child table
---@param repo string
local function open_pr_list_with_mock(child, repo)
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  -- Create mock provider and open PR list directly with test data
  -- Note: the runtimepath includes the plugin root, so we can find fixtures from there
  child.lua([[
    local pr_list_view = require("gitlad.ui.views.pr_list")
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()

    -- Find fixture file via rtp (plugin root is in rtp)
    local fixture_path = nil
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      local candidate = path .. "/tests/fixtures/github/pr_list.json"
      if vim.fn.filereadable(candidate) == 1 then
        fixture_path = candidate
        break
      end
    end

    -- Load fixture data
    local f = io.open(fixture_path, "r")
    local json = f:read("*a")
    f:close()
    local data = vim.json.decode(json)

    -- Parse PRs from fixture
    local graphql = require("gitlad.forge.github.graphql")
    local prs = graphql.parse_pr_list(data)

    -- Create mock provider
    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      list_prs = function(self, opts, cb)
        -- Return cached PRs
        vim.schedule(function()
          cb(prs, nil)
        end)
      end,
      get_pr = function(self, num, cb)
        cb(nil, "Not implemented")
      end,
    }

    pr_list_view.open(buf.repo_state, mock_provider, {})
  ]])

  -- Wait for PR list buffer to appear
  helpers.wait_for_buffer(child, "gitlad://pr%-list")

  -- Wait a bit for async refresh to complete
  child.lua([[vim.wait(500, function() return false end)]])
end

T["pr list view"] = MiniTest.new_set()

T["pr list view"]["opens and shows PRs"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Verify buffer name
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-list") ~= nil, true)

  -- Verify PR data appears in buffer
  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should have PR lines (3 PRs in fixture)
  expect.equality(#lines >= 3, true)

  -- Check for PR numbers from fixture
  local found_42 = false
  local found_41 = false
  local found_40 = false
  for _, line in ipairs(lines) do
    if line:match("#42") then
      found_42 = true
    end
    if line:match("#41") then
      found_41 = true
    end
    if line:match("#40") then
      found_40 = true
    end
  end

  eq(found_42, true)
  eq(found_41, true)
  eq(found_40, true)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["gj/gk navigate between PRs"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Start at line 1
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])

  -- gj should move to next PR
  child.type_keys("gj")
  local line_after_gj = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(line_after_gj, 2)

  -- gk should move back
  child.type_keys("gk")
  local line_after_gk = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(line_after_gk, 1)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["y yanks PR number"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Position on first PR
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])

  -- Yank
  child.type_keys("y")

  -- Wait for notify + register to be set
  child.lua([[vim.wait(100, function() return false end)]])

  -- Check register
  local reg = child.lua_get([[vim.fn.getreg('"')]])
  eq(reg, "#42")

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["q closes buffer"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Verify we're in PR list
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-list") ~= nil, true)

  -- Close with q
  child.type_keys("q")

  -- Should be back to a non-PR-list buffer
  bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-list") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["filetype is set correctly"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  local ft = child.lua_get([[vim.bo.filetype]])
  eq(ft, "gitlad-pr-list")

  helpers.cleanup_repo(child, repo)
end

return T
