local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local review = require("gitlad.ui.views.diff.review")

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
---@param entries table[] List of {left_lineno, right_lineno, left_type?, right_type?}
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
-- new_state
-- =============================================================================

T["new_state()"] = MiniTest.new_set()

T["new_state()"]["returns empty state"] = function()
  local state = review.new_state()
  eq(#state.threads, 0)
  eq(vim.tbl_count(state.thread_map), 0)
  eq(vim.tbl_count(state.collapsed), 0)
  eq(state.pr_node_id, nil)
end

-- =============================================================================
-- group_threads_by_path
-- =============================================================================

T["group_threads_by_path()"] = MiniTest.new_set()

T["group_threads_by_path()"]["groups threads correctly"] = function()
  local threads = {
    make_thread({ id = "T1", path = "src/main.lua" }),
    make_thread({ id = "T2", path = "src/utils.lua" }),
    make_thread({ id = "T3", path = "src/main.lua" }),
  }

  local grouped = review.group_threads_by_path(threads)
  eq(#grouped["src/main.lua"], 2)
  eq(#grouped["src/utils.lua"], 1)
  eq(grouped["src/main.lua"][1].id, "T1")
  eq(grouped["src/main.lua"][2].id, "T3")
end

T["group_threads_by_path()"]["returns empty table for empty input"] = function()
  local grouped = review.group_threads_by_path({})
  eq(vim.tbl_count(grouped), 0)
end

-- =============================================================================
-- map_threads_to_lines
-- =============================================================================

T["map_threads_to_lines()"] = MiniTest.new_set()

T["map_threads_to_lines()"]["maps RIGHT thread to correct buffer line"] = function()
  local threads = {
    make_thread({ line = 5, diff_side = "RIGHT" }),
  }
  local line_map = make_line_map({
    { 1, 1 }, -- buf line 1
    { 2, 2 }, -- buf line 2
    { 3, 3 }, -- buf line 3
    { 4, 4 }, -- buf line 4
    { 5, 5 }, -- buf line 5 <- should match
    { 6, 6 }, -- buf line 6
  })

  local result = review.map_threads_to_lines(threads, line_map)
  eq(result[5] ~= nil, true)
  eq(#result[5], 1)
  eq(result[5][1].id, "PRRT_1")
end

T["map_threads_to_lines()"]["maps LEFT thread to correct buffer line"] = function()
  local threads = {
    make_thread({ line = 3, diff_side = "LEFT" }),
  }
  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
    { 3, 3 }, -- buf line 3, left_lineno=3 <- should match
    { 4, 4 },
  })

  local result = review.map_threads_to_lines(threads, line_map)
  eq(result[3] ~= nil, true)
  eq(#result[3], 1)
end

T["map_threads_to_lines()"]["skips threads with nil line"] = function()
  local threads = {
    make_thread({ line = nil, diff_side = "RIGHT" }),
  }
  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
  })

  local result = review.map_threads_to_lines(threads, line_map)
  eq(vim.tbl_count(result), 0)
end

T["map_threads_to_lines()"]["handles multiple threads on same line"] = function()
  local threads = {
    make_thread({ id = "T1", line = 5, diff_side = "RIGHT" }),
    make_thread({ id = "T2", line = 5, diff_side = "RIGHT" }),
  }
  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
    { 3, 3 },
    { 4, 4 },
    { 5, 5 },
  })

  local result = review.map_threads_to_lines(threads, line_map)
  eq(result[5] ~= nil, true)
  eq(#result[5], 2)
  eq(result[5][1].id, "T1")
  eq(result[5][2].id, "T2")
end

T["map_threads_to_lines()"]["handles threads with no matching line in map"] = function()
  local threads = {
    make_thread({ line = 99, diff_side = "RIGHT" }),
  }
  local line_map = make_line_map({
    { 1, 1 },
    { 2, 2 },
  })

  local result = review.map_threads_to_lines(threads, line_map)
  eq(vim.tbl_count(result), 0)
end

T["map_threads_to_lines()"]["handles filler lines (nil line numbers)"] = function()
  local threads = {
    make_thread({ line = 3, diff_side = "RIGHT" }),
  }
  -- Line map with a filler line (nil right_lineno at buf line 2)
  local line_map = {
    {
      left_lineno = 1,
      right_lineno = 1,
      left_type = "context",
      right_type = "context",
      hunk_index = 1,
      is_hunk_boundary = false,
    },
    {
      left_lineno = 2,
      right_lineno = nil,
      left_type = "delete",
      right_type = "filler",
      hunk_index = 1,
      is_hunk_boundary = false,
    },
    {
      left_lineno = nil,
      right_lineno = 2,
      left_type = "filler",
      right_type = "add",
      hunk_index = 1,
      is_hunk_boundary = false,
    },
    {
      left_lineno = 3,
      right_lineno = 3,
      left_type = "context",
      right_type = "context",
      hunk_index = 1,
      is_hunk_boundary = false,
    },
  }

  local result = review.map_threads_to_lines(threads, line_map)
  eq(result[4] ~= nil, true) -- buf line 4 has right_lineno=3
  eq(#result[4], 1)
end

-- =============================================================================
-- format_collapsed
-- =============================================================================

T["format_collapsed()"] = MiniTest.new_set()

T["format_collapsed()"]["formats single comment thread"] = function()
  local thread = make_thread({
    comments = {
      {
        id = "C1",
        author = { login = "alice" },
        body = "Nice change!",
        created_at = "",
        updated_at = "",
      },
    },
  })
  local result = review.format_collapsed(thread)
  expect.equality(result:match("@alice") ~= nil, true)
  expect.equality(result:match("Nice change!") ~= nil, true)
end

T["format_collapsed()"]["shows reply count"] = function()
  local thread = make_thread({
    comments = {
      {
        id = "C1",
        author = { login = "alice" },
        body = "Question?",
        created_at = "",
        updated_at = "",
      },
      { id = "C2", author = { login = "bob" }, body = "Answer!", created_at = "", updated_at = "" },
    },
  })
  local result = review.format_collapsed(thread)
  expect.equality(result:match("%[1 reply%]") ~= nil, true)
end

T["format_collapsed()"]["shows plural replies"] = function()
  local thread = make_thread({
    comments = {
      { id = "C1", author = { login = "a" }, body = "Q", created_at = "", updated_at = "" },
      { id = "C2", author = { login = "b" }, body = "A1", created_at = "", updated_at = "" },
      { id = "C3", author = { login = "c" }, body = "A2", created_at = "", updated_at = "" },
    },
  })
  local result = review.format_collapsed(thread)
  expect.equality(result:match("%[2 replies%]") ~= nil, true)
end

T["format_collapsed()"]["shows resolved status"] = function()
  local thread = make_thread({
    is_resolved = true,
    comments = {
      { id = "C1", author = { login = "a" }, body = "Fixed", created_at = "", updated_at = "" },
    },
  })
  local result = review.format_collapsed(thread)
  expect.equality(result:match("%[resolved%]") ~= nil, true)
end

T["format_collapsed()"]["shows outdated status"] = function()
  local thread = make_thread({
    is_outdated = true,
    comments = {
      { id = "C1", author = { login = "a" }, body = "Old", created_at = "", updated_at = "" },
    },
  })
  local result = review.format_collapsed(thread)
  expect.equality(result:match("%[outdated%]") ~= nil, true)
end

T["format_collapsed()"]["truncates long body"] = function()
  local long_body = string.rep("a", 100)
  local thread = make_thread({
    comments = {
      { id = "C1", author = { login = "a" }, body = long_body, created_at = "", updated_at = "" },
    },
  })
  local result = review.format_collapsed(thread)
  expect.equality(result:match("%.%.%.") ~= nil, true)
  -- Should be reasonably short
  expect.equality(#result < 100, true)
end

T["format_collapsed()"]["returns empty for thread with no comments"] = function()
  local thread = make_thread({ comments = {} })
  local result = review.format_collapsed(thread)
  eq(result, "")
end

-- =============================================================================
-- format_expanded
-- =============================================================================

T["format_expanded()"] = MiniTest.new_set()

T["format_expanded()"]["returns virt_lines for single comment"] = function()
  local thread = make_thread({
    comments = {
      {
        id = "C1",
        author = { login = "alice" },
        body = "Looks good",
        created_at = "2026-02-20T10:00:00Z",
        updated_at = "",
      },
    },
  })
  local virt_lines = review.format_expanded(thread)
  -- Should have: header line, body line, bottom border = at least 3 lines
  expect.equality(#virt_lines >= 3, true)
end

T["format_expanded()"]["includes author in header"] = function()
  local thread = make_thread({
    comments = {
      {
        id = "C1",
        author = { login = "alice" },
        body = "Test",
        created_at = "2026-02-20T10:00:00Z",
        updated_at = "",
      },
    },
  })
  local virt_lines = review.format_expanded(thread)
  -- First line should contain author
  local header = virt_lines[1]
  local found_author = false
  for _, chunk in ipairs(header) do
    if chunk[1] == "alice" then
      found_author = true
    end
  end
  eq(found_author, true)
end

T["format_expanded()"]["handles multi-line body"] = function()
  local thread = make_thread({
    comments = {
      {
        id = "C1",
        author = { login = "alice" },
        body = "Line 1\nLine 2\nLine 3",
        created_at = "2026-02-20T10:00:00Z",
        updated_at = "",
      },
    },
  })
  local virt_lines = review.format_expanded(thread)
  -- header + 3 body lines + bottom border = 5
  eq(#virt_lines, 5)
end

T["format_expanded()"]["handles multiple comments in thread"] = function()
  local thread = make_thread({
    comments = {
      {
        id = "C1",
        author = { login = "alice" },
        body = "Question",
        created_at = "2026-02-20T10:00:00Z",
        updated_at = "",
      },
      {
        id = "C2",
        author = { login = "bob" },
        body = "Answer",
        created_at = "2026-02-20T11:00:00Z",
        updated_at = "",
      },
    },
  })
  local virt_lines = review.format_expanded(thread)
  -- alice header + alice body + separator + bob header + bob body + bottom border = 6
  eq(#virt_lines, 6)
end

-- =============================================================================
-- Navigation helpers
-- =============================================================================

T["next_thread_line()"] = MiniTest.new_set()

T["next_thread_line()"]["finds next thread after current line"] = function()
  local positions = { [5] = make_thread(), [15] = make_thread(), [25] = make_thread() }
  eq(review.next_thread_line(positions, 1), 5)
  eq(review.next_thread_line(positions, 5), 15)
  eq(review.next_thread_line(positions, 10), 15)
  eq(review.next_thread_line(positions, 20), 25)
end

T["next_thread_line()"]["returns nil when no next thread"] = function()
  local positions = { [5] = make_thread() }
  eq(review.next_thread_line(positions, 5), nil)
  eq(review.next_thread_line(positions, 10), nil)
end

T["next_thread_line()"]["returns nil for empty positions"] = function()
  eq(review.next_thread_line({}, 1), nil)
end

T["prev_thread_line()"] = MiniTest.new_set()

T["prev_thread_line()"]["finds previous thread before current line"] = function()
  local positions = { [5] = make_thread(), [15] = make_thread(), [25] = make_thread() }
  eq(review.prev_thread_line(positions, 25), 15)
  eq(review.prev_thread_line(positions, 20), 15)
  eq(review.prev_thread_line(positions, 10), 5)
end

T["prev_thread_line()"]["returns nil when no previous thread"] = function()
  local positions = { [5] = make_thread() }
  eq(review.prev_thread_line(positions, 5), nil)
  eq(review.prev_thread_line(positions, 1), nil)
end

T["prev_thread_line()"]["returns nil for empty positions"] = function()
  eq(review.prev_thread_line({}, 10), nil)
end

-- =============================================================================
-- thread_at_cursor
-- =============================================================================

T["thread_at_cursor()"] = MiniTest.new_set()

T["thread_at_cursor()"]["finds exact match"] = function()
  local t = make_thread({ id = "T1" })
  local positions = { [10] = t }
  local thread, line = review.thread_at_cursor(positions, 10)
  eq(thread.id, "T1")
  eq(line, 10)
end

T["thread_at_cursor()"]["searches upward for nearby thread"] = function()
  local t = make_thread({ id = "T1" })
  local positions = { [10] = t }
  -- Cursor is at line 12 (within virt_lines area below line 10)
  local thread, line = review.thread_at_cursor(positions, 12)
  eq(thread.id, "T1")
  eq(line, 10)
end

T["thread_at_cursor()"]["returns nil when too far from thread"] = function()
  local t = make_thread({ id = "T1" })
  local positions = { [10] = t }
  -- Cursor is at line 50 (too far)
  local thread, line = review.thread_at_cursor(positions, 50)
  eq(thread, nil)
  eq(line, nil)
end

T["thread_at_cursor()"]["returns nil for empty positions"] = function()
  local thread, line = review.thread_at_cursor({}, 5)
  eq(thread, nil)
  eq(line, nil)
end

return T
