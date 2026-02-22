---@mod gitlad.forge.github.pr GitHub PR operations
---@brief [[
--- PR-specific operations for the GitHub provider.
--- Orchestrates GraphQL queries and response parsing.
---@brief ]]

local M = {}

local graphql = require("gitlad.forge.github.graphql")

--- Map ForgeListPRsOpts state to GitHub GraphQL PullRequestState
---@param state string|nil "open"|"closed"|"merged"|"all"
---@return string[] GitHub PR states
local function map_state(state)
  if state == "all" then
    return { "OPEN", "CLOSED", "MERGED" }
  elseif state == "closed" then
    return { "CLOSED" }
  elseif state == "merged" then
    return { "MERGED" }
  else
    -- Default to open
    return { "OPEN" }
  end
end

--- List pull requests for a repository
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param opts ForgeListPRsOpts Options
---@param callback fun(prs: ForgePullRequest[]|nil, err: string|nil)
function M.list(api_url, token, owner, repo, opts, callback)
  opts = opts or {}

  local variables = {
    owner = owner,
    repo = repo,
    states = map_state(opts.state),
    first = opts.limit or 30,
  }

  graphql.execute(api_url, token, graphql.queries.pr_list, variables, function(data, err)
    if err then
      callback(nil, err)
      return
    end

    local prs, parse_err = graphql.parse_pr_list(data)
    callback(prs, parse_err)
  end)
end

--- Get a single pull request by number (with comments and reviews)
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param callback fun(pr: ForgePullRequest|nil, err: string|nil)
function M.get(api_url, token, owner, repo, number, callback)
  local variables = {
    owner = owner,
    repo = repo,
    number = number,
  }

  graphql.execute(api_url, token, graphql.queries.pr_detail, variables, function(data, err)
    if err then
      callback(nil, err)
      return
    end

    local pr, parse_err = graphql.parse_pr_detail(data)
    callback(pr, parse_err)
  end)
end

--- Get review threads for a pull request
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param callback fun(threads: ForgeReviewThread[]|nil, pr_node_id: string|nil, err: string|nil)
function M.get_review_threads(api_url, token, owner, repo, number, callback)
  local variables = {
    owner = owner,
    repo = repo,
    number = number,
  }

  graphql.execute(api_url, token, graphql.queries.pr_review_threads, variables, function(data, err)
    if err then
      callback(nil, nil, err)
      return
    end

    local threads, pr_node_id, parse_err = graphql.parse_review_threads(data)
    callback(threads, pr_node_id, parse_err)
  end)
end

return M
