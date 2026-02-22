local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local graphql = require("gitlad.forge.github.graphql")

-- Load fixture data
local function load_fixture(name)
  local path = "tests/fixtures/github/" .. name
  local f = io.open(path, "r")
  if not f then
    error("Could not open fixture: " .. path)
  end
  local content = f:read("*a")
  f:close()
  return vim.json.decode(content)
end

-- =============================================================================
-- queries
-- =============================================================================

T["queries"] = MiniTest.new_set()

T["queries"]["pr_list query string is defined"] = function()
  expect.equality(type(graphql.queries.pr_list), "string")
  expect.equality(graphql.queries.pr_list:match("pullRequests") ~= nil, true)
end

-- =============================================================================
-- parse_pr_list
-- =============================================================================

T["parse_pr_list()"] = MiniTest.new_set()

T["parse_pr_list()"]["parses fixture data correctly"] = function()
  local data = load_fixture("pr_list.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)
  eq(#prs, 3)

  -- First PR
  eq(prs[1].number, 42)
  eq(prs[1].title, "Fix authentication bug in login flow")
  eq(prs[1].state, "open")
  eq(prs[1].draft, false)
  eq(prs[1].author.login, "octocat")
  eq(prs[1].head_ref, "fix/auth-bug")
  eq(prs[1].base_ref, "main")
  eq(prs[1].review_decision, "APPROVED")
  eq(#prs[1].labels, 2)
  eq(prs[1].labels[1], "bug")
  eq(prs[1].labels[2], "priority:high")
  eq(prs[1].additions, 10)
  eq(prs[1].deletions, 3)
  eq(prs[1].url, "https://github.com/owner/repo/pull/42")
  expect.equality(prs[1].body ~= nil, true)
end

T["parse_pr_list()"]["parses draft PR correctly"] = function()
  local data = load_fixture("pr_list.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)

  -- Second PR is a draft
  eq(prs[2].number, 41)
  eq(prs[2].draft, true)
  eq(prs[2].review_decision, vim.NIL)
end

T["parse_pr_list()"]["parses changes requested PR"] = function()
  local data = load_fixture("pr_list.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)

  -- Third PR has changes requested
  eq(prs[3].number, 40)
  eq(prs[3].review_decision, "CHANGES_REQUESTED")
  eq(#prs[3].labels, 0)
end

T["parse_pr_list()"]["returns error for nil data"] = function()
  local prs, err = graphql.parse_pr_list(nil)
  eq(prs, nil)
  expect.equality(err ~= nil, true)
end

T["parse_pr_list()"]["returns error for GraphQL errors"] = function()
  local data = {
    errors = {
      { message = "Could not resolve to a Repository" },
    },
  }
  local prs, err = graphql.parse_pr_list(data)
  eq(prs, nil)
  expect.equality(err:match("GraphQL error") ~= nil, true)
  expect.equality(err:match("Could not resolve") ~= nil, true)
end

T["parse_pr_list()"]["returns error for missing repository"] = function()
  local data = { data = {} }
  local prs, err = graphql.parse_pr_list(data)
  eq(prs, nil)
  expect.equality(err:match("Repository not found") ~= nil, true)
end

T["parse_pr_list()"]["handles missing author gracefully"] = function()
  local data = {
    data = {
      repository = {
        pullRequests = {
          nodes = {
            {
              number = 1,
              title = "Test",
              state = "OPEN",
              isDraft = false,
              author = nil,
              headRefName = "test",
              baseRefName = "main",
              labels = { nodes = {} },
              additions = 0,
              deletions = 0,
              createdAt = "",
              updatedAt = "",
              url = "",
            },
          },
        },
      },
    },
  }
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)
  eq(prs[1].author.login, "ghost")
end

T["parse_pr_list()"]["handles empty PR list"] = function()
  local data = {
    data = {
      repository = {
        pullRequests = {
          nodes = {},
        },
      },
    },
  }
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)
  eq(#prs, 0)
end

T["parse_pr_list()"]["lowercases state values"] = function()
  local data = {
    data = {
      repository = {
        pullRequests = {
          nodes = {
            {
              number = 1,
              title = "Test",
              state = "MERGED",
              isDraft = false,
              author = { login = "user" },
              headRefName = "test",
              baseRefName = "main",
              labels = { nodes = {} },
              additions = 0,
              deletions = 0,
              createdAt = "",
              updatedAt = "",
              url = "",
            },
          },
        },
      },
    },
  }
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)
  eq(prs[1].state, "merged")
end

return T
