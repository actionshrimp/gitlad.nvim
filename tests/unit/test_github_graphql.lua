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

-- =============================================================================
-- queries.pr_detail
-- =============================================================================

T["queries"]["pr_detail query string is defined"] = function()
  expect.equality(type(graphql.queries.pr_detail), "string")
  expect.equality(graphql.queries.pr_detail:match("pullRequest") ~= nil, true)
  expect.equality(graphql.queries.pr_detail:match("comments") ~= nil, true)
  expect.equality(graphql.queries.pr_detail:match("reviews") ~= nil, true)
  expect.equality(graphql.queries.pr_detail:match("databaseId") ~= nil, true)
end

-- =============================================================================
-- parse_pr_detail
-- =============================================================================

T["parse_pr_detail()"] = MiniTest.new_set()

T["parse_pr_detail()"]["parses fixture data correctly"] = function()
  local data = load_fixture("pr_detail.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  -- PR metadata
  eq(pr.number, 42)
  eq(pr.title, "Fix authentication bug in login flow")
  eq(pr.state, "open")
  eq(pr.draft, false)
  eq(pr.author.login, "octocat")
  eq(pr.head_ref, "fix/auth-bug")
  eq(pr.base_ref, "main")
  eq(pr.review_decision, "APPROVED")
  eq(#pr.labels, 2)
  eq(pr.additions, 10)
  eq(pr.deletions, 3)
  expect.equality(pr.body ~= nil, true)
end

T["parse_pr_detail()"]["parses comments correctly"] = function()
  local data = load_fixture("pr_detail.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  -- 2 issue comments
  eq(#pr.comments, 2)
  eq(pr.comments[1].author.login, "reviewer")
  expect.equality(pr.comments[1].body:match("token expiry") ~= nil, true)
  eq(pr.comments[1].database_id, 1001)

  eq(pr.comments[2].author.login, "octocat")
  expect.equality(pr.comments[2].body:match("updated the expiry") ~= nil, true)
  eq(pr.comments[2].database_id, 1002)
end

T["parse_pr_detail()"]["parses reviews correctly"] = function()
  local data = load_fixture("pr_detail.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  -- 1 review
  eq(#pr.reviews, 1)
  eq(pr.reviews[1].author.login, "reviewer")
  eq(pr.reviews[1].state, "APPROVED")
  expect.equality(pr.reviews[1].body:match("LGTM") ~= nil, true)
  eq(pr.reviews[1].database_id, 3001)

  -- Review has 1 inline comment
  eq(#pr.reviews[1].comments, 1)
  eq(pr.reviews[1].comments[1].path, "src/auth.lua")
  eq(pr.reviews[1].comments[1].line, 42)
end

T["parse_pr_detail()"]["builds chronological timeline"] = function()
  local data = load_fixture("pr_detail.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  -- Timeline: 2 comments + 1 review = 3 items
  eq(#pr.timeline, 3)

  -- Should be chronologically sorted
  eq(pr.timeline[1].type, "comment") -- 2026-02-19T14:00:00Z
  eq(pr.timeline[1].comment.author.login, "reviewer")

  eq(pr.timeline[2].type, "comment") -- 2026-02-19T16:00:00Z
  eq(pr.timeline[2].comment.author.login, "octocat")

  eq(pr.timeline[3].type, "review") -- 2026-02-20T10:00:00Z
  eq(pr.timeline[3].review.state, "APPROVED")

  -- Verify timestamps are in order
  for i = 2, #pr.timeline do
    expect.equality(pr.timeline[i].timestamp >= pr.timeline[i - 1].timestamp, true)
  end
end

T["parse_pr_detail()"]["handles empty comments and reviews"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          number = 1,
          title = "Test",
          state = "OPEN",
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
          body = "Test body",
          comments = { nodes = {} },
          reviews = { nodes = {} },
        },
      },
    },
  }
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)
  eq(#pr.comments, 0)
  eq(#pr.reviews, 0)
  eq(#pr.timeline, 0)
end

T["parse_pr_detail()"]["returns error for nil data"] = function()
  local pr, err = graphql.parse_pr_detail(nil)
  eq(pr, nil)
  expect.equality(err ~= nil, true)
end

T["parse_pr_detail()"]["returns error for GraphQL errors"] = function()
  local data = {
    errors = {
      { message = "Could not resolve to a PullRequest" },
    },
  }
  local pr, err = graphql.parse_pr_detail(data)
  eq(pr, nil)
  expect.equality(err:match("GraphQL error") ~= nil, true)
end

T["parse_pr_detail()"]["returns error for missing PR"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = nil,
      },
    },
  }
  local pr, err = graphql.parse_pr_detail(data)
  eq(pr, nil)
  expect.equality(err:match("Pull request not found") ~= nil, true)
end

T["parse_pr_detail()"]["returns error for missing repository"] = function()
  local data = { data = {} }
  local pr, err = graphql.parse_pr_detail(data)
  eq(pr, nil)
  expect.equality(err:match("Repository not found") ~= nil, true)
end

-- =============================================================================
-- PR list with checks
-- =============================================================================

T["parse_pr_list() with checks"] = MiniTest.new_set()

T["parse_pr_list() with checks"]["parses checks summary from fixture"] = function()
  local data = load_fixture("pr_list_with_checks.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)
  eq(#prs, 3)

  -- First PR: all 3 checks pass
  expect.equality(prs[1].checks_summary ~= nil, true)
  eq(prs[1].checks_summary.state, "success")
  eq(prs[1].checks_summary.total, 3)
  eq(prs[1].checks_summary.success, 3)
  eq(prs[1].checks_summary.failure, 0)
  eq(prs[1].checks_summary.pending, 0)
end

T["parse_pr_list() with checks"]["parses failure checks correctly"] = function()
  local data = load_fixture("pr_list_with_checks.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)

  -- Second PR: 2 pass, 1 fail
  expect.equality(prs[2].checks_summary ~= nil, true)
  eq(prs[2].checks_summary.state, "failure")
  eq(prs[2].checks_summary.total, 3)
  eq(prs[2].checks_summary.success, 2)
  eq(prs[2].checks_summary.failure, 1)
end

T["parse_pr_list() with checks"]["parses pending checks correctly"] = function()
  local data = load_fixture("pr_list_with_checks.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)

  -- Third PR: 1 pass, 1 in-progress
  expect.equality(prs[3].checks_summary ~= nil, true)
  eq(prs[3].checks_summary.state, "pending")
  eq(prs[3].checks_summary.total, 2)
  eq(prs[3].checks_summary.success, 1)
  eq(prs[3].checks_summary.pending, 1)
end

T["parse_pr_list() with checks"]["does not include check details in list mode"] = function()
  local data = load_fixture("pr_list_with_checks.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)

  -- List mode should not populate individual checks
  eq(#prs[1].checks_summary.checks, 0)
end

T["parse_pr_list() with checks"]["handles PR without statusCheckRollup"] = function()
  local data = load_fixture("pr_list.json")
  local prs, err = graphql.parse_pr_list(data)
  eq(err, nil)

  -- Original fixture has no commits/checks data
  eq(prs[1].checks_summary, nil)
end

-- =============================================================================
-- PR detail with checks
-- =============================================================================

T["parse_pr_detail() with checks"] = MiniTest.new_set()

T["parse_pr_detail() with checks"]["parses checks with full details from fixture"] = function()
  local data = load_fixture("pr_detail_with_checks.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  expect.equality(pr.checks_summary ~= nil, true)
  eq(pr.checks_summary.total, 4)
  eq(pr.checks_summary.success, 3) -- 2 CheckRun success + 1 StatusContext success
  eq(pr.checks_summary.failure, 1) -- 1 CheckRun failure
end

T["parse_pr_detail() with checks"]["includes check details in detail mode"] = function()
  local data = load_fixture("pr_detail_with_checks.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  local checks = pr.checks_summary.checks
  eq(#checks, 4)

  -- First CheckRun
  eq(checks[1].name, "CI / test")
  eq(checks[1].status, "completed")
  eq(checks[1].conclusion, "success")
  eq(checks[1].app_name, "GitHub Actions")
  expect.equality(checks[1].details_url ~= nil, true)
  expect.equality(checks[1].started_at ~= nil, true)
  expect.equality(checks[1].completed_at ~= nil, true)
end

T["parse_pr_detail() with checks"]["parses StatusContext as check"] = function()
  local data = load_fixture("pr_detail_with_checks.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  -- Fourth item is a StatusContext
  local check = pr.checks_summary.checks[4]
  eq(check.name, "coverage/codecov")
  eq(check.status, "completed")
  eq(check.conclusion, "success")
  expect.equality(check.details_url ~= nil, true)
end

T["parse_pr_detail() with checks"]["handles PR without statusCheckRollup"] = function()
  local data = load_fixture("pr_detail.json")
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)

  -- Original fixture has no commits/checks data
  eq(pr.checks_summary, nil)
end

T["parse_pr_detail() with checks"]["handles empty contexts"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          number = 1,
          title = "Test",
          state = "OPEN",
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
          body = "",
          commits = {
            nodes = {
              {
                commit = {
                  statusCheckRollup = {
                    state = "SUCCESS",
                    contexts = { nodes = {} },
                  },
                },
              },
            },
          },
          comments = { nodes = {} },
          reviews = { nodes = {} },
        },
      },
    },
  }
  local pr, err = graphql.parse_pr_detail(data)
  eq(err, nil)
  expect.equality(pr.checks_summary ~= nil, true)
  eq(pr.checks_summary.total, 0)
  eq(#pr.checks_summary.checks, 0)
end

-- =============================================================================
-- queries.pr_commits
-- =============================================================================

T["queries"]["pr_commits query string is defined"] = function()
  expect.equality(type(graphql.queries.pr_commits), "string")
  expect.equality(graphql.queries.pr_commits:match("pullRequest") ~= nil, true)
  expect.equality(graphql.queries.pr_commits:match("commits") ~= nil, true)
  expect.equality(graphql.queries.pr_commits:match("messageHeadline") ~= nil, true)
end

-- =============================================================================
-- parse_pr_commits
-- =============================================================================

T["parse_pr_commits()"] = MiniTest.new_set()

T["parse_pr_commits()"]["parses commits from a mock response"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          commits = {
            nodes = {
              {
                commit = {
                  oid = "abc1234def5678901234567890abcdef12345678",
                  messageHeadline = "Fix authentication bug",
                  author = { name = "Jane Doe" },
                  authoredDate = "2026-02-19T10:00:00Z",
                  additions = 10,
                  deletions = 3,
                },
              },
              {
                commit = {
                  oid = "def5678abc1234567890abcdef1234567890abcd",
                  messageHeadline = "Add validation",
                  author = { name = "John Smith" },
                  authoredDate = "2026-02-19T11:00:00Z",
                  additions = 15,
                  deletions = 5,
                },
              },
            },
          },
        },
      },
    },
  }

  local commits, err = graphql.parse_pr_commits(data)
  eq(err, nil)
  eq(#commits, 2)

  eq(commits[1].oid, "abc1234def5678901234567890abcdef12345678")
  eq(commits[1].short_oid, "abc1234")
  eq(commits[1].message_headline, "Fix authentication bug")
  eq(commits[1].author_name, "Jane Doe")
  eq(commits[1].author_date, "2026-02-19T10:00:00Z")
  eq(commits[1].additions, 10)
  eq(commits[1].deletions, 3)

  eq(commits[2].oid, "def5678abc1234567890abcdef1234567890abcd")
  eq(commits[2].short_oid, "def5678")
  eq(commits[2].message_headline, "Add validation")
  eq(commits[2].author_name, "John Smith")
  eq(commits[2].additions, 15)
  eq(commits[2].deletions, 5)
end

T["parse_pr_commits()"]["handles empty commits list"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          commits = {
            nodes = {},
          },
        },
      },
    },
  }

  local commits, err = graphql.parse_pr_commits(data)
  eq(err, nil)
  eq(#commits, 0)
end

T["parse_pr_commits()"]["handles missing author"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          commits = {
            nodes = {
              {
                commit = {
                  oid = "abc1234def5678901234567890abcdef12345678",
                  messageHeadline = "Some commit",
                  author = nil,
                  authoredDate = "2026-02-19T10:00:00Z",
                  additions = 5,
                  deletions = 2,
                },
              },
            },
          },
        },
      },
    },
  }

  local commits, err = graphql.parse_pr_commits(data)
  eq(err, nil)
  eq(#commits, 1)
  eq(commits[1].author_name, "Unknown")
end

T["parse_pr_commits()"]["returns error for nil data"] = function()
  local commits, err = graphql.parse_pr_commits(nil)
  eq(commits, nil)
  expect.equality(err ~= nil, true)
end

T["parse_pr_commits()"]["returns error for GraphQL errors"] = function()
  local data = {
    errors = {
      { message = "Could not resolve to a PullRequest" },
    },
  }
  local commits, err = graphql.parse_pr_commits(data)
  eq(commits, nil)
  expect.equality(err:match("GraphQL error") ~= nil, true)
end

T["parse_pr_commits()"]["returns error for missing repository"] = function()
  local data = { data = {} }
  local commits, err = graphql.parse_pr_commits(data)
  eq(commits, nil)
  expect.equality(err:match("Repository not found") ~= nil, true)
end

T["parse_pr_commits()"]["returns error for missing pull request"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = nil,
      },
    },
  }
  local commits, err = graphql.parse_pr_commits(data)
  eq(commits, nil)
  expect.equality(err:match("Pull request not found") ~= nil, true)
end

T["parse_pr_commits()"]["handles missing commits node gracefully"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {},
      },
    },
  }

  local commits, err = graphql.parse_pr_commits(data)
  eq(err, nil)
  eq(#commits, 0)
end

T["parse_pr_commits()"]["handles missing optional fields with defaults"] = function()
  local data = {
    data = {
      repository = {
        pullRequest = {
          commits = {
            nodes = {
              {
                commit = {
                  oid = "abc1234def5678901234567890abcdef12345678",
                },
              },
            },
          },
        },
      },
    },
  }

  local commits, err = graphql.parse_pr_commits(data)
  eq(err, nil)
  eq(#commits, 1)
  eq(commits[1].message_headline, "")
  eq(commits[1].author_name, "Unknown")
  eq(commits[1].author_date, "")
  eq(commits[1].additions, 0)
  eq(commits[1].deletions, 0)
end

-- =============================================================================
-- queries.viewer
-- =============================================================================

T["queries"]["viewer query string is defined"] = function()
  expect.equality(type(graphql.queries.viewer), "string")
  expect.equality(graphql.queries.viewer:match("viewer") ~= nil, true)
  expect.equality(graphql.queries.viewer:match("login") ~= nil, true)
end

-- =============================================================================
-- parse_viewer
-- =============================================================================

T["parse_viewer()"] = MiniTest.new_set()

T["parse_viewer()"]["parses fixture data correctly"] = function()
  local data = load_fixture("viewer.json")
  local login, err = graphql.parse_viewer(data)
  eq(err, nil)
  eq(login, "octocat")
end

T["parse_viewer()"]["returns error for nil data"] = function()
  local login, err = graphql.parse_viewer(nil)
  eq(login, nil)
  expect.equality(err ~= nil, true)
end

T["parse_viewer()"]["returns error for GraphQL errors"] = function()
  local data = {
    errors = {
      { message = "Bad credentials" },
    },
  }
  local login, err = graphql.parse_viewer(data)
  eq(login, nil)
  expect.equality(err:match("GraphQL error") ~= nil, true)
  expect.equality(err:match("Bad credentials") ~= nil, true)
end

T["parse_viewer()"]["returns error for missing viewer"] = function()
  local data = { data = {} }
  local login, err = graphql.parse_viewer(data)
  eq(login, nil)
  expect.equality(err:match("Viewer not found") ~= nil, true)
end

T["parse_viewer()"]["returns error for viewer without login"] = function()
  local data = { data = { viewer = {} } }
  local login, err = graphql.parse_viewer(data)
  eq(login, nil)
  expect.equality(err:match("Viewer not found") ~= nil, true)
end

-- =============================================================================
-- queries.pr_search
-- =============================================================================

T["queries"]["pr_search query string is defined"] = function()
  expect.equality(type(graphql.queries.pr_search), "string")
  expect.equality(graphql.queries.pr_search:match("search") ~= nil, true)
  expect.equality(graphql.queries.pr_search:match("PullRequest") ~= nil, true)
end

-- =============================================================================
-- parse_pr_search
-- =============================================================================

T["parse_pr_search()"] = MiniTest.new_set()

T["parse_pr_search()"]["parses fixture data correctly"] = function()
  local data = load_fixture("pr_search.json")
  local prs, err = graphql.parse_pr_search(data)
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
  eq(prs[1].additions, 10)
  eq(prs[1].deletions, 3)
end

T["parse_pr_search()"]["parses draft PR correctly"] = function()
  local data = load_fixture("pr_search.json")
  local prs, err = graphql.parse_pr_search(data)
  eq(err, nil)
  eq(prs[2].number, 41)
  eq(prs[2].draft, true)
end

T["parse_pr_search()"]["returns error for nil data"] = function()
  local prs, err = graphql.parse_pr_search(nil)
  eq(prs, nil)
  expect.equality(err ~= nil, true)
end

T["parse_pr_search()"]["returns error for GraphQL errors"] = function()
  local data = {
    errors = {
      { message = "Something went wrong" },
    },
  }
  local prs, err = graphql.parse_pr_search(data)
  eq(prs, nil)
  expect.equality(err:match("GraphQL error") ~= nil, true)
end

T["parse_pr_search()"]["returns error for missing search data"] = function()
  local data = { data = {} }
  local prs, err = graphql.parse_pr_search(data)
  eq(prs, nil)
  expect.equality(err:match("No search data") ~= nil, true)
end

T["parse_pr_search()"]["handles empty results"] = function()
  local data = {
    data = {
      search = {
        nodes = {},
      },
    },
  }
  local prs, err = graphql.parse_pr_search(data)
  eq(err, nil)
  eq(#prs, 0)
end

T["parse_pr_search()"]["skips non-PR nodes"] = function()
  local data = {
    data = {
      search = {
        nodes = {
          {
            number = 42,
            title = "A real PR",
            state = "OPEN",
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
          {}, -- Empty node (e.g. an Issue that doesn't match PullRequest fragment)
          { title = "An issue without number" }, -- Another non-PR node
        },
      },
    },
  }
  local prs, err = graphql.parse_pr_search(data)
  eq(err, nil)
  eq(#prs, 1)
  eq(prs[1].number, 42)
end

return T
