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
-- queries.pr_review_threads
-- =============================================================================

T["queries"] = MiniTest.new_set()

T["queries"]["pr_review_threads query string is defined"] = function()
  expect.equality(type(graphql.queries.pr_review_threads), "string")
  expect.equality(graphql.queries.pr_review_threads:match("reviewThreads") ~= nil, true)
  expect.equality(graphql.queries.pr_review_threads:match("isResolved") ~= nil, true)
  expect.equality(graphql.queries.pr_review_threads:match("isOutdated") ~= nil, true)
  expect.equality(graphql.queries.pr_review_threads:match("diffSide") ~= nil, true)
  expect.equality(graphql.queries.pr_review_threads:match("databaseId") ~= nil, true)
end

-- =============================================================================
-- parse_review_threads
-- =============================================================================

T["parse_review_threads()"] = MiniTest.new_set()

T["parse_review_threads()"]["parses fixture data correctly"] = function()
  local data = load_fixture("pr_review_threads.json")
  local threads, pr_node_id, err = graphql.parse_review_threads(data)
  eq(err, nil)
  eq(pr_node_id, "PR_kwDOTest123")
  eq(#threads, 4)
end

T["parse_review_threads()"]["parses first thread (active, RIGHT side)"] = function()
  local data = load_fixture("pr_review_threads.json")
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)

  local t = threads[1]
  eq(t.id, "PRRT_thread1")
  eq(t.is_resolved, false)
  eq(t.is_outdated, false)
  eq(t.path, "src/main.lua")
  eq(t.line, 42)
  eq(t.original_line, 42)
  eq(t.start_line, nil)
  eq(t.diff_side, "RIGHT")

  -- 2 comments in thread
  eq(#t.comments, 2)
  eq(t.comments[1].author.login, "reviewer1")
  eq(t.comments[1].body, "Should we add rate limiting here?")
  eq(t.comments[1].database_id, 1001)
  eq(t.comments[2].author.login, "author1")
  eq(t.comments[2].body, "Good idea, I'll add in a follow-up")
  eq(t.comments[2].database_id, 1002)
end

T["parse_review_threads()"]["parses resolved thread"] = function()
  local data = load_fixture("pr_review_threads.json")
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)

  local t = threads[2]
  eq(t.id, "PRRT_thread2")
  eq(t.is_resolved, true)
  eq(t.is_outdated, false)
  eq(t.path, "src/utils.lua")
  eq(t.line, 15)
  eq(t.diff_side, "RIGHT")
  eq(#t.comments, 1)
end

T["parse_review_threads()"]["parses outdated thread with nil line"] = function()
  local data = load_fixture("pr_review_threads.json")
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)

  local t = threads[3]
  eq(t.id, "PRRT_thread3")
  eq(t.is_resolved, false)
  eq(t.is_outdated, true)
  eq(t.line, nil)
  eq(t.original_line, 8)
  eq(t.diff_side, "LEFT")
  eq(t.path, "src/main.lua")
end

T["parse_review_threads()"]["parses multi-line thread (start_line set)"] = function()
  local data = load_fixture("pr_review_threads.json")
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)

  local t = threads[4]
  eq(t.id, "PRRT_thread4")
  eq(t.start_line, 8)
  eq(t.line, 10)
  eq(t.diff_side, "RIGHT")
end

T["parse_review_threads()"]["parses comment timestamps"] = function()
  local data = load_fixture("pr_review_threads.json")
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)

  eq(threads[1].comments[1].created_at, "2026-02-20T10:30:00Z")
  eq(threads[1].comments[1].updated_at, "2026-02-20T10:30:00Z")
end

T["parse_review_threads()"]["returns error for nil data"] = function()
  local threads, pr_node_id, err = graphql.parse_review_threads(nil)
  eq(threads, nil)
  eq(pr_node_id, nil)
  expect.equality(err ~= nil, true)
end

T["parse_review_threads()"]["returns error for GraphQL errors"] = function()
  local data = {
    errors = {
      { message = "Could not resolve to a PullRequest" },
    },
  }
  local threads, pr_node_id, err = graphql.parse_review_threads(data)
  eq(threads, nil)
  eq(pr_node_id, nil)
  expect.equality(err:match("GraphQL error") ~= nil, true)
end

T["parse_review_threads()"]["returns error for missing repository"] = function()
  local data = { data = {} }
  local threads, pr_node_id, err = graphql.parse_review_threads(data)
  eq(threads, nil)
  eq(pr_node_id, nil)
  expect.equality(err:match("Repository not found") ~= nil, true)
end

T["parse_review_threads()"]["returns error for missing pull request"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = nil,
      },
    },
  }
  local threads, pr_node_id, err = graphql.parse_review_threads(data)
  eq(threads, nil)
  eq(pr_node_id, nil)
  expect.equality(err:match("Pull request not found") ~= nil, true)
end

T["parse_review_threads()"]["handles empty thread list"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          id = "PR_test",
          reviewThreads = {
            nodes = {},
          },
        },
      },
    },
  }
  local threads, pr_node_id, err = graphql.parse_review_threads(data)
  eq(err, nil)
  eq(pr_node_id, "PR_test")
  eq(#threads, 0)
end

T["parse_review_threads()"]["handles missing reviewThreads gracefully"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          id = "PR_test",
        },
      },
    },
  }
  local threads, pr_node_id, err = graphql.parse_review_threads(data)
  eq(err, nil)
  eq(pr_node_id, "PR_test")
  eq(#threads, 0)
end

T["parse_review_threads()"]["handles thread with empty comments"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          id = "PR_test",
          reviewThreads = {
            nodes = {
              {
                id = "PRRT_empty",
                isResolved = false,
                isOutdated = false,
                line = 5,
                originalLine = 5,
                startLine = vim.NIL,
                path = "test.lua",
                diffSide = "RIGHT",
                comments = { nodes = {} },
              },
            },
          },
        },
      },
    },
  }
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)
  eq(#threads, 1)
  eq(threads[1].id, "PRRT_empty")
  eq(#threads[1].comments, 0)
  eq(threads[1].start_line, nil) -- vim.NIL normalized to nil
end

T["parse_review_threads()"]["handles missing author in comment"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          id = "PR_test",
          reviewThreads = {
            nodes = {
              {
                id = "PRRT_1",
                isResolved = false,
                isOutdated = false,
                line = 1,
                originalLine = 1,
                startLine = vim.NIL,
                path = "test.lua",
                diffSide = "RIGHT",
                comments = {
                  nodes = {
                    {
                      id = "C1",
                      databaseId = 100,
                      author = nil,
                      body = "test",
                      createdAt = "2026-01-01T00:00:00Z",
                      updatedAt = "2026-01-01T00:00:00Z",
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  }
  local threads, _, err = graphql.parse_review_threads(data)
  eq(err, nil)
  eq(threads[1].comments[1].author.login, "ghost")
end

return T
