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

return T
