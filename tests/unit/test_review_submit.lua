local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      require("gitlad.forge.http")._set_executor(nil)
    end,
  },
})

local review = require("gitlad.forge.github.review")
local graphql = require("gitlad.forge.github.graphql")

-- =============================================================================
-- mutations.add_pull_request_review
-- =============================================================================

T["mutations"] = MiniTest.new_set()

T["mutations"]["add_pull_request_review mutation string is defined"] = function()
  expect.equality(type(graphql.mutations.add_pull_request_review), "string")
  expect.equality(
    graphql.mutations.add_pull_request_review:match("addPullRequestReview") ~= nil,
    true
  )
  expect.equality(
    graphql.mutations.add_pull_request_review:match("PullRequestReviewEvent") ~= nil,
    true
  )
  expect.equality(graphql.mutations.add_pull_request_review:match("pullRequestId") ~= nil, true)
end

-- =============================================================================
-- submit_review
-- =============================================================================

T["submit_review()"] = MiniTest.new_set()

T["submit_review()"]["sends correct GraphQL mutation for APPROVE"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local response = vim.json.encode({
      data = {
        addPullRequestReview = {
          pullRequestReview = {
            id = "PRR_123",
            state = "APPROVED",
          },
        },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.submit_review(
    "https://api.github.com",
    "test-token",
    "PR_node123",
    "APPROVE",
    "Looks great!",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Verify the request body contains correct variables
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  eq(body.variables.pullRequestId, "PR_node123")
  eq(body.variables.event, "APPROVE")
  eq(body.variables.body, "Looks great!")

  -- Verify result
  eq(got_result.err, nil)
  eq(got_result.result.state, "APPROVED")
end

T["submit_review()"]["sends REQUEST_CHANGES event"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local response = vim.json.encode({
      data = {
        addPullRequestReview = {
          pullRequestReview = {
            id = "PRR_456",
            state = "CHANGES_REQUESTED",
          },
        },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.submit_review(
    "https://api.github.com",
    "test-token",
    "PR_node123",
    "REQUEST_CHANGES",
    "Please fix the typo",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  local body = vim.json.decode(captured_request)
  eq(body.variables.event, "REQUEST_CHANGES")

  eq(got_result.err, nil)
  eq(got_result.result.state, "CHANGES_REQUESTED")
end

T["submit_review()"]["handles GraphQL errors"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    local response = vim.json.encode({
      errors = {
        { message = "Pull request is not in a reviewable state" },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.submit_review(
    "https://api.github.com",
    "test-token",
    "PR_node123",
    "APPROVE",
    nil,
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err:match("GraphQL error") ~= nil, true)
  expect.equality(got_result.err:match("reviewable") ~= nil, true)
end

T["submit_review()"]["handles HTTP error"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    opts.on_stderr(nil, { "Connection refused", "" })
    opts.on_exit(nil, 7)
    return 1
  end)

  local got_result = nil
  review.submit_review(
    "https://api.github.com",
    "token",
    "PR_node123",
    "COMMENT",
    "Test",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err ~= nil, true)
end

T["submit_review()"]["handles nil body (approve without message)"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local response = vim.json.encode({
      data = {
        addPullRequestReview = {
          pullRequestReview = {
            id = "PRR_789",
            state = "APPROVED",
          },
        },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.submit_review(
    "https://api.github.com",
    "test-token",
    "PR_node123",
    "APPROVE",
    nil,
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Body should be null in request
  local body = vim.json.decode(captured_request)
  eq(body.variables.body, vim.NIL) -- vim.json.encode(nil) becomes null

  eq(got_result.err, nil)
  eq(got_result.result.state, "APPROVED")
end

return T
