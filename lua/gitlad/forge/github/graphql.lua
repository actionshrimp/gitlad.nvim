---@mod gitlad.forge.github.graphql GitHub GraphQL queries and parsers
---@brief [[
--- GraphQL query strings for GitHub API and pure functions
--- to transform GraphQL responses into forge types.
---@brief ]]

local M = {}

-- =============================================================================
-- Query Strings
-- =============================================================================

M.queries = {}

M.queries.pr_list = [[
query($owner: String!, $repo: String!, $states: [PullRequestState!], $first: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequests(states: $states, first: $first, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        title
        state
        isDraft
        author {
          login
          avatarUrl
        }
        headRefName
        baseRefName
        reviewDecision
        labels(first: 10) {
          nodes {
            name
          }
        }
        additions
        deletions
        createdAt
        updatedAt
        url
        body
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup {
                state
                contexts(first: 100) {
                  nodes {
                    __typename
                    ... on CheckRun {
                      conclusion
                      status
                    }
                    ... on StatusContext {
                      cState: state
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
]]

M.queries.pr_detail = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      title
      state
      isDraft
      author {
        login
        avatarUrl
      }
      headRefName
      baseRefName
      reviewDecision
      labels(first: 10) {
        nodes {
          name
        }
      }
      additions
      deletions
      createdAt
      updatedAt
      url
      body
      commits(last: 1) {
        nodes {
          commit {
            statusCheckRollup {
              state
              contexts(first: 100) {
                nodes {
                  __typename
                  ... on CheckRun {
                    name
                    conclusion
                    status
                    detailsUrl
                    startedAt
                    completedAt
                    checkSuite {
                      app {
                        name
                      }
                    }
                  }
                  ... on StatusContext {
                    context
                    cState: state
                    targetUrl
                    createdAt
                  }
                }
              }
            }
          }
        }
      }
      comments(first: 100) {
        nodes {
          id
          databaseId
          author {
            login
          }
          body
          createdAt
          updatedAt
        }
      }
      reviews(first: 50) {
        nodes {
          id
          databaseId
          author {
            login
          }
          state
          body
          submittedAt
          comments(first: 50) {
            nodes {
              id
              databaseId
              author {
                login
              }
              body
              path
              line
              createdAt
            }
          }
        }
      }
    }
  }
}
]]

M.mutations = {}

M.mutations.add_pull_request_review = [[
mutation($pullRequestId: ID!, $event: PullRequestReviewEvent!, $body: String) {
  addPullRequestReview(input: {pullRequestId: $pullRequestId, event: $event, body: $body}) {
    pullRequestReview {
      id
      state
    }
  }
}
]]

M.mutations.add_pull_request_review_with_threads = [[
mutation($pullRequestId: ID!, $event: PullRequestReviewEvent!, $body: String, $threads: [DraftPullRequestReviewThread!]) {
  addPullRequestReview(input: {pullRequestId: $pullRequestId, event: $event, body: $body, threads: $threads}) {
    pullRequestReview {
      id
      state
    }
  }
}
]]

M.queries.pr_review_threads = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      id
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          line
          originalLine
          startLine
          path
          diffSide
          comments(first: 50) {
            nodes {
              id
              databaseId
              author {
                login
              }
              body
              createdAt
              updatedAt
            }
          }
        }
      }
    }
  }
}
]]

M.queries.pr_commits = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      commits(first: 250) {
        nodes {
          commit {
            oid
            messageHeadline
            author {
              name
            }
            authoredDate
            additions
            deletions
          }
        }
      }
    }
  }
}
]]

-- =============================================================================
-- Response Parsers
-- =============================================================================

--- Parse statusCheckRollup commit node into a ForgeChecksSummary
--- Works for both pr_list (compact) and pr_detail (full details) responses.
---@param commits_node table The `commits` field from the PR node
---@param include_details boolean Whether to include full check details (name, urls, timestamps)
---@return ForgeChecksSummary|nil
local function parse_checks_summary(commits_node, include_details)
  if not commits_node or not commits_node.nodes or #commits_node.nodes == 0 then
    return nil
  end

  local commit_node = commits_node.nodes[1]
  if not commit_node or not commit_node.commit then
    return nil
  end

  local rollup = commit_node.commit.statusCheckRollup
  if not rollup then
    return nil
  end

  local state_map = {
    SUCCESS = "success",
    FAILURE = "failure",
    ERROR = "failure",
    EXPECTED = "pending",
    PENDING = "pending",
  }
  local rollup_state = state_map[rollup.state] or "pending"

  local checks = {}
  local success_count = 0
  local failure_count = 0
  local pending_count = 0

  local contexts = rollup.contexts and rollup.contexts.nodes or {}
  for _, ctx in ipairs(contexts) do
    if ctx.__typename == "CheckRun" then
      local status = (ctx.status or ""):upper()
      local raw_conclusion = ctx.conclusion
      -- vim.NIL comes from JSON null; treat as nil
      if raw_conclusion == vim.NIL then
        raw_conclusion = nil
      end
      local conclusion = raw_conclusion and raw_conclusion:lower() or nil

      if status ~= "COMPLETED" then
        pending_count = pending_count + 1
      elseif conclusion == "success" then
        success_count = success_count + 1
      elseif
        conclusion == "failure"
        or conclusion == "timed_out"
        or conclusion == "startup_failure"
      then
        failure_count = failure_count + 1
      elseif conclusion == "cancelled" or conclusion == "skipped" or conclusion == "neutral" then
        success_count = success_count + 1 -- count neutral/skipped as non-failures
      else
        pending_count = pending_count + 1
      end

      if include_details then
        ---@type ForgeCheck
        local check = {
          name = ctx.name or "unknown",
          status = status == "COMPLETED" and "completed" or "in_progress",
          conclusion = conclusion,
          details_url = ctx.detailsUrl ~= vim.NIL and ctx.detailsUrl or nil,
          app_name = ctx.checkSuite and ctx.checkSuite.app and ctx.checkSuite.app.name or nil,
          started_at = ctx.startedAt ~= vim.NIL and ctx.startedAt or nil,
          completed_at = ctx.completedAt ~= vim.NIL and ctx.completedAt or nil,
        }
        table.insert(checks, check)
      end
    elseif ctx.__typename == "StatusContext" then
      local state = (ctx.cState or ""):upper()

      if state == "SUCCESS" then
        success_count = success_count + 1
      elseif state == "FAILURE" or state == "ERROR" then
        failure_count = failure_count + 1
      else
        pending_count = pending_count + 1
      end

      if include_details then
        ---@type ForgeCheck
        local check = {
          name = ctx.context or "unknown",
          status = (state == "SUCCESS" or state == "FAILURE" or state == "ERROR") and "completed"
            or "in_progress",
          conclusion = state == "SUCCESS" and "success"
            or (state == "FAILURE" or state == "ERROR") and "failure"
            or nil,
          details_url = ctx.targetUrl ~= vim.NIL and ctx.targetUrl or nil,
          app_name = nil,
          started_at = ctx.createdAt ~= vim.NIL and ctx.createdAt or nil,
          completed_at = nil,
        }
        table.insert(checks, check)
      end
    end
  end

  local total = success_count + failure_count + pending_count

  ---@type ForgeChecksSummary
  return {
    state = rollup_state,
    total = total,
    success = success_count,
    failure = failure_count,
    pending = pending_count,
    checks = checks,
  }
end

--- Parse a PR list GraphQL response into ForgePullRequest[]
---@param data table Decoded JSON response from GraphQL API
---@return ForgePullRequest[]|nil prs List of PRs
---@return string|nil err Error message
function M.parse_pr_list(data)
  if not data then
    return nil, "No data in response"
  end

  -- Check for GraphQL errors
  if data.errors and #data.errors > 0 then
    local msgs = {}
    for _, err in ipairs(data.errors) do
      table.insert(msgs, err.message or "Unknown error")
    end
    return nil, "GraphQL error: " .. table.concat(msgs, "; ")
  end

  -- Navigate to the PR nodes
  local repo = data.data and data.data.repository
  if not repo then
    return nil, "Repository not found"
  end

  local pr_data = repo.pullRequests
  if not pr_data or not pr_data.nodes then
    return nil, "No pull request data"
  end

  local prs = {}
  for _, node in ipairs(pr_data.nodes) do
    local labels = {}
    if node.labels and node.labels.nodes then
      for _, label in ipairs(node.labels.nodes) do
        table.insert(labels, label.name)
      end
    end

    ---@type ForgePullRequest
    local pr = {
      number = node.number,
      title = node.title,
      state = (node.state or ""):lower(),
      draft = node.isDraft or false,
      author = {
        login = (node.author and node.author.login) or "ghost",
        avatar_url = node.author and node.author.avatarUrl,
      },
      head_ref = node.headRefName or "",
      base_ref = node.baseRefName or "",
      review_decision = node.reviewDecision, -- can be nil
      labels = labels,
      additions = node.additions or 0,
      deletions = node.deletions or 0,
      created_at = node.createdAt or "",
      updated_at = node.updatedAt or "",
      url = node.url or "",
      body = node.body,
      checks_summary = parse_checks_summary(node.commits, false),
    }
    table.insert(prs, pr)
  end

  return prs, nil
end

--- Parse a PR detail GraphQL response into a ForgePullRequest with comments and reviews
---@param data table Decoded JSON response from GraphQL API
---@return ForgePullRequest|nil pr PR with comments, reviews, and timeline
---@return string|nil err Error message
function M.parse_pr_detail(data)
  if not data then
    return nil, "No data in response"
  end

  -- Check for GraphQL errors
  if data.errors and #data.errors > 0 then
    local msgs = {}
    for _, err in ipairs(data.errors) do
      table.insert(msgs, err.message or "Unknown error")
    end
    return nil, "GraphQL error: " .. table.concat(msgs, "; ")
  end

  -- Navigate to the PR node
  local repo = data.data and data.data.repository
  if not repo then
    return nil, "Repository not found"
  end

  local node = repo.pullRequest
  if not node then
    return nil, "Pull request not found"
  end

  -- Parse labels
  local labels = {}
  if node.labels and node.labels.nodes then
    for _, label in ipairs(node.labels.nodes) do
      table.insert(labels, label.name)
    end
  end

  -- Parse comments
  local comments = {}
  if node.comments and node.comments.nodes then
    for _, c in ipairs(node.comments.nodes) do
      ---@type ForgeComment
      local comment = {
        id = c.id or "",
        database_id = c.databaseId,
        author = {
          login = (c.author and c.author.login) or "ghost",
        },
        body = c.body or "",
        created_at = c.createdAt or "",
        updated_at = c.updatedAt or "",
      }
      table.insert(comments, comment)
    end
  end

  -- Parse reviews
  local reviews = {}
  if node.reviews and node.reviews.nodes then
    for _, r in ipairs(node.reviews.nodes) do
      local review_comments = {}
      if r.comments and r.comments.nodes then
        for _, rc in ipairs(r.comments.nodes) do
          ---@type ForgeReviewComment
          local review_comment = {
            id = rc.id or "",
            database_id = rc.databaseId,
            author = {
              login = (rc.author and rc.author.login) or "ghost",
            },
            body = rc.body or "",
            path = rc.path or "",
            line = rc.line,
            created_at = rc.createdAt or "",
          }
          table.insert(review_comments, review_comment)
        end
      end

      ---@type ForgeReview
      local review = {
        id = r.id or "",
        database_id = r.databaseId,
        author = {
          login = (r.author and r.author.login) or "ghost",
        },
        state = r.state or "COMMENTED",
        body = r.body,
        submitted_at = r.submittedAt or "",
        comments = review_comments,
      }
      table.insert(reviews, review)
    end
  end

  -- Build timeline (interleaved comments and reviews, sorted chronologically)
  local timeline = {}
  for _, comment in ipairs(comments) do
    ---@type ForgeTimelineItem
    local item = {
      type = "comment",
      comment = comment,
      timestamp = comment.created_at,
    }
    table.insert(timeline, item)
  end
  for _, review in ipairs(reviews) do
    ---@type ForgeTimelineItem
    local item = {
      type = "review",
      review = review,
      timestamp = review.submitted_at,
    }
    table.insert(timeline, item)
  end

  -- Sort timeline chronologically
  table.sort(timeline, function(a, b)
    return a.timestamp < b.timestamp
  end)

  ---@type ForgePullRequest
  local pr = {
    number = node.number,
    title = node.title,
    state = (node.state or ""):lower(),
    draft = node.isDraft or false,
    author = {
      login = (node.author and node.author.login) or "ghost",
      avatar_url = node.author and node.author.avatarUrl,
    },
    head_ref = node.headRefName or "",
    base_ref = node.baseRefName or "",
    review_decision = node.reviewDecision, -- can be nil
    labels = labels,
    additions = node.additions or 0,
    deletions = node.deletions or 0,
    created_at = node.createdAt or "",
    updated_at = node.updatedAt or "",
    url = node.url or "",
    body = node.body,
    comments = comments,
    reviews = reviews,
    timeline = timeline,
    checks_summary = parse_checks_summary(node.commits, true),
  }

  return pr, nil
end

--- Parse a PR commits GraphQL response into DiffPRCommit[]
---@param data table Decoded JSON response from GraphQL API
---@return DiffPRCommit[]|nil commits List of commits
---@return string|nil err Error message
function M.parse_pr_commits(data)
  if not data then
    return nil, "No data in response"
  end

  -- Check for GraphQL errors
  if data.errors and #data.errors > 0 then
    local msgs = {}
    for _, err in ipairs(data.errors) do
      table.insert(msgs, err.message or "Unknown error")
    end
    return nil, "GraphQL error: " .. table.concat(msgs, "; ")
  end

  -- Navigate to the PR node
  local repo = data.data and data.data.repository
  if not repo then
    return nil, "Repository not found"
  end

  local pr = repo.pullRequest
  if not pr then
    return nil, "Pull request not found"
  end

  local commits = {}
  local commit_nodes = pr.commits and pr.commits.nodes or {}
  for _, node in ipairs(commit_nodes) do
    local c = node.commit
    if c then
      table.insert(commits, {
        oid = c.oid or "",
        short_oid = (c.oid or ""):sub(1, 7),
        message_headline = c.messageHeadline or "",
        author_name = (c.author and c.author.name) or "Unknown",
        author_date = c.authoredDate or "",
        additions = c.additions or 0,
        deletions = c.deletions or 0,
      })
    end
  end

  return commits, nil
end

--- Parse a PR review threads GraphQL response into ForgeReviewThread[]
---@param data table Decoded JSON response from GraphQL API
---@return ForgeReviewThread[]|nil threads List of review threads
---@return string|nil pr_node_id PR GraphQL node ID (for mutations)
---@return string|nil err Error message
function M.parse_review_threads(data)
  if not data then
    return nil, nil, "No data in response"
  end

  -- Check for GraphQL errors
  if data.errors and #data.errors > 0 then
    local msgs = {}
    for _, err in ipairs(data.errors) do
      table.insert(msgs, err.message or "Unknown error")
    end
    return nil, nil, "GraphQL error: " .. table.concat(msgs, "; ")
  end

  -- Navigate to the PR node
  local repo = data.data and data.data.repository
  if not repo then
    return nil, nil, "Repository not found"
  end

  local pr_node = repo.pullRequest
  if not pr_node then
    return nil, nil, "Pull request not found"
  end

  local pr_node_id = pr_node.id

  local threads = {}
  local thread_nodes = pr_node.reviewThreads and pr_node.reviewThreads.nodes or {}

  for _, node in ipairs(thread_nodes) do
    local comments = {}
    local comment_nodes = node.comments and node.comments.nodes or {}

    for _, c in ipairs(comment_nodes) do
      ---@type ForgeThreadComment
      local comment = {
        id = c.id or "",
        database_id = c.databaseId,
        author = {
          login = (c.author and c.author.login) or "ghost",
        },
        body = c.body or "",
        created_at = c.createdAt or "",
        updated_at = c.updatedAt or "",
      }
      table.insert(comments, comment)
    end

    -- Normalize vim.NIL to nil
    local line = node.line
    if line == vim.NIL then
      line = nil
    end
    local original_line = node.originalLine
    if original_line == vim.NIL then
      original_line = nil
    end
    local start_line = node.startLine
    if start_line == vim.NIL then
      start_line = nil
    end

    ---@type ForgeReviewThread
    local thread = {
      id = node.id or "",
      is_resolved = node.isResolved or false,
      is_outdated = node.isOutdated or false,
      path = node.path or "",
      line = line,
      original_line = original_line,
      start_line = start_line,
      diff_side = node.diffSide or "RIGHT",
      comments = comments,
    }
    table.insert(threads, thread)
  end

  return threads, pr_node_id, nil
end

--- Execute a GraphQL query against GitHub API
---@param api_url string GitHub API URL (e.g. "https://api.github.com")
---@param token string Auth token
---@param query string GraphQL query string
---@param variables table Query variables
---@param callback fun(data: table|nil, err: string|nil)
function M.execute(api_url, token, query, variables, callback)
  local http = require("gitlad.forge.http")

  local body = vim.json.encode({
    query = query,
    variables = variables,
  })

  http.request({
    url = api_url .. "/graphql",
    method = "POST",
    headers = {
      Authorization = "Bearer " .. token,
      ["Content-Type"] = "application/json",
      Accept = "application/json",
    },
    body = body,
    timeout = 30,
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    if not response then
      callback(nil, "No response received")
      return
    end

    if response.status == 401 then
      callback(nil, "Authentication failed. Run `gh auth login` to re-authenticate.")
      return
    end

    if response.status == 403 then
      callback(nil, "Access forbidden. Check your token permissions.")
      return
    end

    if response.status ~= 200 then
      callback(nil, "GitHub API returned HTTP " .. response.status)
      return
    end

    if not response.json then
      callback(nil, "Failed to parse JSON response")
      return
    end

    callback(response.json, nil)
  end)
end

return M
