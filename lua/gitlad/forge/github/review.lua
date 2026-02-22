---@mod gitlad.forge.github.review GitHub review and comment operations
---@brief [[
--- REST API operations for PR comments and reviews.
--- Uses REST (not GraphQL) for mutations as GitHub recommends.
---@brief ]]

local M = {}

local http = require("gitlad.forge.http")

--- Add a comment to a PR (issue comment)
--- Uses REST: POST /repos/{owner}/{repo}/issues/{number}/comments
---@param api_url string GitHub API URL (e.g. "https://api.github.com")
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param pr_number number PR number
---@param body string Comment body (markdown)
---@param callback fun(comment: table|nil, err: string|nil)
function M.add_comment(api_url, token, owner, repo, pr_number, body, callback)
  local url = string.format("%s/repos/%s/%s/issues/%d/comments", api_url, owner, repo, pr_number)

  http.request({
    url = url,
    method = "POST",
    headers = {
      Authorization = "Bearer " .. token,
      ["Content-Type"] = "application/json",
      Accept = "application/vnd.github+json",
    },
    body = vim.json.encode({ body = body }),
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

    if response.status == 201 then
      callback(response.json, nil)
    elseif response.status == 401 then
      callback(nil, "Authentication failed. Run `gh auth login` to re-authenticate.")
    elseif response.status == 403 then
      callback(nil, "Access forbidden. Check your token permissions.")
    elseif response.status == 404 then
      callback(nil, "PR not found.")
    else
      local msg = "GitHub API returned HTTP " .. response.status
      if response.json and response.json.message then
        msg = msg .. ": " .. response.json.message
      end
      callback(nil, msg)
    end
  end)
end

--- Edit an existing comment
--- Uses REST: PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param comment_id number Numeric database ID of the comment
---@param body string New comment body (markdown)
---@param callback fun(comment: table|nil, err: string|nil)
function M.edit_comment(api_url, token, owner, repo, comment_id, body, callback)
  local url = string.format("%s/repos/%s/%s/issues/comments/%d", api_url, owner, repo, comment_id)

  http.request({
    url = url,
    method = "PATCH",
    headers = {
      Authorization = "Bearer " .. token,
      ["Content-Type"] = "application/json",
      Accept = "application/vnd.github+json",
    },
    body = vim.json.encode({ body = body }),
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

    if response.status == 200 then
      callback(response.json, nil)
    elseif response.status == 401 then
      callback(nil, "Authentication failed. Run `gh auth login` to re-authenticate.")
    elseif response.status == 403 then
      callback(nil, "Forbidden. You can only edit your own comments.")
    elseif response.status == 404 then
      callback(nil, "Comment not found.")
    else
      local msg = "GitHub API returned HTTP " .. response.status
      if response.json and response.json.message then
        msg = msg .. ": " .. response.json.message
      end
      callback(nil, msg)
    end
  end)
end

--- Create a review comment on a specific line of a PR
--- Uses REST: POST /repos/{owner}/{repo}/pulls/{pr_number}/comments
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param pr_number number PR number
---@param opts { body: string, path: string, line: number, side: string, commit_id: string } Comment details
---@param callback fun(comment: table|nil, err: string|nil)
function M.create_review_comment(api_url, token, owner, repo, pr_number, opts, callback)
  local url = string.format("%s/repos/%s/%s/pulls/%d/comments", api_url, owner, repo, pr_number)

  local payload = {
    body = opts.body,
    path = opts.path,
    line = opts.line,
    side = opts.side or "RIGHT",
    commit_id = opts.commit_id,
  }

  http.request({
    url = url,
    method = "POST",
    headers = {
      Authorization = "Bearer " .. token,
      ["Content-Type"] = "application/json",
      Accept = "application/vnd.github+json",
    },
    body = vim.json.encode(payload),
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

    if response.status == 201 then
      callback(response.json, nil)
    elseif response.status == 401 then
      callback(nil, "Authentication failed. Run `gh auth login` to re-authenticate.")
    elseif response.status == 403 then
      callback(nil, "Access forbidden. Check your token permissions.")
    elseif response.status == 404 then
      callback(nil, "PR not found.")
    elseif response.status == 422 then
      local msg = "Validation failed"
      if response.json and response.json.message then
        msg = msg .. ": " .. response.json.message
      end
      callback(nil, msg)
    else
      local msg = "GitHub API returned HTTP " .. response.status
      if response.json and response.json.message then
        msg = msg .. ": " .. response.json.message
      end
      callback(nil, msg)
    end
  end)
end

--- Reply to an existing review thread
--- Uses REST: POST /repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies
---@param api_url string GitHub API URL
---@param token string Auth token
---@param owner string Repository owner
---@param repo string Repository name
---@param pr_number number PR number
---@param comment_id number Database ID of the comment to reply to
---@param body string Reply body (markdown)
---@param callback fun(comment: table|nil, err: string|nil)
function M.reply_to_review_comment(
  api_url,
  token,
  owner,
  repo,
  pr_number,
  comment_id,
  body,
  callback
)
  local url = string.format(
    "%s/repos/%s/%s/pulls/%d/comments/%d/replies",
    api_url,
    owner,
    repo,
    pr_number,
    comment_id
  )

  http.request({
    url = url,
    method = "POST",
    headers = {
      Authorization = "Bearer " .. token,
      ["Content-Type"] = "application/json",
      Accept = "application/vnd.github+json",
    },
    body = vim.json.encode({ body = body }),
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

    if response.status == 201 then
      callback(response.json, nil)
    elseif response.status == 401 then
      callback(nil, "Authentication failed. Run `gh auth login` to re-authenticate.")
    elseif response.status == 403 then
      callback(nil, "Access forbidden. Check your token permissions.")
    elseif response.status == 404 then
      callback(nil, "Comment not found.")
    else
      local msg = "GitHub API returned HTTP " .. response.status
      if response.json and response.json.message then
        msg = msg .. ": " .. response.json.message
      end
      callback(nil, msg)
    end
  end)
end

--- Submit a pull request review (approve, request changes, or comment)
--- Uses GraphQL: addPullRequestReview mutation
---@param api_url string GitHub API URL
---@param token string Auth token
---@param pr_node_id string GraphQL node ID of the pull request
---@param event string "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
---@param body string|nil Optional review body
---@param callback fun(result: table|nil, err: string|nil)
function M.submit_review(api_url, token, pr_node_id, event, body, callback)
  local graphql = require("gitlad.forge.github.graphql")

  local variables = {
    pullRequestId = pr_node_id,
    event = event,
    body = body,
  }

  graphql.execute(
    api_url,
    token,
    graphql.mutations.add_pull_request_review,
    variables,
    function(data, err)
      if err then
        callback(nil, err)
        return
      end

      if not data then
        callback(nil, "No data in response")
        return
      end

      -- Check for GraphQL errors
      if data.errors and #data.errors > 0 then
        local msgs = {}
        for _, e in ipairs(data.errors) do
          table.insert(msgs, e.message or "Unknown error")
        end
        callback(nil, "GraphQL error: " .. table.concat(msgs, "; "))
        return
      end

      local review_data = data.data
        and data.data.addPullRequestReview
        and data.data.addPullRequestReview.pullRequestReview
      callback(review_data, nil)
    end
  )
end

--- Submit a review with batch comments (threads)
--- Uses GraphQL: addPullRequestReview mutation with threads argument
---@param api_url string GitHub API URL
---@param token string Auth token
---@param pr_node_id string GraphQL node ID of the pull request
---@param event string "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
---@param body string|nil Optional review body
---@param threads PendingComment[] List of pending comments to submit as threads
---@param callback fun(result: table|nil, err: string|nil)
function M.submit_review_with_comments(api_url, token, pr_node_id, event, body, threads, callback)
  local graphql = require("gitlad.forge.github.graphql")

  -- Convert PendingComment[] to DraftPullRequestReviewThread[] for GraphQL
  local draft_threads = {}
  for _, pc in ipairs(threads) do
    table.insert(draft_threads, {
      path = pc.path,
      line = pc.line,
      side = pc.side,
      body = pc.body,
    })
  end

  local variables = {
    pullRequestId = pr_node_id,
    event = event,
    body = body,
    threads = draft_threads,
  }

  graphql.execute(
    api_url,
    token,
    graphql.mutations.add_pull_request_review_with_threads,
    variables,
    function(data, err)
      if err then
        callback(nil, err)
        return
      end

      if not data then
        callback(nil, "No data in response")
        return
      end

      if data.errors and #data.errors > 0 then
        local msgs = {}
        for _, e in ipairs(data.errors) do
          table.insert(msgs, e.message or "Unknown error")
        end
        callback(nil, "GraphQL error: " .. table.concat(msgs, "; "))
        return
      end

      local review_data = data.data
        and data.data.addPullRequestReview
        and data.data.addPullRequestReview.pullRequestReview
      callback(review_data, nil)
    end
  )
end

return M
