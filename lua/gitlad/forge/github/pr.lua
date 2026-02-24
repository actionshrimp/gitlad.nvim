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

--- Fetch remaining pages of checks and merge them into the PR's checks_summary.
--- Calls itself recursively until all pages are fetched, then invokes the final callback.
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param pr ForgePullRequest The PR being built up
---@param end_cursor string The cursor for the next page
---@param callback fun(pr: ForgePullRequest|nil, err: string|nil)
local function fetch_remaining_checks(api_url, token, owner, repo, number, pr, end_cursor, callback)
  local variables = {
    owner = owner,
    repo = repo,
    number = number,
    after = end_cursor,
  }

  graphql.execute(api_url, token, graphql.queries.pr_checks_page, variables, function(data, err)
    if err then
      -- Non-fatal: return what we have so far
      callback(pr, nil)
      return
    end

    local checks, page_info, parse_err = graphql.parse_checks_page(data)
    if parse_err or not checks then
      -- Non-fatal: return what we have so far
      callback(pr, nil)
      return
    end

    graphql.merge_checks_into_summary(pr.checks_summary, checks)

    if page_info and page_info.has_next_page and page_info.end_cursor then
      fetch_remaining_checks(
        api_url,
        token,
        owner,
        repo,
        number,
        pr,
        page_info.end_cursor,
        callback
      )
    else
      callback(pr, nil)
    end
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

    local pr, parse_err, checks_page_info = graphql.parse_pr_detail(data)
    if parse_err or not pr then
      callback(pr, parse_err)
      return
    end

    -- If there are more pages of checks, fetch them
    if
      checks_page_info
      and checks_page_info.has_next_page
      and checks_page_info.end_cursor
      and pr.checks_summary
    then
      fetch_remaining_checks(
        api_url,
        token,
        owner,
        repo,
        number,
        pr,
        checks_page_info.end_cursor,
        callback
      )
    else
      callback(pr, nil)
    end
  end)
end

--- Search pull requests using GitHub search query
---@param api_url string GitHub API URL
---@param token string Auth token
---@param search_query string GitHub search query string
---@param limit number Max results to return
---@param callback fun(prs: ForgePullRequest[]|nil, err: string|nil)
function M.search(api_url, token, search_query, limit, callback)
  local variables = {
    searchQuery = search_query,
    first = limit,
  }

  graphql.execute(api_url, token, graphql.queries.pr_search, variables, function(data, err)
    if err then
      callback(nil, err)
      return
    end

    local prs, parse_err = graphql.parse_pr_search(data)
    callback(prs, parse_err)
  end)
end

--- Get the authenticated user's login
---@param api_url string GitHub API URL
---@param token string Auth token
---@param callback fun(login: string|nil, err: string|nil)
function M.get_viewer(api_url, token, callback)
  graphql.execute(api_url, token, graphql.queries.viewer, {}, function(data, err)
    if err then
      callback(nil, err)
      return
    end

    local login, parse_err = graphql.parse_viewer(data)
    callback(login, parse_err)
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
