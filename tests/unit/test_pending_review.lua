local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      require("gitlad.forge.http")._set_executor(nil)
    end,
  },
})

local review_mod = require("gitlad.ui.views.diff.review")
local gh_review = require("gitlad.forge.github.review")
local graphql = require("gitlad.forge.github.graphql")

-- =============================================================================
-- Helpers
-- =============================================================================

--- Create a mock ForgeReviewThread
---@param overrides? table
---@return ForgeReviewThread
local function make_thread(overrides)
  overrides = overrides or {}
  return vim.tbl_extend("force", {
    id = "PRRT_1",
    is_resolved = false,
    is_outdated = false,
    path = "src/main.lua",
    line = 10,
    original_line = 10,
    start_line = nil,
    diff_side = "RIGHT",
    comments = {
      {
        id = "C1",
        database_id = 100,
        author = { login = "reviewer" },
        body = "Looks good",
        created_at = "2026-02-20T10:00:00Z",
        updated_at = "2026-02-20T10:00:00Z",
      },
    },
  }, overrides)
end

--- Create a simple line_map for testing
---@param entries table[] List of {left_lineno, right_lineno}
---@return AlignedLineInfo[]
local function make_line_map(entries)
  local map = {}
  for _, e in ipairs(entries) do
    table.insert(map, {
      left_lineno = e[1],
      right_lineno = e[2],
      left_type = e[3] or "context",
      right_type = e[4] or "context",
      hunk_index = 1,
      is_hunk_boundary = false,
    })
  end
  return map
end

-- =============================================================================
-- ReviewState pending fields
-- =============================================================================

T["new_state()"] = MiniTest.new_set()

T["new_state()"]["initializes pending mode as false"] = function()
  local state = review_mod.new_state()
  eq(state.pending_mode, false)
end

T["new_state()"]["initializes pending_comments as empty list"] = function()
  local state = review_mod.new_state()
  eq(#state.pending_comments, 0)
end

-- =============================================================================
-- Pending comment accumulation
-- =============================================================================

T["pending_comments"] = MiniTest.new_set()

T["pending_comments"]["can add pending comments to state"] = function()
  local state = review_mod.new_state()
  state.pending_mode = true

  table.insert(state.pending_comments, {
    path = "src/main.lua",
    line = 10,
    side = "RIGHT",
    body = "Should we add rate limiting?",
  })

  eq(#state.pending_comments, 1)
  eq(state.pending_comments[1].path, "src/main.lua")
  eq(state.pending_comments[1].line, 10)
  eq(state.pending_comments[1].side, "RIGHT")
  eq(state.pending_comments[1].body, "Should we add rate limiting?")
end

T["pending_comments"]["can accumulate multiple pending comments"] = function()
  local state = review_mod.new_state()
  state.pending_mode = true

  table.insert(state.pending_comments, {
    path = "src/main.lua",
    line = 10,
    side = "RIGHT",
    body = "Comment 1",
  })
  table.insert(state.pending_comments, {
    path = "src/utils.lua",
    line = 5,
    side = "LEFT",
    body = "Comment 2",
  })
  table.insert(state.pending_comments, {
    path = "src/main.lua",
    line = 20,
    side = "RIGHT",
    body = "Comment 3",
  })

  eq(#state.pending_comments, 3)
end

T["pending_comments"]["clearing pending comments after submit"] = function()
  local state = review_mod.new_state()
  state.pending_mode = true

  table.insert(state.pending_comments, {
    path = "src/main.lua",
    line = 10,
    side = "RIGHT",
    body = "Pending comment",
  })

  eq(#state.pending_comments, 1)

  -- Simulate submit clearing
  state.pending_comments = {}
  state.pending_mode = false

  eq(#state.pending_comments, 0)
  eq(state.pending_mode, false)
end

-- =============================================================================
-- mutations.add_pull_request_review_with_threads
-- =============================================================================

T["mutations"] = MiniTest.new_set()

T["mutations"]["add_pull_request_review_with_threads mutation is defined"] = function()
  expect.equality(type(graphql.mutations.add_pull_request_review_with_threads), "string")
  expect.equality(
    graphql.mutations.add_pull_request_review_with_threads:match("addPullRequestReview") ~= nil,
    true
  )
  expect.equality(
    graphql.mutations.add_pull_request_review_with_threads:match("threads") ~= nil,
    true
  )
  expect.equality(
    graphql.mutations.add_pull_request_review_with_threads:match("DraftPullRequestReviewThread")
      ~= nil,
    true
  )
end

-- =============================================================================
-- submit_review_with_comments API
-- =============================================================================

T["submit_review_with_comments()"] = MiniTest.new_set()

T["submit_review_with_comments()"]["sends threads in GraphQL mutation"] = function()
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
            id = "PRR_batch",
            state = "COMMENTED",
          },
        },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local pending = {
    { path = "src/main.lua", line = 10, side = "RIGHT", body = "Fix this" },
    { path = "src/utils.lua", line = 5, side = "LEFT", body = "Why not use X?" },
  }

  local got_result = nil
  gh_review.submit_review_with_comments(
    "https://api.github.com",
    "test-token",
    "PR_node123",
    "COMMENT",
    "Overall review",
    pending,
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  -- Verify request body
  expect.equality(captured_request ~= nil, true)
  local body = vim.json.decode(captured_request)
  eq(body.variables.pullRequestId, "PR_node123")
  eq(body.variables.event, "COMMENT")
  eq(body.variables.body, "Overall review")

  -- Verify threads were included
  eq(#body.variables.threads, 2)
  eq(body.variables.threads[1].path, "src/main.lua")
  eq(body.variables.threads[1].line, 10)
  eq(body.variables.threads[1].side, "RIGHT")
  eq(body.variables.threads[1].body, "Fix this")
  eq(body.variables.threads[2].path, "src/utils.lua")
  eq(body.variables.threads[2].line, 5)
  eq(body.variables.threads[2].side, "LEFT")
  eq(body.variables.threads[2].body, "Why not use X?")

  -- Verify success
  eq(got_result.err, nil)
  eq(got_result.result.state, "COMMENTED")
end

T["submit_review_with_comments()"]["handles APPROVE with batch comments"] = function()
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
            id = "PRR_approve_batch",
            state = "APPROVED",
          },
        },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local pending = {
    { path = "src/main.lua", line = 15, side = "RIGHT", body = "Nice pattern" },
  }

  local got_result = nil
  gh_review.submit_review_with_comments(
    "https://api.github.com",
    "test-token",
    "PR_node456",
    "APPROVE",
    nil,
    pending,
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  local body = vim.json.decode(captured_request)
  eq(body.variables.event, "APPROVE")
  eq(#body.variables.threads, 1)

  eq(got_result.err, nil)
  eq(got_result.result.state, "APPROVED")
end

T["submit_review_with_comments()"]["handles GraphQL errors"] = function()
  local http = require("gitlad.forge.http")

  http._set_executor(function(cmd, opts)
    local response = vim.json.encode({
      errors = {
        { message = "Cannot submit empty review" },
      },
    })
    opts.on_stdout(nil, vim.split(response .. "\n200", "\n"))
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_result = nil
  gh_review.submit_review_with_comments(
    "https://api.github.com",
    "test-token",
    "PR_node123",
    "COMMENT",
    nil,
    {},
    function(result, err)
      got_result = { result = result, err = err }
    end
  )

  vim.wait(200, function()
    return got_result ~= nil
  end, 10)

  eq(got_result.result, nil)
  expect.equality(got_result.err:match("GraphQL error") ~= nil, true)
end

-- =============================================================================
-- Pending overlay rendering (pure logic tests)
-- =============================================================================

T["pending_overlays"] = MiniTest.new_set()

T["pending_overlays"]["_apply_pending_overlays finds correct buffer line"] = function()
  -- This tests the mapping logic inside _apply_pending_overlays.
  -- Since _apply_pending_overlays needs real buffers, we test the underlying
  -- line mapping logic instead.
  local pending = {
    { path = "src/main.lua", line = 5, side = "RIGHT", body = "Fix this" },
  }

  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
    { 3, 3 },
    { 4, 4 },
    { 5, 5 }, -- buf line 5, right_lineno = 5 should match
    { 6, 6 },
  })

  -- Verify that the pending comment's line matches in the line_map
  local found_line = nil
  for buf_line, info in ipairs(line_map) do
    if pending[1].side == "RIGHT" and info.right_lineno == pending[1].line then
      found_line = buf_line
      break
    end
  end

  eq(found_line, 5)
end

T["pending_overlays"]["LEFT side pending comment maps correctly"] = function()
  local pending = {
    { path = "src/main.lua", line = 3, side = "LEFT", body = "Old code issue" },
  }

  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
    { 3, 3 }, -- buf line 3, left_lineno = 3 should match
    { 4, 4 },
  })

  local found_line = nil
  for buf_line, info in ipairs(line_map) do
    if pending[1].side == "LEFT" and info.left_lineno == pending[1].line then
      found_line = buf_line
      break
    end
  end

  eq(found_line, 3)
end

T["pending_overlays"]["pending comment with no matching line is skipped"] = function()
  local pending = {
    { path = "src/main.lua", line = 99, side = "RIGHT", body = "No match" },
  }

  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
  })

  local found_line = nil
  for buf_line, info in ipairs(line_map) do
    if pending[1].side == "RIGHT" and info.right_lineno == pending[1].line then
      found_line = buf_line
      break
    end
  end

  eq(found_line, nil)
end

return T
