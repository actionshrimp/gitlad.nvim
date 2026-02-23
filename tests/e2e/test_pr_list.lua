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

--- Helper: open PR list with sectioned mock provider (viewer + search_prs)
---@param child table
---@param repo string
---@param opts? { viewer_fail?: boolean }
local function open_pr_list_with_mock(child, repo, opts)
  opts = opts or {}
  local viewer_fail = opts.viewer_fail or false

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  -- Set viewer_fail flag in the child process first
  child.lua("_G._test_viewer_fail = " .. tostring(viewer_fail))

  -- Create mock provider with get_viewer + search_prs support
  child.lua([[
    local pr_list_view = require("gitlad.ui.views.pr_list")
    local status_view = require("gitlad.ui.views.status")
    local forge = require("gitlad.forge")
    local buf = status_view.get_buffer()

    -- Find fixture file via rtp
    local fixture_path = nil
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      local candidate = path .. "/tests/fixtures/github/pr_search.json"
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
    local prs = graphql.parse_pr_search(data)

    local viewer_fail = _G._test_viewer_fail

    -- Create mock provider with sectioned support
    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      list_prs = function(self, opts, cb)
        vim.schedule(function()
          cb(prs, nil)
        end)
      end,
      get_pr = function(self, num, cb)
        cb(nil, "Not implemented")
      end,
      get_viewer = function(self, cb)
        vim.schedule(function()
          if viewer_fail then
            cb(nil, "Auth failed")
          else
            cb("octocat", nil)
          end
        end)
      end,
      search_prs = function(self, query, limit, cb)
        vim.schedule(function()
          -- Return different subsets based on query
          if query:match("review%-requested:") then
            -- Return only PR #40 for review requests
            local review_prs = {}
            for _, pr in ipairs(prs) do
              if pr.number == 40 then
                table.insert(review_prs, pr)
              end
            end
            cb(review_prs, nil)
          elseif query:match("is:merged") then
            -- Return empty for recently merged
            cb({}, nil)
          else
            -- Return PRs #42 and #41 for "my PRs"
            local my_prs = {}
            for _, pr in ipairs(prs) do
              if pr.number == 42 or pr.number == 41 then
                table.insert(my_prs, pr)
              end
            end
            cb(my_prs, nil)
          end
        end)
      end,
    }

    -- Clear forge viewer cache so our mock is used
    forge._clear_cache()

    pr_list_view.open(buf.repo_state, mock_provider, {})
  ]])

  -- Wait for PR list buffer to appear
  helpers.wait_for_buffer(child, "gitlad://pr%-list")

  -- Wait for async refresh to complete
  child.lua([[vim.wait(500, function() return false end)]])
end

T["pr list view"] = MiniTest.new_set()

T["pr list view"]["opens with sectioned layout"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Verify buffer name
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-list") ~= nil, true)

  -- Verify section headers appear
  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_my_prs = false
  local found_review = false
  for _, line in ipairs(lines) do
    if line:match("^My Pull Requests") then
      found_my_prs = true
    end
    if line:match("^Review Requests") then
      found_review = true
    end
  end

  eq(found_my_prs, true)
  eq(found_review, true)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["section headers show correct PR counts"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_my_count = false
  local found_review_count = false
  for _, line in ipairs(lines) do
    if line:match("^My Pull Requests %(2%)") then
      found_my_count = true
    end
    if line:match("^Review Requests %(1%)") then
      found_review_count = true
    end
  end

  eq(found_my_count, true)
  eq(found_review_count, true)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["shows PR numbers from fixture data"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

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

T["pr list view"]["gj/gk navigate between PRs skipping headers"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Start at line 1 (section header)
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])

  -- gj should jump to first PR line (skipping header)
  child.type_keys("gj")
  local line_after_gj = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")

  -- Verify we landed on a PR line (not the header)
  child.lua(
    "local buf = require('gitlad.ui.views.pr_list').get_buffer(); local info = buf.line_map["
      .. line_after_gj
      .. "]; _G._test_info_type = info and info.type or 'none'"
  )
  local pr_info = child.lua_get("_G._test_info_type")
  eq(pr_info, "pr")

  -- Continue navigating with gj
  child.type_keys("gj")
  local line_after_gj2 = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")

  -- Should land on another PR line
  child.lua(
    "local buf = require('gitlad.ui.views.pr_list').get_buffer(); local info = buf.line_map["
      .. line_after_gj2
      .. "]; _G._test_info_type2 = info and info.type or 'none'"
  )
  local pr_info2 = child.lua_get("_G._test_info_type2")
  eq(pr_info2, "pr")

  -- gk should go back
  child.type_keys("gk")
  local line_after_gk = child.lua_get("vim.api.nvim_win_get_cursor(0)[1]")
  eq(line_after_gk, line_after_gj)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["Tab toggles section collapse"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Get initial line count
  local initial_count = child.lua_get("vim.api.nvim_buf_line_count(0)")

  -- Move to first line (should be section header)
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])

  -- Press Tab to collapse
  child.type_keys("\t")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Line count should decrease (section PRs hidden)
  local collapsed_count = child.lua_get("vim.api.nvim_buf_line_count(0)")
  expect.equality(collapsed_count < initial_count, true)

  -- Press Tab again to expand
  child.type_keys("\t")
  child.lua([[vim.wait(100, function() return false end)]])

  -- Line count should be back to initial
  local expanded_count = child.lua_get("vim.api.nvim_buf_line_count(0)")
  eq(expanded_count, initial_count)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["falls back to flat list on viewer failure"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo, { viewer_fail = true })

  -- Verify buffer exists
  local bufname = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
  expect.equality(bufname:match("gitlad://pr%-list") ~= nil, true)

  -- In fallback mode, should show PRs without section headers
  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  -- Should have PR lines but NO section headers
  local found_section_header = false
  local found_pr = false
  for _, line in ipairs(lines) do
    if line:match("^My Pull Requests") or line:match("^Review Requests") then
      found_section_header = true
    end
    if line:match("#42") then
      found_pr = true
    end
  end

  eq(found_section_header, false)
  eq(found_pr, true)

  helpers.cleanup_repo(child, repo)
end

T["pr list view"]["y yanks PR number"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Navigate to first PR
  child.lua([[vim.api.nvim_win_set_cursor(0, {1, 0})]])
  child.type_keys("gj")

  -- Yank
  child.type_keys("y")

  -- Wait for register to be set
  child.lua([[vim.wait(100, function() return false end)]])

  -- Check register contains a PR number
  local reg = child.lua_get([[vim.fn.getreg('"')]])
  expect.equality(reg:match("^#%d+$") ~= nil, true)

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

T["pr list view"]["? opens help popup with Tab entry"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  open_pr_list_with_mock(child, repo)

  -- Press ? to open help popup
  child.type_keys("?")

  -- Get popup content
  child.lua([[
    _G._popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._popup_lines]])

  -- Verify key entries are present
  local found_tab = false
  local found_gj = false
  local found_cr = false

  for _, line in ipairs(lines) do
    if line:match("<Tab>%s+Toggle section") then
      found_tab = true
    end
    if line:match("gj%s+Next PR") then
      found_gj = true
    end
    if line:match("<CR>%s+View PR") then
      found_cr = true
    end
  end

  eq(found_tab, true)
  eq(found_gj, true)
  eq(found_cr, true)

  -- Close help
  child.type_keys("q")

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
