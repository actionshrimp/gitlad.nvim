-- End-to-end tests for gitlad.nvim PR detail view
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

--- Helper: open PR detail with mock provider and data (no real HTTP)
---@param child table
---@param repo string
local function open_pr_detail_with_mock(child, repo)
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  -- Create mock provider and open PR detail directly
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()

    -- Find fixture file via rtp
    local fixture_path = nil
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      local candidate = path .. "/tests/fixtures/github/pr_detail.json"
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

    -- Parse PR from fixture
    local graphql = require("gitlad.forge.github.graphql")
    local pr = graphql.parse_pr_detail(data)

    -- Create mock provider
    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      list_prs = function(self, opts, cb)
        vim.schedule(function() cb({}, nil) end)
      end,
      get_pr = function(self, num, cb)
        vim.schedule(function() cb(pr, nil) end)
      end,
    }

    pr_detail_view.open(buf.repo_state, mock_provider, 42)
  ]])

  -- Wait for PR detail buffer to appear
  helpers.wait_for_buffer(child, "gitlad://pr%-detail")

  -- Wait for async refresh to complete
  child.lua([[vim.wait(500, function() return false end)]])
end

T["pr detail view"] = MiniTest.new_set()

T["pr detail view"]["opens and shows PR header"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Verify buffer name
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-detail") ~= nil, true)

  -- Verify PR data appears in buffer
  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should have title
  local found_title = false
  for _, line in ipairs(lines) do
    if line:match("#42") and line:match("Fix authentication bug") then
      found_title = true
    end
  end
  eq(found_title, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["shows comments"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should show comments
  local found_reviewer = false
  local found_comment_section = false
  for _, line in ipairs(lines) do
    if line:match("@reviewer") then
      found_reviewer = true
    end
    if line:match("Comments %(2%)") then
      found_comment_section = true
    end
  end
  eq(found_reviewer, true)
  eq(found_comment_section, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["shows reviews"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should show review section
  local found_review_section = false
  local found_approved = false
  for _, line in ipairs(lines) do
    if line:match("Reviews %(1%)") then
      found_review_section = true
    end
    if line:match("APPROVED") then
      found_approved = true
    end
  end
  eq(found_review_section, true)
  eq(found_approved, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["? opens help popup"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Press ? to open help popup
  child.type_keys("?")

  -- Verify popup window exists (should be 2 windows now)
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Get popup content
  child.lua([[
    _G._popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._popup_lines]])

  -- Verify sections are present
  local found_actions = false
  local found_navigation = false
  local found_essential = false
  local found_comment = false
  local found_edit = false
  local found_gj = false

  for _, line in ipairs(lines) do
    if line:match("^Actions") then
      found_actions = true
    end
    if line:match("^Navigation") then
      found_navigation = true
    end
    if line:match("^Essential commands") then
      found_essential = true
    end
    if line:match("c%s+Add comment") then
      found_comment = true
    end
    if line:match("e%s+Edit comment") then
      found_edit = true
    end
    if line:match("gj%s+Next comment") then
      found_gj = true
    end
  end

  eq(found_actions, true)
  eq(found_navigation, true)
  eq(found_essential, true)
  eq(found_comment, true)
  eq(found_edit, true)
  eq(found_gj, true)

  -- Close help
  child.type_keys("q")

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["filetype is set correctly"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  local ft = child.lua_get([[vim.bo.filetype]])
  eq(ft, "gitlad-pr-detail")

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["y yanks PR number"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  child.type_keys("y")
  child.lua([[vim.wait(100, function() return false end)]])

  local reg = child.lua_get([[vim.fn.getreg('"')]])
  eq(reg, "#42")

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["q closes buffer"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Verify we're in PR detail
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-detail") ~= nil, true)

  -- Close with q
  child.type_keys("q")

  -- Should be back to a non-PR-detail buffer
  bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-detail") == nil, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["gj/gk navigate between comments"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Start at top
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])

  -- gj should move to first comment/review
  child.type_keys("gj")
  local line1 = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")

  -- gj again should move to next
  child.type_keys("gj")
  local line2 = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")

  -- Should have moved forward
  expect.equality(line2 > line1, true)

  -- gk should move back
  child.type_keys("gk")
  local line3 = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(line3, line1)

  helpers.cleanup_repo(child, repo)
end

return T
