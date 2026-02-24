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

--- Helper: open PR detail with checks fixture (no real HTTP)
---@param child table
---@param repo string
local function open_pr_detail_with_checks(child, repo)
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()

    local fixture_path = nil
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      local candidate = path .. "/tests/fixtures/github/pr_detail_with_checks.json"
      if vim.fn.filereadable(candidate) == 1 then
        fixture_path = candidate
        break
      end
    end

    local f = io.open(fixture_path, "r")
    local json = f:read("*a")
    f:close()
    local data = vim.json.decode(json)

    local graphql = require("gitlad.forge.github.graphql")
    local pr = graphql.parse_pr_detail(data)

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

  helpers.wait_for_buffer(child, "gitlad://pr%-detail")
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
    if line:match("gj%s+Next comment/check") then
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

T["pr detail view"]["shows checks section when PR has checks"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_checks(child, repo)

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should show checks section header
  local found_checks_header = false
  local found_ci_test = false
  for _, line in ipairs(lines) do
    if line:match("Checks") then
      found_checks_header = true
    end
    if line:match("CI / test") then
      found_ci_test = true
    end
  end
  eq(found_checks_header, true)
  eq(found_ci_test, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["gj/gk navigate to check lines"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_checks(child, repo)

  -- Start at top
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])

  -- Navigate forward repeatedly, collecting line types
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    _G._visited_types = {}
    vim.api.nvim_win_set_cursor(0, {1, 0})
    for i = 1, 10 do
      vim.cmd("normal gj")
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local info = buf.line_map[line]
      if info then
        table.insert(_G._visited_types, info.type)
      end
    end
  ]])
  local visited_types = child.lua_get([[_G._visited_types]])

  -- Should have visited checks_header or check types
  local found_check_type = false
  for _, t in ipairs(visited_types) do
    if t == "check" or t == "checks_header" then
      found_check_type = true
    end
  end
  eq(found_check_type, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m keymap is registered on PR detail buffer"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Check that 'm' keymap exists on the buffer
  child.lua([[
    local maps = vim.api.nvim_buf_get_keymap(0, "n")
    _G._has_m_keymap = false
    for _, map in ipairs(maps) do
      if map.lhs == "m" then
        _G._has_m_keymap = true
      end
    end
  ]])
  local has_keymap = child.lua_get([[_G._has_m_keymap]])
  eq(has_keymap, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m opens merge strategy selector"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Override vim.ui.select to capture the call
  child.lua([[
    _G._select_called = false
    _G._select_items = nil
    _G._select_opts = nil
    vim.ui.select = function(items, opts, on_choice)
      _G._select_called = true
      _G._select_items = items
      _G._select_opts = opts
      -- Don't call on_choice (user cancels)
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  local select_called = child.lua_get([[_G._select_called]])
  eq(select_called, true)

  local items = child.lua_get([[_G._select_items]])
  eq(items, { "merge", "squash", "rebase" })

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m does nothing when PR is not open"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Set PR state to merged
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    buf.pr.state = "merged"
  ]])

  -- Override vim.ui.select to detect if it's called
  child.lua([[
    _G._select_called = false
    vim.ui.select = function(items, opts, on_choice)
      _G._select_called = true
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  local select_called = child.lua_get([[_G._select_called]])
  eq(select_called, false)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["help popup includes merge entry"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  child.type_keys("?")

  child.lua([[
    _G._popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._popup_lines]])

  local found_merge = false
  for _, line in ipairs(lines) do
    if line:match("m%s+Merge PR") then
      found_merge = true
    end
  end
  eq(found_merge, true)

  child.type_keys("q")

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m warns on merge conflicts"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Set PR as conflicting
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    buf.pr.mergeable = "CONFLICTING"
  ]])

  -- Override vim.ui.select to capture calls
  child.lua([[
    _G._select_calls = {}
    vim.ui.select = function(items, opts, on_choice)
      table.insert(_G._select_calls, { items = items, prompt = opts.prompt })
      -- Don't call on_choice (user cancels)
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Should show confirmation prompt (Yes/No), not strategy selector
  child.lua([[
    _G._first_call = _G._select_calls[1]
  ]])
  local first_items = child.lua_get([[_G._first_call.items]])
  eq(first_items, { "Yes", "No" })

  local first_prompt = child.lua_get([[_G._first_call.prompt]])
  expect.equality(first_prompt:match("merge conflicts") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m warns on failing checks"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Set PR with failing checks
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    buf.pr.checks_summary = { state = "failure", total = 3, success = 1, failure = 2, pending = 0, checks = {} }
  ]])

  child.lua([[
    _G._select_calls = {}
    vim.ui.select = function(items, opts, on_choice)
      table.insert(_G._select_calls, { items = items, prompt = opts.prompt })
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  local first_items = child.lua_get([[_G._select_calls[1].items]])
  eq(first_items, { "Yes", "No" })

  local first_prompt = child.lua_get([[_G._select_calls[1].prompt]])
  expect.equality(first_prompt:match("check%(s%) failing") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m warns on changes requested"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Set PR with changes requested
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    buf.pr.review_decision = "CHANGES_REQUESTED"
  ]])

  child.lua([[
    _G._select_calls = {}
    vim.ui.select = function(items, opts, on_choice)
      table.insert(_G._select_calls, { items = items, prompt = opts.prompt })
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  local first_items = child.lua_get([[_G._select_calls[1].items]])
  eq(first_items, { "Yes", "No" })

  local first_prompt = child.lua_get([[_G._select_calls[1].prompt]])
  expect.equality(first_prompt:match("Changes requested") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["m proceeds directly when PR is clean"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_mock(child, repo)

  -- Fixture already has MERGEABLE + CLEAN + APPROVED, so no warnings

  child.lua([[
    _G._select_calls = {}
    vim.ui.select = function(items, opts, on_choice)
      table.insert(_G._select_calls, { items = items, prompt = opts.prompt })
    end
  ]])

  child.type_keys("m")
  child.lua([[vim.wait(200, function() return false end)]])

  -- Should go straight to strategy selector (no Yes/No confirmation)
  local first_items = child.lua_get([[_G._select_calls[1].items]])
  eq(first_items, { "merge", "squash", "rebase" })

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["TAB toggles checks section"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_checks(child, repo)

  -- Count lines with checks
  local initial_count = child.lua_get([[vim.api.nvim_buf_line_count(0)]])

  -- Navigate to checks header and press TAB to collapse
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    -- Find the checks header line
    for line_nr, info in pairs(buf.line_map) do
      if info.type == "checks_header" then
        vim.api.nvim_win_set_cursor(0, {line_nr, 0})
        break
      end
    end
  ]])

  child.type_keys("<Tab>")
  child.lua([[vim.wait(100, function() return false end)]])

  local collapsed_count = child.lua_get([[vim.api.nvim_buf_line_count(0)]])

  -- Should have fewer lines after collapsing
  expect.equality(collapsed_count < initial_count, true)

  -- Press TAB again to expand
  child.type_keys("<Tab>")
  child.lua([[vim.wait(100, function() return false end)]])

  local expanded_count = child.lua_get([[vim.api.nvim_buf_line_count(0)]])

  -- Should be back to original count
  eq(expanded_count, initial_count)

  helpers.cleanup_repo(child, repo)
end

--- Helper: open PR detail with many-checks fixture (>5 successful → sub-section)
---@param child table
---@param repo string
local function open_pr_detail_with_many_checks(child, repo)
  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()

    local fixture_path = nil
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      local candidate = path .. "/tests/fixtures/github/pr_detail_many_checks.json"
      if vim.fn.filereadable(candidate) == 1 then
        fixture_path = candidate
        break
      end
    end

    local f = io.open(fixture_path, "r")
    local json = f:read("*a")
    f:close()
    local data = vim.json.decode(json)

    local graphql = require("gitlad.forge.github.graphql")
    local pr = graphql.parse_pr_detail(data)

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

  helpers.wait_for_buffer(child, "gitlad://pr%-detail")
  child.lua([[vim.wait(500, function() return false end)]])
end

T["pr detail view"]["shows sub-section header when category has > 5 checks"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_many_checks(child, repo)

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should have a sub-section header for Successful (7 checks > 5 threshold)
  local found_sub_header = false
  for _, line in ipairs(lines) do
    if line:match("Successful") and line:match("%(7%)") then
      found_sub_header = true
    end
  end
  eq(found_sub_header, true)

  -- Failed checks (2) should be flat, no sub-header for Failed
  local found_failed_sub_header = false
  for _, line in ipairs(lines) do
    if line:match("Failed") and line:match("%(2%)") then
      found_failed_sub_header = true
    end
  end
  eq(found_failed_sub_header, false)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["Tab on sub-section header toggles that sub-section"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_many_checks(child, repo)

  local initial_count = child.lua_get([[vim.api.nvim_buf_line_count(0)]])

  -- Navigate to the sub-section header for Successful
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    for line_nr, info in pairs(buf.line_map) do
      if info.type == "checks_sub_header" and info.sub_category == "successful" then
        vim.api.nvim_win_set_cursor(0, {line_nr, 0})
        break
      end
    end
  ]])

  -- Press Tab to collapse the sub-section
  child.type_keys("<Tab>")
  child.lua([[vim.wait(100, function() return false end)]])

  local collapsed_count = child.lua_get([[vim.api.nvim_buf_line_count(0)]])

  -- Should have fewer lines (7 check lines hidden)
  expect.equality(collapsed_count < initial_count, true)
  eq(initial_count - collapsed_count, 7)

  -- Press Tab again to expand
  -- Re-navigate to the sub-section header (line numbers may have shifted)
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    for line_nr, info in pairs(buf.line_map) do
      if info.type == "checks_sub_header" and info.sub_category == "successful" then
        vim.api.nvim_win_set_cursor(0, {line_nr, 0})
        break
      end
    end
  ]])
  child.type_keys("<Tab>")
  child.lua([[vim.wait(100, function() return false end)]])

  local expanded_count = child.lua_get([[vim.api.nvim_buf_line_count(0)]])
  eq(expanded_count, initial_count)

  helpers.cleanup_repo(child, repo)
end

T["pr detail view"]["gj/gk navigate to sub-section headers"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_detail_with_many_checks(child, repo)

  -- Navigate forward and check if we visit checks_sub_header
  child.lua([[
    local pr_detail_view = require("gitlad.ui.views.pr_detail")
    local buf = pr_detail_view.get_buffer()
    _G._visited_sub_headers = {}
    vim.api.nvim_win_set_cursor(0, {1, 0})
    for i = 1, 20 do
      vim.cmd("normal gj")
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local info = buf.line_map[line]
      if info and info.type == "checks_sub_header" then
        table.insert(_G._visited_sub_headers, info.sub_category)
      end
    end
  ]])
  local visited = child.lua_get([[_G._visited_sub_headers]])

  -- Should have visited the successful sub-header
  local found_successful = false
  for _, cat in ipairs(visited) do
    if cat == "successful" then
      found_successful = true
    end
  end
  eq(found_successful, true)

  helpers.cleanup_repo(child, repo)
end

return T
