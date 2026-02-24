-- Tests for gitlad.ui.views.diff.content module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local content = require("gitlad.ui.views.diff.content")

-- =============================================================================
-- align_sides
-- =============================================================================

T["align_sides"] = MiniTest.new_set()

--- Helper to build a DiffFilePair for testing
---@param hunks table[] Array of {header, pairs} tables
---@return DiffFilePair
local function make_file_pair(hunks)
  return {
    old_path = "test.lua",
    new_path = "test.lua",
    status = "M",
    hunks = hunks,
    additions = 0,
    deletions = 0,
    is_binary = false,
  }
end

--- Helper to build a DiffSideBySideHunk
---@param old_start number
---@param old_count number
---@param new_start number
---@param new_count number
---@param pairs DiffLinePair[]
---@return DiffSideBySideHunk
local function make_hunk(old_start, old_count, new_start, new_count, pairs)
  return {
    header = {
      old_start = old_start,
      old_count = old_count,
      new_start = new_start,
      new_count = new_count,
      text = string.format("@@ -%d,%d +%d,%d @@", old_start, old_count, new_start, new_count),
    },
    pairs = pairs,
  }
end

T["align_sides"]["single hunk with context and changes"] = function()
  local fp = make_file_pair({
    make_hunk(1, 3, 1, 3, {
      {
        left_line = "line 1",
        right_line = "line 1",
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
      },
      {
        left_line = "old line 2",
        right_line = "new line 2",
        left_type = "change",
        right_type = "change",
        left_lineno = 2,
        right_lineno = 2,
      },
      {
        left_line = "line 3",
        right_line = "line 3",
        left_type = "context",
        right_type = "context",
        left_lineno = 3,
        right_lineno = 3,
      },
    }),
  })

  local result = content.align_sides(fp)

  eq(#result.left_lines, 3)
  eq(#result.right_lines, 3)
  eq(#result.line_map, 3)

  -- Context lines
  eq(result.left_lines[1], "line 1")
  eq(result.right_lines[1], "line 1")

  -- Changed lines
  eq(result.left_lines[2], "old line 2")
  eq(result.right_lines[2], "new line 2")

  -- Context lines
  eq(result.left_lines[3], "line 3")
  eq(result.right_lines[3], "line 3")
end

T["align_sides"]["multiple hunks"] = function()
  local fp = make_file_pair({
    make_hunk(1, 2, 1, 2, {
      {
        left_line = "a",
        right_line = "a",
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
      },
      {
        left_line = "old b",
        right_line = "new b",
        left_type = "change",
        right_type = "change",
        left_lineno = 2,
        right_lineno = 2,
      },
    }),
    make_hunk(10, 2, 10, 2, {
      {
        left_line = "j",
        right_line = "j",
        left_type = "context",
        right_type = "context",
        left_lineno = 10,
        right_lineno = 10,
      },
      {
        left_line = "old k",
        right_line = "new k",
        left_type = "change",
        right_type = "change",
        left_lineno = 11,
        right_lineno = 11,
      },
    }),
  })

  local result = content.align_sides(fp)

  eq(#result.left_lines, 4)
  eq(#result.right_lines, 4)
  eq(#result.line_map, 4)

  -- First hunk
  eq(result.left_lines[1], "a")
  eq(result.left_lines[2], "old b")

  -- Second hunk
  eq(result.left_lines[3], "j")
  eq(result.left_lines[4], "old k")
  eq(result.right_lines[4], "new k")
end

T["align_sides"]["pure additions (new file)"] = function()
  local fp = make_file_pair({
    make_hunk(0, 0, 1, 3, {
      {
        left_line = nil,
        right_line = "line 1",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 1,
      },
      {
        left_line = nil,
        right_line = "line 2",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 2,
      },
      {
        left_line = nil,
        right_line = "line 3",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 3,
      },
    }),
  })
  fp.status = "A"

  local result = content.align_sides(fp)

  eq(#result.left_lines, 3)
  eq(#result.right_lines, 3)

  -- Left side should be filler (empty strings)
  eq(result.left_lines[1], "")
  eq(result.left_lines[2], "")
  eq(result.left_lines[3], "")

  -- Right side has the new content
  eq(result.right_lines[1], "line 1")
  eq(result.right_lines[2], "line 2")
  eq(result.right_lines[3], "line 3")

  -- Types
  eq(result.line_map[1].left_type, "filler")
  eq(result.line_map[1].right_type, "add")
  eq(result.line_map[2].left_type, "filler")
  eq(result.line_map[2].right_type, "add")
end

T["align_sides"]["pure deletions (deleted file)"] = function()
  local fp = make_file_pair({
    make_hunk(1, 3, 0, 0, {
      {
        left_line = "line 1",
        right_line = nil,
        left_type = "delete",
        right_type = "filler",
        left_lineno = 1,
        right_lineno = nil,
      },
      {
        left_line = "line 2",
        right_line = nil,
        left_type = "delete",
        right_type = "filler",
        left_lineno = 2,
        right_lineno = nil,
      },
      {
        left_line = "line 3",
        right_line = nil,
        left_type = "delete",
        right_type = "filler",
        left_lineno = 3,
        right_lineno = nil,
      },
    }),
  })
  fp.status = "D"

  local result = content.align_sides(fp)

  eq(#result.left_lines, 3)
  eq(#result.right_lines, 3)

  -- Left side has the deleted content
  eq(result.left_lines[1], "line 1")
  eq(result.left_lines[2], "line 2")
  eq(result.left_lines[3], "line 3")

  -- Right side should be filler (empty strings)
  eq(result.right_lines[1], "")
  eq(result.right_lines[2], "")
  eq(result.right_lines[3], "")

  -- Types
  eq(result.line_map[1].left_type, "delete")
  eq(result.line_map[1].right_type, "filler")
end

T["align_sides"]["filler lines are empty strings"] = function()
  local fp = make_file_pair({
    make_hunk(1, 1, 1, 2, {
      {
        left_line = "old line",
        right_line = "new line 1",
        left_type = "change",
        right_type = "change",
        left_lineno = 1,
        right_lineno = 1,
      },
      {
        left_line = nil,
        right_line = "new line 2",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 2,
      },
    }),
  })

  local result = content.align_sides(fp)

  -- Filler line on left should be empty string, not nil
  eq(result.left_lines[2], "")
  eq(result.right_lines[2], "new line 2")
end

T["align_sides"]["line_map has correct types and line numbers"] = function()
  local fp = make_file_pair({
    make_hunk(5, 4, 5, 4, {
      {
        left_line = "ctx",
        right_line = "ctx",
        left_type = "context",
        right_type = "context",
        left_lineno = 5,
        right_lineno = 5,
      },
      {
        left_line = "old",
        right_line = "new",
        left_type = "change",
        right_type = "change",
        left_lineno = 6,
        right_lineno = 6,
      },
      {
        left_line = "del",
        right_line = nil,
        left_type = "delete",
        right_type = "filler",
        left_lineno = 7,
        right_lineno = nil,
      },
      {
        left_line = nil,
        right_line = "add",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 7,
      },
    }),
  })

  local result = content.align_sides(fp)

  -- Context line
  eq(result.line_map[1].left_type, "context")
  eq(result.line_map[1].right_type, "context")
  eq(result.line_map[1].left_lineno, 5)
  eq(result.line_map[1].right_lineno, 5)

  -- Change line
  eq(result.line_map[2].left_type, "change")
  eq(result.line_map[2].right_type, "change")
  eq(result.line_map[2].left_lineno, 6)
  eq(result.line_map[2].right_lineno, 6)

  -- Delete line
  eq(result.line_map[3].left_type, "delete")
  eq(result.line_map[3].right_type, "filler")
  eq(result.line_map[3].left_lineno, 7)
  eq(result.line_map[3].right_lineno, nil)

  -- Add line
  eq(result.line_map[4].left_type, "filler")
  eq(result.line_map[4].right_type, "add")
  eq(result.line_map[4].left_lineno, nil)
  eq(result.line_map[4].right_lineno, 7)
end

T["align_sides"]["hunk_index is set correctly"] = function()
  local fp = make_file_pair({
    make_hunk(1, 1, 1, 1, {
      {
        left_line = "a",
        right_line = "b",
        left_type = "change",
        right_type = "change",
        left_lineno = 1,
        right_lineno = 1,
      },
    }),
    make_hunk(10, 1, 10, 1, {
      {
        left_line = "x",
        right_line = "y",
        left_type = "change",
        right_type = "change",
        left_lineno = 10,
        right_lineno = 10,
      },
    }),
    make_hunk(20, 1, 20, 1, {
      {
        left_line = "m",
        right_line = "n",
        left_type = "change",
        right_type = "change",
        left_lineno = 20,
        right_lineno = 20,
      },
    }),
  })

  local result = content.align_sides(fp)

  eq(result.line_map[1].hunk_index, 1)
  eq(result.line_map[2].hunk_index, 2)
  eq(result.line_map[3].hunk_index, 3)
end

T["align_sides"]["is_hunk_boundary marks context-to-change transitions"] = function()
  local fp = make_file_pair({
    make_hunk(1, 2, 1, 2, {
      {
        left_line = "a",
        right_line = "a",
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
      },
      {
        left_line = "b",
        right_line = "c",
        left_type = "change",
        right_type = "change",
        left_lineno = 2,
        right_lineno = 2,
      },
    }),
    make_hunk(10, 2, 10, 2, {
      {
        left_line = "j",
        right_line = "j",
        left_type = "context",
        right_type = "context",
        left_lineno = 10,
        right_lineno = 10,
      },
      {
        left_line = "k",
        right_line = "l",
        left_type = "change",
        right_type = "change",
        left_lineno = 11,
        right_lineno = 11,
      },
    }),
  })

  local result = content.align_sides(fp)

  eq(#result.line_map, 4)

  -- Context line — not a boundary
  eq(result.line_map[1].is_hunk_boundary, false)
  -- First change after context — boundary
  eq(result.line_map[2].is_hunk_boundary, true)
  -- Context line in second hunk — not a boundary
  eq(result.line_map[3].is_hunk_boundary, false)
  -- First change after context — boundary
  eq(result.line_map[4].is_hunk_boundary, true)
end

T["align_sides"]["is_hunk_boundary marks multiple change regions in single hunk"] = function()
  -- Simulates -U999999 merging two change regions into one hunk
  local fp = make_file_pair({
    make_hunk(1, 5, 1, 5, {
      {
        left_line = "a",
        right_line = "A",
        left_type = "change",
        right_type = "change",
        left_lineno = 1,
        right_lineno = 1,
      },
      {
        left_line = "b",
        right_line = "b",
        left_type = "context",
        right_type = "context",
        left_lineno = 2,
        right_lineno = 2,
      },
      {
        left_line = "c",
        right_line = "c",
        left_type = "context",
        right_type = "context",
        left_lineno = 3,
        right_lineno = 3,
      },
      {
        left_line = "d",
        right_line = "D",
        left_type = "change",
        right_type = "change",
        left_lineno = 4,
        right_lineno = 4,
      },
      {
        left_line = "e",
        right_line = "E",
        left_type = "change",
        right_type = "change",
        left_lineno = 5,
        right_lineno = 5,
      },
    }),
  })

  local result = content.align_sides(fp)

  eq(#result.line_map, 5)

  -- First non-context line (start of first change region)
  eq(result.line_map[1].is_hunk_boundary, true)
  -- Context lines
  eq(result.line_map[2].is_hunk_boundary, false)
  eq(result.line_map[3].is_hunk_boundary, false)
  -- First change after context (start of second change region)
  eq(result.line_map[4].is_hunk_boundary, true)
  -- Continuation of change region
  eq(result.line_map[5].is_hunk_boundary, false)
end

T["align_sides"]["empty file pair produces empty result"] = function()
  local fp = make_file_pair({})

  local result = content.align_sides(fp)

  eq(#result.left_lines, 0)
  eq(#result.right_lines, 0)
  eq(#result.line_map, 0)
end

T["align_sides"]["mixed additions and deletions in a single hunk"] = function()
  local fp = make_file_pair({
    make_hunk(1, 3, 1, 4, {
      {
        left_line = "ctx",
        right_line = "ctx",
        left_type = "context",
        right_type = "context",
        left_lineno = 1,
        right_lineno = 1,
      },
      {
        left_line = "del 1",
        right_line = nil,
        left_type = "delete",
        right_type = "filler",
        left_lineno = 2,
        right_lineno = nil,
      },
      {
        left_line = nil,
        right_line = "add 1",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 2,
      },
      {
        left_line = nil,
        right_line = "add 2",
        left_type = "filler",
        right_type = "add",
        left_lineno = nil,
        right_lineno = 3,
      },
      {
        left_line = "ctx2",
        right_line = "ctx2",
        left_type = "context",
        right_type = "context",
        left_lineno = 3,
        right_lineno = 4,
      },
    }),
  })

  local result = content.align_sides(fp)

  eq(#result.left_lines, 5)
  eq(#result.right_lines, 5)

  eq(result.left_lines[1], "ctx")
  eq(result.left_lines[2], "del 1")
  eq(result.left_lines[3], "")
  eq(result.left_lines[4], "")
  eq(result.left_lines[5], "ctx2")

  eq(result.right_lines[1], "ctx")
  eq(result.right_lines[2], "")
  eq(result.right_lines[3], "add 1")
  eq(result.right_lines[4], "add 2")
  eq(result.right_lines[5], "ctx2")
end

-- =============================================================================
-- ref_for_source
-- =============================================================================

T["ref_for_source"] = MiniTest.new_set()

T["ref_for_source"]["staged: left is HEAD, right is INDEX"] = function()
  local source = { type = "staged" }
  eq(content.ref_for_source(source, "left"), "HEAD")
  eq(content.ref_for_source(source, "right"), "INDEX")
end

T["ref_for_source"]["unstaged: left is INDEX, right is WORKTREE"] = function()
  local source = { type = "unstaged" }
  eq(content.ref_for_source(source, "left"), "INDEX")
  eq(content.ref_for_source(source, "right"), "WORKTREE")
end

T["ref_for_source"]["worktree: left is HEAD, right is WORKTREE"] = function()
  local source = { type = "worktree" }
  eq(content.ref_for_source(source, "left"), "HEAD")
  eq(content.ref_for_source(source, "right"), "WORKTREE")
end

T["ref_for_source"]["commit: left is ref^, right is ref"] = function()
  local source = { type = "commit", ref = "abc123" }
  eq(content.ref_for_source(source, "left"), "abc123^")
  eq(content.ref_for_source(source, "right"), "abc123")
end

T["ref_for_source"]["commit without ref defaults to HEAD"] = function()
  local source = { type = "commit" }
  eq(content.ref_for_source(source, "left"), "HEAD^")
  eq(content.ref_for_source(source, "right"), "HEAD")
end

T["ref_for_source"]["stash: left is ref^, right is ref"] = function()
  local source = { type = "stash", ref = "stash@{0}" }
  eq(content.ref_for_source(source, "left"), "stash@{0}^")
  eq(content.ref_for_source(source, "right"), "stash@{0}")
end

T["ref_for_source"]["range with two dots: splits into left and right"] = function()
  local source = { type = "range", range = "main..feature" }
  eq(content.ref_for_source(source, "left"), "main")
  eq(content.ref_for_source(source, "right"), "feature")
end

T["ref_for_source"]["range with three dots: splits into left and right"] = function()
  local source = { type = "range", range = "main...feature" }
  eq(content.ref_for_source(source, "left"), "main")
  eq(content.ref_for_source(source, "right"), "feature")
end

T["ref_for_source"]["range with commit hashes"] = function()
  local source = { type = "range", range = "abc123..def456" }
  eq(content.ref_for_source(source, "left"), "abc123")
  eq(content.ref_for_source(source, "right"), "def456")
end

T["ref_for_source"]["pr: uses base and head OIDs"] = function()
  local source = {
    type = "pr",
    pr_info = {
      number = 42,
      title = "Test PR",
      base_ref = "main",
      head_ref = "feature",
      base_oid = "aaa111",
      head_oid = "bbb222",
      commits = {},
    },
  }
  eq(content.ref_for_source(source, "left"), "aaa111")
  eq(content.ref_for_source(source, "right"), "bbb222")
end

T["ref_for_source"]["pr: falls back to ref names when OIDs missing"] = function()
  local source = {
    type = "pr",
    pr_info = {
      number = 42,
      title = "Test PR",
      base_ref = "main",
      head_ref = "feature",
      commits = {},
    },
  }
  eq(content.ref_for_source(source, "left"), "main")
  eq(content.ref_for_source(source, "right"), "feature")
end

T["ref_for_source"]["three_way: left is HEAD, mid is INDEX, right is WORKTREE"] = function()
  local source = { type = "three_way" }
  eq(content.ref_for_source(source, "left"), "HEAD")
  eq(content.ref_for_source(source, "mid"), "INDEX")
  eq(content.ref_for_source(source, "right"), "WORKTREE")
end

T["ref_for_source"]["merge: left is OURS, mid is WORKTREE, right is THEIRS"] = function()
  local source = { type = "merge" }
  eq(content.ref_for_source(source, "left"), ":2:")
  eq(content.ref_for_source(source, "mid"), "WORKTREE")
  eq(content.ref_for_source(source, "right"), ":3:")
end

return T
