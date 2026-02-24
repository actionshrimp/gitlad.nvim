local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local github = require("gitlad.forge.github")

-- =============================================================================
-- new (provider construction)
-- =============================================================================

T["new()"] = MiniTest.new_set()

T["new()"]["creates provider with correct fields"] = function()
  local provider = github.new("owner", "repo", "https://api.github.com", "token123")
  eq(provider.owner, "owner")
  eq(provider.repo, "repo")
  eq(provider.host, "api.github.com")
  eq(provider.provider_type, "github")
end

T["new()"]["has list_prs method"] = function()
  local provider = github.new("owner", "repo", "https://api.github.com", "token123")
  eq(type(provider.list_prs), "function")
end

T["new()"]["has get_pr method"] = function()
  local provider = github.new("owner", "repo", "https://api.github.com", "token123")
  eq(type(provider.get_pr), "function")
end

T["new()"]["extracts host from GHE API URL"] = function()
  local provider = github.new("org", "project", "https://github.mycompany.com/api/v3", "token")
  eq(provider.host, "github.mycompany.com")
end

-- =============================================================================
-- list_prs (with mocked HTTP)
-- =============================================================================

T["list_prs()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Store original executor
      _G._test_original_executor = nil
    end,
    post_case = function()
      -- Reset HTTP executor
      require("gitlad.forge.http")._set_executor(nil)
    end,
  },
})

T["list_prs()"]["calls HTTP with correct GraphQL query"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    -- Capture the curl command to inspect it
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    -- Return mock response
    local fixture = io.open("tests/fixtures/github/pr_list.json", "r")
    local json_body = fixture:read("*a")
    fixture:close()
    opts.on_stdout(nil, vim.split(json_body .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local provider = github.new("owner", "repo", "https://api.github.com", "test-token")
  local got_prs = nil

  provider:list_prs({ state = "open" }, function(prs, err)
    got_prs = prs
  end)

  -- Flush vim.schedule
  vim.wait(200, function()
    return got_prs ~= nil
  end, 10)

  -- Verify request contains GraphQL query
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  expect.equality(body.query:match("pullRequests") ~= nil, true)
  eq(body.variables.owner, "owner")
  eq(body.variables.repo, "repo")

  -- Verify parsed PRs
  eq(#got_prs, 3)
  eq(got_prs[1].number, 42)
end

T["list_prs()"]["handles HTTP error"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    opts.on_stderr(nil, { "Connection refused", "" })
    opts.on_exit(nil, 7)
    return 1
  end)

  local provider = github.new("owner", "repo", "https://api.github.com", "test-token")
  local got_err = nil

  provider:list_prs({}, function(prs, err)
    got_err = err
  end)

  vim.wait(200, function()
    return got_err ~= nil
  end, 10)

  expect.equality(got_err ~= nil, true)
end

-- =============================================================================
-- get_pr (with mocked HTTP)
-- =============================================================================

T["get_pr()"] = MiniTest.new_set({
  hooks = {
    post_case = function()
      require("gitlad.forge.http")._set_executor(nil)
    end,
  },
})

T["get_pr()"]["calls HTTP with correct GraphQL query"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local fixture = io.open("tests/fixtures/github/pr_detail.json", "r")
    local json_body = fixture:read("*a")
    fixture:close()
    opts.on_stdout(nil, vim.split(json_body .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local provider = github.new("owner", "repo", "https://api.github.com", "test-token")
  local got_pr = nil

  provider:get_pr(42, function(pr, err)
    got_pr = pr
  end)

  vim.wait(200, function()
    return got_pr ~= nil
  end, 10)

  -- Verify request contains correct query
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  expect.equality(body.query:match("pullRequest%(number:") ~= nil, true)
  eq(body.variables.owner, "owner")
  eq(body.variables.repo, "repo")
  eq(body.variables.number, 42)

  -- Verify parsed PR
  eq(got_pr.number, 42)
  eq(got_pr.title, "Fix authentication bug in login flow")
  eq(#got_pr.comments, 2)
  eq(#got_pr.reviews, 1)
  eq(#got_pr.timeline, 3)
end

T["get_pr()"]["handles HTTP error"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    opts.on_stderr(nil, { "Connection refused", "" })
    opts.on_exit(nil, 7)
    return 1
  end)

  local provider = github.new("owner", "repo", "https://api.github.com", "test-token")
  local got_err = nil

  provider:get_pr(42, function(pr, err)
    got_err = err
  end)

  vim.wait(200, function()
    return got_err ~= nil
  end, 10)

  expect.equality(got_err ~= nil, true)
end

-- =============================================================================
-- search_prs (with mocked HTTP)
-- =============================================================================

T["search_prs()"] = MiniTest.new_set({
  hooks = {
    post_case = function()
      require("gitlad.forge.http")._set_executor(nil)
    end,
  },
})

T["search_prs()"]["sends correct search query to GraphQL"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local fixture = io.open("tests/fixtures/github/pr_search.json", "r")
    local json_body = fixture:read("*a")
    fixture:close()
    opts.on_stdout(nil, vim.split(json_body .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local provider = github.new("owner", "repo", "https://api.github.com", "test-token")
  local got_prs = nil

  local query = "repo:owner/repo is:pr is:open head:fix/auth-bug"
  provider:search_prs(query, 1, function(prs, err)
    got_prs = prs
  end)

  vim.wait(200, function()
    return got_prs ~= nil
  end, 10)

  -- Verify request contains the search query
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  expect.equality(body.query:match("search") ~= nil, true)
  eq(body.variables.searchQuery, "repo:owner/repo is:pr is:open head:fix/auth-bug")
  eq(body.variables.first, 1)

  -- Verify parsed PRs
  eq(#got_prs, 3)
  eq(got_prs[1].number, 42)
  eq(got_prs[1].head_ref, "fix/auth-bug")
end

return T
