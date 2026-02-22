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

-- =============================================================================
-- Response Parsers
-- =============================================================================

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
  }

  return pr, nil
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
