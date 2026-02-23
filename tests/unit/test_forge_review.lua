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

-- =============================================================================
-- add_comment
-- =============================================================================

T["add_comment()"] = MiniTest.new_set()

T["add_comment()"]["sends correct REST request"] = function()
  local http = require("gitlad.forge.http")
  local captured_request = nil
  local captured_url = nil

  http._set_executor(function(cmd, opts)
    -- Capture URL (last arg) and body
    captured_url = cmd[#cmd]
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    -- Return 201 Created with mock response
    local response = vim.json.encode({ id = 123, body = "Test comment" })
    opts.on_stdout(nil, vim.split(response .. "\n201", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.add_comment(
    "https://api.github.com",
    "test-token",
    "owner",
    "repo",
    42,
    "Test comment",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Verify URL
  expect.equality(captured_url, "https://api.github.com/repos/owner/repo/issues/42/comments")

  -- Verify body
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  eq(body.body, "Test comment")

  -- Verify result
  eq(got_result.err, nil)
  eq(got_result.result.id, 123)
end

T["add_comment()"]["handles 401 authentication error"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    local response = vim.json.encode({ message = "Bad credentials" })
    opts.on_stdout(nil, vim.split(response .. "\n401", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.add_comment(
    "https://api.github.com",
    "bad-token",
    "owner",
    "repo",
    42,
    "Test",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err:match("Authentication failed") ~= nil, true)
end

T["add_comment()"]["handles HTTP error"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    opts.on_stderr(nil, { "Connection refused", "" })
    opts.on_exit(nil, 7)
    return 1
  end)

  local got_result = nil
  review.add_comment(
    "https://api.github.com",
    "token",
    "owner",
    "repo",
    42,
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

-- =============================================================================
-- edit_comment
-- =============================================================================

T["edit_comment()"] = MiniTest.new_set()

T["edit_comment()"]["sends correct REST PATCH request"] = function()
  local http = require("gitlad.forge.http")
  local captured_url = nil
  local captured_method = nil
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    captured_url = cmd[#cmd]
    for i, v in ipairs(cmd) do
      if v == "-X" then
        captured_method = cmd[i + 1]
      end
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local response = vim.json.encode({ id = 1001, body = "Updated" })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.edit_comment(
    "https://api.github.com",
    "test-token",
    "owner",
    "repo",
    1001,
    "Updated comment",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Verify URL includes comment ID
  expect.equality(captured_url, "https://api.github.com/repos/owner/repo/issues/comments/1001")

  -- Verify PATCH method
  eq(captured_method, "PATCH")

  -- Verify body
  local body = vim.json.decode(captured_request)
  eq(body.body, "Updated comment")

  -- Verify result
  eq(got_result.err, nil)
  eq(got_result.result.id, 1001)
end

T["edit_comment()"]["handles 403 forbidden"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    local response = vim.json.encode({ message = "You can only edit your own comments" })
    opts.on_stdout(nil, vim.split(response .. "\n403", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.edit_comment(
    "https://api.github.com",
    "token",
    "owner",
    "repo",
    1001,
    "Updated",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err:match("Forbidden") ~= nil, true)
end

-- =============================================================================
-- create_review_comment
-- =============================================================================

T["create_review_comment()"] = MiniTest.new_set()

T["create_review_comment()"]["sends correct REST request"] = function()
  local http = require("gitlad.forge.http")
  local captured_url = nil
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    captured_url = cmd[#cmd]
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local response = vim.json.encode({ id = 5001, body = "Review comment" })
    opts.on_stdout(nil, vim.split(response .. "\n201", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.create_review_comment("https://api.github.com", "test-token", "owner", "repo", 42, {
    body = "Nice code!",
    path = "src/main.lua",
    line = 10,
    side = "RIGHT",
    commit_id = "abc123",
  }, function(result, err)
    got_result = { result = result, err = err }
  end)

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Verify URL
  expect.equality(captured_url, "https://api.github.com/repos/owner/repo/pulls/42/comments")

  -- Verify body payload
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  eq(body.body, "Nice code!")
  eq(body.path, "src/main.lua")
  eq(body.line, 10)
  eq(body.side, "RIGHT")
  eq(body.commit_id, "abc123")

  -- Verify result
  eq(got_result.err, nil)
  eq(got_result.result.id, 5001)
end

T["create_review_comment()"]["handles 422 validation error"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    local response = vim.json.encode({ message = "Validation Failed" })
    opts.on_stdout(nil, vim.split(response .. "\n422", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.create_review_comment("https://api.github.com", "token", "owner", "repo", 42, {
    body = "test",
    path = "test.lua",
    line = 1,
    side = "RIGHT",
    commit_id = "abc123",
  }, function(result, err)
    got_result = { result = result, err = err }
  end)

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err:match("Validation failed") ~= nil, true)
end

-- =============================================================================
-- reply_to_review_comment
-- =============================================================================

T["reply_to_review_comment()"] = MiniTest.new_set()

T["reply_to_review_comment()"]["sends correct REST request"] = function()
  local http = require("gitlad.forge.http")
  local captured_url = nil
  local captured_request = nil

  http._set_executor(function(cmd, opts)
    captured_url = cmd[#cmd]
    for i, v in ipairs(cmd) do
      if v == "-d" then
        captured_request = cmd[i + 1]
      end
    end
    local response = vim.json.encode({ id = 6001, body = "Reply text" })
    opts.on_stdout(nil, vim.split(response .. "\n201", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.reply_to_review_comment(
    "https://api.github.com",
    "test-token",
    "owner",
    "repo",
    42,
    1001,
    "Great point!",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Verify URL includes PR and comment ID
  expect.equality(
    captured_url,
    "https://api.github.com/repos/owner/repo/pulls/42/comments/1001/replies"
  )

  -- Verify body
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  eq(body.body, "Great point!")

  -- Verify result
  eq(got_result.err, nil)
  eq(got_result.result.id, 6001)
end

T["reply_to_review_comment()"]["handles 404 not found"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    local response = vim.json.encode({ message = "Not Found" })
    opts.on_stdout(nil, vim.split(response .. "\n404", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  review.reply_to_review_comment(
    "https://api.github.com",
    "token",
    "owner",
    "repo",
    42,
    9999,
    "Reply",
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err:match("Comment not found") ~= nil, true)
end

return T
