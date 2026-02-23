local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local three_way = require("gitlad.ui.views.diff.three_way")

-- =============================================================================
-- Helper: build a DiffSideBySideHunk from raw pairs for testing
-- =============================================================================

--- Build a hunk from simplified pair specs
---@param old_start number
---@param old_count number
---@param new_start number
---@param new_count number
---@param pairs table[] Array of { left_line, right_line, left_type, right_type, left_lineno, right_lineno }
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

--- Build a context pair
local function ctx(lineno, content)
  return {
    left_line = content,
    right_line = content,
    left_type = "context",
    right_type = "context",
    left_lineno = lineno,
    right_lineno = lineno,
  }
end

--- Build a change pair (old line changed to new line)
local function chg(old_lineno, old_content, new_lineno, new_content)
  return {
    left_line = old_content,
    right_line = new_content,
    left_type = "change",
    right_type = "change",
    left_lineno = old_lineno,
    right_lineno = new_lineno,
  }
end

--- Build a delete pair (line deleted from old side)
local function del(old_lineno, content)
  return {
    left_line = content,
    right_line = nil,
    left_type = "delete",
    right_type = "filler",
    left_lineno = old_lineno,
    right_lineno = nil,
  }
end

--- Build an add pair (line added on new side)
local function add(new_lineno, content)
  return {
    left_line = nil,
    right_line = content,
    left_type = "filler",
    right_type = "add",
    left_lineno = nil,
    right_lineno = new_lineno,
  }
end

-- =============================================================================
-- merge_file_lists
-- =============================================================================

T["merge_file_lists"] = MiniTest.new_set()

T["merge_file_lists"]["merges empty lists"] = function()
  local result = three_way.merge_file_lists({}, {})
  eq(#result, 0)
end

T["merge_file_lists"]["staged only files"] = function()
  local staged = {
    {
      old_path = "a.lua",
      new_path = "a.lua",
      status = "M",
      hunks = {},
      additions = 3,
      deletions = 1,
      is_binary = false,
    },
  }
  local result = three_way.merge_file_lists(staged, {})
  eq(#result, 1)
  eq(result[1].path, "a.lua")
  eq(result[1].status_staged, "M")
  eq(result[1].status_unstaged, nil)
  eq(result[1].additions, 3)
  eq(result[1].deletions, 1)
  eq(#result[1].staged_hunks, 0)
  eq(#result[1].unstaged_hunks, 0)
end

T["merge_file_lists"]["unstaged only files"] = function()
  local unstaged = {
    {
      old_path = "b.lua",
      new_path = "b.lua",
      status = "M",
      hunks = {},
      additions = 2,
      deletions = 0,
      is_binary = false,
    },
  }
  local result = three_way.merge_file_lists({}, unstaged)
  eq(#result, 1)
  eq(result[1].path, "b.lua")
  eq(result[1].status_staged, nil)
  eq(result[1].status_unstaged, "M")
  eq(result[1].additions, 2)
end

T["merge_file_lists"]["merges files appearing in both"] = function()
  local staged = {
    {
      old_path = "file.lua",
      new_path = "file.lua",
      status = "M",
      hunks = {},
      additions = 5,
      deletions = 2,
      is_binary = false,
    },
  }
  local unstaged = {
    {
      old_path = "file.lua",
      new_path = "file.lua",
      status = "M",
      hunks = {},
      additions = 3,
      deletions = 1,
      is_binary = false,
    },
  }
  local result = three_way.merge_file_lists(staged, unstaged)
  eq(#result, 1)
  eq(result[1].path, "file.lua")
  eq(result[1].status_staged, "M")
  eq(result[1].status_unstaged, "M")
  eq(result[1].additions, 8) -- 5 + 3
  eq(result[1].deletions, 3) -- 2 + 1
end

T["merge_file_lists"]["preserves order: staged first, then unstaged-only"] = function()
  local staged = {
    {
      old_path = "a.lua",
      new_path = "a.lua",
      status = "M",
      hunks = {},
      additions = 1,
      deletions = 0,
      is_binary = false,
    },
    {
      old_path = "c.lua",
      new_path = "c.lua",
      status = "M",
      hunks = {},
      additions = 1,
      deletions = 0,
      is_binary = false,
    },
  }
  local unstaged = {
    {
      old_path = "b.lua",
      new_path = "b.lua",
      status = "M",
      hunks = {},
      additions = 1,
      deletions = 0,
      is_binary = false,
    },
    {
      old_path = "c.lua",
      new_path = "c.lua",
      status = "M",
      hunks = {},
      additions = 1,
      deletions = 0,
      is_binary = false,
    },
  }
  local result = three_way.merge_file_lists(staged, unstaged)
  eq(#result, 3)
  eq(result[1].path, "a.lua") -- staged only
  eq(result[2].path, "c.lua") -- both
  eq(result[3].path, "b.lua") -- unstaged only
end

-- =============================================================================
-- align_three_way
-- =============================================================================

T["align_three_way"] = MiniTest.new_set()

T["align_three_way"]["returns empty for no hunks"] = function()
  local file_diff = {
    path = "empty.lua",
    staged_hunks = {},
    unstaged_hunks = {},
    status_staged = nil,
    status_unstaged = nil,
    additions = 0,
    deletions = 0,
  }
  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 0)
  eq(#result.mid_lines, 0)
  eq(#result.right_lines, 0)
  eq(#result.line_map, 0)
end

T["align_three_way"]["staged-only change: HEAD differs, INDEX=WORKTREE"] = function()
  -- Staged diff (HEAD→INDEX): line 1 changed from "old" to "new"
  local staged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "old", 1, "new"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 1,
    deletions = 1,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)
  eq(#result.mid_lines, 1)
  eq(#result.right_lines, 1)

  -- HEAD shows old content, INDEX and WORKTREE show new
  eq(result.left_lines[1], "old")
  eq(result.mid_lines[1], "new")
  eq(result.right_lines[1], "new")

  -- Types: HEAD=change, INDEX=change, WORKTREE=change (mirrors INDEX)
  eq(result.line_map[1].left_type, "change")
  eq(result.line_map[1].mid_type, "change")
  eq(result.line_map[1].right_type, "change")
  eq(result.line_map[1].is_hunk_boundary, true)
end

T["align_three_way"]["unstaged-only change: HEAD=INDEX, WORKTREE differs"] = function()
  -- Unstaged diff (INDEX→WORKTREE): line 1 changed from "original" to "modified"
  local unstaged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "original", 1, "modified"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = {},
    unstaged_hunks = unstaged_hunks,
    status_staged = nil,
    status_unstaged = "M",
    additions = 1,
    deletions = 1,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)

  -- HEAD and INDEX show same content, WORKTREE shows modified
  eq(result.left_lines[1], "original")
  eq(result.mid_lines[1], "original")
  eq(result.right_lines[1], "modified")

  eq(result.line_map[1].left_type, "change")
  eq(result.line_map[1].mid_type, "change")
  eq(result.line_map[1].right_type, "change")
end

T["align_three_way"]["staged addition: new line in INDEX, not in HEAD"] = function()
  -- Staged diff: a line was added at position 1 in INDEX
  local staged_hunks = {
    make_hunk(0, 0, 1, 1, {
      add(1, "new line"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 1,
    deletions = 0,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)

  -- HEAD has filler, INDEX and WORKTREE have the new line
  eq(result.left_lines[1], "")
  eq(result.mid_lines[1], "new line")
  eq(result.right_lines[1], "new line")

  eq(result.line_map[1].left_type, "filler")
  eq(result.line_map[1].mid_type, "add")
  eq(result.line_map[1].right_type, "add")
end

T["align_three_way"]["staged deletion: line removed from HEAD, not in INDEX"] = function()
  -- Staged diff: line 1 "deleted" removed from HEAD, INDEX has nothing there
  local staged_hunks = {
    make_hunk(1, 1, 0, 0, {
      del(1, "deleted"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 0,
    deletions = 1,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)

  -- HEAD shows the deleted line, INDEX and WORKTREE show filler
  eq(result.left_lines[1], "deleted")
  eq(result.mid_lines[1], "")
  eq(result.right_lines[1], "")

  eq(result.line_map[1].left_type, "delete")
  eq(result.line_map[1].mid_type, "filler")
  eq(result.line_map[1].right_type, "filler")
end

T["align_three_way"]["unstaged addition: new line in WORKTREE, not in INDEX"] = function()
  -- Unstaged diff: a line was added at position 1 in WORKTREE
  local unstaged_hunks = {
    make_hunk(0, 0, 1, 1, {
      add(1, "added in worktree"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = {},
    unstaged_hunks = unstaged_hunks,
    status_staged = nil,
    status_unstaged = "M",
    additions = 1,
    deletions = 0,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)

  -- HEAD and INDEX have filler, WORKTREE has the new line
  eq(result.left_lines[1], "")
  eq(result.mid_lines[1], "")
  eq(result.right_lines[1], "added in worktree")

  eq(result.line_map[1].left_type, "filler")
  eq(result.line_map[1].mid_type, "filler")
  eq(result.line_map[1].right_type, "add")
end

T["align_three_way"]["unstaged deletion: line in INDEX removed from WORKTREE"] = function()
  -- Unstaged diff: line 1 "kept in index" removed from WORKTREE
  local unstaged_hunks = {
    make_hunk(1, 1, 0, 0, {
      del(1, "kept in index"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = {},
    unstaged_hunks = unstaged_hunks,
    status_staged = nil,
    status_unstaged = "M",
    additions = 0,
    deletions = 1,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)

  -- HEAD and INDEX show the content, WORKTREE has filler
  eq(result.left_lines[1], "kept in index")
  eq(result.mid_lines[1], "kept in index")
  eq(result.right_lines[1], "")

  eq(result.line_map[1].left_type, "delete")
  eq(result.line_map[1].mid_type, "delete")
  eq(result.line_map[1].right_type, "filler")
end

T["align_three_way"]["non-overlapping hunks: staged at line 1, unstaged at line 5"] = function()
  -- Staged: change at line 1
  local staged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "head_v1", 1, "index_v1"),
    }),
  }
  -- Unstaged: change at line 5 (no overlap with staged)
  local unstaged_hunks = {
    make_hunk(5, 1, 5, 1, {
      chg(5, "index_v5", 5, "worktree_v5"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = unstaged_hunks,
    status_staged = "M",
    status_unstaged = "M",
    additions = 2,
    deletions = 2,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 2)

  -- First line: staged change (HEAD≠INDEX, WORKTREE=INDEX)
  eq(result.left_lines[1], "head_v1")
  eq(result.mid_lines[1], "index_v1")
  eq(result.right_lines[1], "index_v1")
  eq(result.line_map[1].hunk_index, 1)
  eq(result.line_map[1].is_hunk_boundary, true)

  -- Second line: unstaged change (HEAD=INDEX, WORKTREE≠INDEX)
  eq(result.left_lines[2], "index_v5")
  eq(result.mid_lines[2], "index_v5")
  eq(result.right_lines[2], "worktree_v5")
  eq(result.line_map[2].hunk_index, 2)
  eq(result.line_map[2].is_hunk_boundary, true)
end

T["align_three_way"]["overlapping hunks: same INDEX line modified in both"] = function()
  -- Staged: line 1 changed from "head" to "index" (HEAD→INDEX)
  local staged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "head", 1, "index"),
    }),
  }
  -- Unstaged: line 1 changed from "index" to "worktree" (INDEX→WORKTREE)
  local unstaged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "index", 1, "worktree"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = unstaged_hunks,
    status_staged = "M",
    status_unstaged = "M",
    additions = 2,
    deletions = 2,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 1)

  -- All three panes differ
  eq(result.left_lines[1], "head")
  eq(result.mid_lines[1], "index")
  eq(result.right_lines[1], "worktree")

  eq(result.line_map[1].left_type, "change")
  eq(result.line_map[1].mid_type, "change")
  eq(result.line_map[1].right_type, "change")
end

T["align_three_way"]["staged hunk with context lines"] = function()
  -- Staged diff with context around the change
  local staged_hunks = {
    make_hunk(1, 3, 1, 3, {
      ctx(1, "context before"),
      chg(2, "old line", 2, "new line"),
      ctx(3, "context after"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 1,
    deletions = 1,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 3)

  -- Context lines: all 3 panes same
  eq(result.left_lines[1], "context before")
  eq(result.mid_lines[1], "context before")
  eq(result.right_lines[1], "context before")
  eq(result.line_map[1].left_type, "context")
  eq(result.line_map[1].mid_type, "context")
  eq(result.line_map[1].right_type, "context")
  eq(result.line_map[1].is_hunk_boundary, true)

  -- Changed line
  eq(result.left_lines[2], "old line")
  eq(result.mid_lines[2], "new line")
  eq(result.right_lines[2], "new line")

  -- Context after
  eq(result.left_lines[3], "context after")
  eq(result.mid_lines[3], "context after")
  eq(result.right_lines[3], "context after")
end

T["align_three_way"]["multiple staged hunks"] = function()
  local staged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "old1", 1, "new1"),
    }),
    make_hunk(5, 1, 5, 1, {
      chg(5, "old5", 5, "new5"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 2,
    deletions = 2,
  }

  local result = three_way.align_three_way(file_diff)
  eq(#result.left_lines, 2)

  eq(result.left_lines[1], "old1")
  eq(result.mid_lines[1], "new1")
  eq(result.right_lines[1], "new1")
  eq(result.line_map[1].hunk_index, 1)

  eq(result.left_lines[2], "old5")
  eq(result.mid_lines[2], "new5")
  eq(result.right_lines[2], "new5")
  eq(result.line_map[2].hunk_index, 2)
end

T["align_three_way"]["line numbers are correct for all panes"] = function()
  -- Staged: change line 3
  local staged_hunks = {
    make_hunk(3, 1, 3, 1, {
      chg(3, "head_line3", 3, "index_line3"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 1,
    deletions = 1,
  }

  local result = three_way.align_three_way(file_diff)
  eq(result.line_map[1].left_lineno, 3) -- HEAD line 3
  eq(result.line_map[1].mid_lineno, 3) -- INDEX line 3
  eq(result.line_map[1].right_lineno, 3) -- WORKTREE line 3 (same as INDEX)
end

T["align_three_way"]["filler lines have nil line numbers"] = function()
  -- Staged addition
  local staged_hunks = {
    make_hunk(0, 0, 1, 1, {
      add(1, "added"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = {},
    status_staged = "M",
    status_unstaged = nil,
    additions = 1,
    deletions = 0,
  }

  local result = three_way.align_three_way(file_diff)
  eq(result.line_map[1].left_lineno, nil) -- HEAD has filler
  eq(result.line_map[1].mid_lineno, 1) -- INDEX line 1
  eq(result.line_map[1].right_lineno, 1) -- WORKTREE line 1
end

T["align_three_way"]["overlapping: staged deletion + unstaged change at adjacent lines"] = function()
  -- Staged: delete line 1 from HEAD (HEAD has "deleted", INDEX doesn't)
  local staged_hunks = {
    make_hunk(1, 2, 1, 1, {
      del(1, "deleted from head"),
      ctx(2, "kept line"),
    }),
  }
  -- Unstaged: change line 1 of INDEX (which is "kept line") to something else
  local unstaged_hunks = {
    make_hunk(1, 1, 1, 1, {
      chg(1, "kept line", 1, "modified in worktree"),
    }),
  }

  local file_diff = {
    path = "test.lua",
    staged_hunks = staged_hunks,
    unstaged_hunks = unstaged_hunks,
    status_staged = "M",
    status_unstaged = "M",
    additions = 1,
    deletions = 2,
  }

  local result = three_way.align_three_way(file_diff)
  -- Should have 2 lines:
  -- 1. HEAD="deleted from head", INDEX=filler, WORKTREE=filler
  -- 2. HEAD="kept line", INDEX="kept line", WORKTREE="modified in worktree"
  eq(#result.left_lines >= 2, true)

  -- The deleted line from HEAD: only appears in HEAD
  eq(result.left_lines[1], "deleted from head")
  eq(result.line_map[1].left_type, "delete")
  eq(result.line_map[1].mid_type, "filler")
  eq(result.line_map[1].right_type, "filler")
end

return T
