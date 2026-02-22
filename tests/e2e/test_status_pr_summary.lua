-- End-to-end tests for gitlad.nvim status buffer PR summary line
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

T["status PR summary"] = MiniTest.new_set()

T["status PR summary"]["shows PR line when pr_info is set"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  -- Inject mock pr_info directly into repo_state
  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    buf.repo_state.pr_info = {
      number = 42,
      title = "Fix auth bug",
      state = "open",
      draft = false,
      author = { login = "octocat" },
      head_ref = "fix/auth-bug",
      base_ref = "main",
      review_decision = "APPROVED",
      labels = {},
      additions = 10,
      deletions = 3,
      created_at = "",
      updated_at = "",
      url = "",
    }
    buf.repo_state._pr_info_branch = buf.repo_state.status.branch
    -- Trigger re-render
    buf:render()
  ]])

  -- Wait for render
  child.lua([[vim.wait(200, function() return false end)]])

  -- Check for PR line in status buffer
  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_pr_line = false
  for _, line in ipairs(lines) do
    if line:match("PR:") and line:match("#42") and line:match("Fix auth bug") then
      found_pr_line = true
    end
  end
  eq(found_pr_line, true)

  helpers.cleanup_repo(child, repo)
end

T["status PR summary"]["includes review decision"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    buf.repo_state.pr_info = {
      number = 42,
      title = "Fix auth bug",
      state = "open",
      draft = false,
      author = { login = "octocat" },
      head_ref = "fix/auth-bug",
      base_ref = "main",
      review_decision = "APPROVED",
      labels = {},
      additions = 10,
      deletions = 3,
      created_at = "",
      updated_at = "",
      url = "",
    }
    buf.repo_state._pr_info_branch = buf.repo_state.status.branch
    buf:render()
  ]])

  child.lua([[vim.wait(200, function() return false end)]])

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_approved = false
  for _, line in ipairs(lines) do
    if line:match("PR:") and line:match("APPROVED") then
      found_approved = true
    end
  end
  eq(found_approved, true)

  helpers.cleanup_repo(child, repo)
end

T["status PR summary"]["includes diff stat"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    buf.repo_state.pr_info = {
      number = 42,
      title = "Fix auth bug",
      state = "open",
      draft = false,
      author = { login = "octocat" },
      head_ref = "fix/auth-bug",
      base_ref = "main",
      review_decision = nil,
      labels = {},
      additions = 10,
      deletions = 3,
      created_at = "",
      updated_at = "",
      url = "",
    }
    buf.repo_state._pr_info_branch = buf.repo_state.status.branch
    buf:render()
  ]])

  child.lua([[vim.wait(200, function() return false end)]])

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_stat = false
  for _, line in ipairs(lines) do
    if line:match("PR:") and line:match("+10 %-3") then
      found_stat = true
    end
  end
  eq(found_stat, true)

  helpers.cleanup_repo(child, repo)
end

T["status PR summary"]["includes checks indicator when checks_summary present"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    buf.repo_state.pr_info = {
      number = 42,
      title = "Fix auth bug",
      state = "open",
      draft = false,
      author = { login = "octocat" },
      head_ref = "fix/auth-bug",
      base_ref = "main",
      review_decision = "APPROVED",
      labels = {},
      additions = 10,
      deletions = 3,
      created_at = "",
      updated_at = "",
      url = "",
      checks_summary = {
        state = "success",
        total = 3,
        success = 3,
        failure = 0,
        pending = 0,
        checks = {},
      },
    }
    buf.repo_state._pr_info_branch = buf.repo_state.status.branch
    buf:render()
  ]])

  child.lua([[vim.wait(200, function() return false end)]])

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_checks = false
  for _, line in ipairs(lines) do
    if line:match("PR:") and line:match("%[3/3%]") then
      found_checks = true
    end
  end
  eq(found_checks, true)

  helpers.cleanup_repo(child, repo)
end

T["status PR summary"]["no checks indicator when checks_summary is nil"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    buf.repo_state.pr_info = {
      number = 42,
      title = "Fix auth bug",
      state = "open",
      draft = false,
      author = { login = "octocat" },
      head_ref = "fix/auth-bug",
      base_ref = "main",
      review_decision = nil,
      labels = {},
      additions = 10,
      deletions = 3,
      created_at = "",
      updated_at = "",
      url = "",
    }
    buf.repo_state._pr_info_branch = buf.repo_state.status.branch
    buf:render()
  ]])

  child.lua([[vim.wait(200, function() return false end)]])

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_bracket = false
  for _, line in ipairs(lines) do
    if line:match("PR:") and line:match("%[%d+/%d+%]") then
      found_bracket = true
    end
  end
  eq(found_bracket, false)

  helpers.cleanup_repo(child, repo)
end

T["status PR summary"]["does not show PR line when disabled in config"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'init'")

  -- Disable forge in config
  child.lua([[
    require("gitlad.config").setup({ forge = { show_pr_in_status = false } })
  ]])

  child.lua(string.format(
    [[
    vim.cmd("cd %s")
    require("gitlad.ui.views.status").open()
  ]],
    repo
  ))
  helpers.wait_for_status(child)

  child.lua([[
    local status_view = require("gitlad.ui.views.status")
    local buf = status_view.get_buffer()
    -- Even with pr_info set, it should not render because config disables it
    buf.repo_state.pr_info = {
      number = 42,
      title = "Fix auth bug",
      state = "open",
      draft = false,
      author = { login = "octocat" },
      head_ref = "fix/auth-bug",
      base_ref = "main",
      review_decision = "APPROVED",
      labels = {},
      additions = 10,
      deletions = 3,
      created_at = "",
      updated_at = "",
      url = "",
    }
    buf.repo_state._pr_info_branch = buf.repo_state.status.branch
    buf:render()
  ]])

  child.lua([[vim.wait(200, function() return false end)]])

  child.lua([[
    _G._test_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  local lines = child.lua_get([[_G._test_lines]])

  local found_pr_line = false
  for _, line in ipairs(lines) do
    if line:match("^PR:") then
      found_pr_line = true
    end
  end
  eq(found_pr_line, false)

  helpers.cleanup_repo(child, repo)
end

return T
