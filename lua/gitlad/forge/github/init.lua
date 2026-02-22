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

  return provider
end

return M
