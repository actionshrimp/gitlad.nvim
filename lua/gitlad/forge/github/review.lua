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

return M
