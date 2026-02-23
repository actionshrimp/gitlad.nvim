---@mod gitlad.forge.github GitHub forge provider
---@brief [[
--- GitHub provider implementation for the forge system.
--- Creates ForgeProvider instances that use GraphQL API for data.
---@brief ]]

local M = {}

local pr = require("gitlad.forge.github.pr")
local review = require("gitlad.forge.github.review")

--- Create a new GitHub provider instance
---@param owner string Repository owner
---@param repo string Repository name
---@param api_url string GitHub API URL (e.g. "https://api.github.com")
---@param token string Auth token
---@return ForgeProvider
function M.new(owner, repo, api_url, token)
  ---@type ForgeProvider
  local provider = {
    owner = owner,
    repo = repo,
    host = api_url:match("https?://([^/]+)"),
    provider_type = "github",
  }

  --- List pull requests
  ---@param self ForgeProvider
  ---@param opts ForgeListPRsOpts
  ---@param callback fun(prs: ForgePullRequest[]|nil, err: string|nil)
  function provider:list_prs(opts, callback)
    pr.list(api_url, token, self.owner, self.repo, opts, callback)
  end

  --- Get a single pull request by number (with comments and reviews)
  ---@param self ForgeProvider
  ---@param number number PR number
  ---@param callback fun(pr: ForgePullRequest|nil, err: string|nil)
  function provider:get_pr(number, callback)
    pr.get(api_url, token, self.owner, self.repo, number, callback)
  end

  --- Search pull requests using GitHub search query
  ---@param self ForgeProvider
  ---@param search_query string GitHub search query string
  ---@param limit number Max results to return
  ---@param callback fun(prs: ForgePullRequest[]|nil, err: string|nil)
  function provider:search_prs(search_query, limit, callback)
    pr.search(api_url, token, search_query, limit, callback)
  end

  --- Get the authenticated user's login
  ---@param self ForgeProvider
  ---@param callback fun(login: string|nil, err: string|nil)
  function provider:get_viewer(callback)
    pr.get_viewer(api_url, token, callback)
  end

  --- Add a comment to a PR
  ---@param self ForgeProvider
  ---@param pr_number number PR number
  ---@param body string Comment body
  ---@param callback fun(result: table|nil, err: string|nil)
  function provider:add_comment(pr_number, body, callback)
    review.add_comment(api_url, token, self.owner, self.repo, pr_number, body, callback)
  end

  --- Edit an existing comment
  ---@param self ForgeProvider
  ---@param comment_id number Numeric database ID of the comment
  ---@param body string New comment body
  ---@param callback fun(result: table|nil, err: string|nil)
  function provider:edit_comment(comment_id, body, callback)
    review.edit_comment(api_url, token, self.owner, self.repo, comment_id, body, callback)
  end

  --- Get review threads for a PR
  ---@param self ForgeProvider
  ---@param pr_number number PR number
  ---@param callback fun(threads: ForgeReviewThread[]|nil, pr_node_id: string|nil, err: string|nil)
  function provider:get_review_threads(pr_number, callback)
    pr.get_review_threads(api_url, token, self.owner, self.repo, pr_number, callback)
  end

  --- Create a review comment on a specific line
  ---@param self ForgeProvider
  ---@param pr_number number PR number
  ---@param opts { body: string, path: string, line: number, side: string, commit_id: string }
  ---@param callback fun(comment: table|nil, err: string|nil)
  function provider:create_review_comment(pr_number, opts, callback)
    review.create_review_comment(api_url, token, self.owner, self.repo, pr_number, opts, callback)
  end

  --- Reply to an existing review thread
  ---@param self ForgeProvider
  ---@param pr_number number PR number
  ---@param comment_id number Database ID of the comment to reply to
  ---@param body string Reply body
  ---@param callback fun(comment: table|nil, err: string|nil)
  function provider:reply_to_review_comment(pr_number, comment_id, body, callback)
    review.reply_to_review_comment(
      api_url,
      token,
      self.owner,
      self.repo,
      pr_number,
      comment_id,
      body,
      callback
    )
  end

  --- Submit a pull request review
  ---@param self ForgeProvider
  ---@param pr_node_id string GraphQL node ID of the PR
  ---@param event string "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
  ---@param body string|nil Optional review body
  ---@param callback fun(result: table|nil, err: string|nil)
  function provider:submit_review(pr_node_id, event, body, callback)
    review.submit_review(api_url, token, pr_node_id, event, body, callback)
  end

  --- Submit a review with batch comments
  ---@param self ForgeProvider
  ---@param pr_node_id string GraphQL node ID of the PR
  ---@param event string "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
  ---@param body string|nil Optional review body
  ---@param threads PendingComment[] Pending comments to include
  ---@param callback fun(result: table|nil, err: string|nil)
  function provider:submit_review_with_comments(pr_node_id, event, body, threads, callback)
    review.submit_review_with_comments(api_url, token, pr_node_id, event, body, threads, callback)
  end

  return provider
end

return M
