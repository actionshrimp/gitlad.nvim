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
