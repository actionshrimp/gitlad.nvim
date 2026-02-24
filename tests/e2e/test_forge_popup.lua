-- End-to-end tests for gitlad.nvim forge popup
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

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

T["forge popup"] = MiniTest.new_set()

T["forge popup"]["N keybinding is registered on status buffer"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Check that N keymap exists on the buffer
  child.lua([[
    _G._test_has_n = false
    local maps = vim.api.nvim_buf_get_keymap(0, "n")
    for _, map in ipairs(maps) do
      if map.lhs == "N" then
        _G._test_has_n = true
      end
    end
  ]])
  local has_n_keymap = child.lua_get([[_G._test_has_n]])
  eq(has_n_keymap, true)

  helpers.cleanup_repo(child, repo)
end

T["forge popup"]["N appears in help popup"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Open help popup
  child.type_keys("?")
  helpers.wait_for_popup(child)

  -- Get popup content
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_forge = false
  for _, line in ipairs(lines) do
    if line:match("N%s+Forge") then
      found_forge = true
      break
    end
  end

  eq(found_forge, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["forge popup"]["forge popup module loads"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))

  -- Verify module loads
  child.lua([[
    local ok, forge_popup = pcall(require, "gitlad.popups.forge")
    _G._test_forge_ok = ok and type(forge_popup.open) == "function"
  ]])
  local ok = child.lua_get([[_G._test_forge_ok]])
  eq(ok, true)

  helpers.cleanup_repo(child, repo)
end

T["forge popup"]["_show_popup opens popup with provider info"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Directly call _show_popup with a mock provider
  child.lua([[
    local forge_popup = require("gitlad.popups.forge")
    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      list_prs = function() end,
      get_pr = function() end,
    }
    -- Get the status buffer's repo_state
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    forge_popup._show_popup(buf.repo_state, mock_provider)
  ]])
  helpers.wait_for_popup(child)

  -- Verify popup opened
  local win_count = child.lua_get([[#vim.api.nvim_list_wins()]])
  eq(win_count, 2)

  -- Verify popup content includes provider info
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_list = false
  for _, line in ipairs(lines) do
    if line:match("l%s+List pull requests") then
      found_list = true
      break
    end
  end
  eq(found_list, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["forge popup"]["_show_popup includes PR action keys"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Directly call _show_popup with a mock provider
  child.lua([[
    local forge_popup = require("gitlad.popups.forge")
    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      list_prs = function() end,
      get_pr = function() end,
    }
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    forge_popup._show_popup(buf.repo_state, mock_provider)
  ]])
  helpers.wait_for_popup(child)

  -- Verify popup content includes new actions
  child.lua([[
    popup_buf = vim.api.nvim_get_current_buf()
    popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[popup_lines]])

  local found_create = false
  local found_merge = false
  local found_close = false
  local found_reopen = false
  local found_open_browser = false
  for _, line in ipairs(lines) do
    if line:match("n%s+Create pull request") then
      found_create = true
    end
    if line:match("m%s+Merge pull request") then
      found_merge = true
    end
    if line:match("C%s+Close pull request") then
      found_close = true
    end
    if line:match("R%s+Reopen pull request") then
      found_reopen = true
    end
    if line:match("o%s+Open in browser") then
      found_open_browser = true
    end
  end
  eq(found_create, true)
  eq(found_merge, true)
  eq(found_close, true)
  eq(found_reopen, true)
  eq(found_open_browser, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["forge popup"]["_view_current_pr uses search_prs with head:<branch> query"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Get the current branch name
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    _G._test_branch = buf.repo_state.status and buf.repo_state.status.branch or "unknown"
  ]])
  local branch = child.lua_get([[_G._test_branch]])

  -- Call _view_current_pr with a mock provider that captures the search query
  child.lua([[
    local forge_popup = require("gitlad.popups.forge")
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()

    _G._test_search_query = nil
    _G._test_search_limit = nil

    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      search_prs = function(self, query, limit, cb)
        _G._test_search_query = query
        _G._test_search_limit = limit
        vim.schedule(function()
          cb({}, nil)
        end)
      end,
    }

    forge_popup._view_current_pr(buf.repo_state, mock_provider)
  ]])

  -- Wait for the async callback to fire
  helpers.wait_short(child, 200)

  local query = child.lua_get([[_G._test_search_query]])
  local limit = child.lua_get([[_G._test_search_limit]])

  -- Verify search_prs was called with correct query
  eq(type(query), "string")
  eq(query, "repo:testowner/testrepo is:pr is:open head:" .. branch)
  eq(limit, 1)

  helpers.cleanup_repo(child, repo)
end

T["forge popup"]["_view_current_pr opens pr_detail when PR found"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua(string.format([[vim.cmd("cd %s")]], repo))
  child.lua([[require("gitlad.ui.views.status").open()]])
  helpers.wait_for_status(child)

  -- Call _view_current_pr with a mock provider that returns a PR
  child.lua([[
    local forge_popup = require("gitlad.popups.forge")
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()

    _G._test_pr_detail_opened = nil

    -- Mock pr_detail.open to capture the call
    package.loaded["gitlad.ui.views.pr_detail"] = {
      open = function(repo_state, provider, pr_number)
        _G._test_pr_detail_opened = pr_number
      end,
    }

    local mock_provider = {
      provider_type = "github",
      owner = "testowner",
      repo = "testrepo",
      host = "github.com",
      search_prs = function(self, query, limit, cb)
        vim.schedule(function()
          cb({ { number = 99, head_ref = "test-branch" } }, nil)
        end)
      end,
    }

    forge_popup._view_current_pr(buf.repo_state, mock_provider)
  ]])

  helpers.wait_short(child, 200)

  local opened_pr = child.lua_get([[_G._test_pr_detail_opened]])
  eq(opened_pr, 99)

  -- Restore original module
  child.lua([[package.loaded["gitlad.ui.views.pr_detail"] = nil]])

  helpers.cleanup_repo(child, repo)
end

return T
