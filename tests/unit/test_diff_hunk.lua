-- Tests for gitlad.ui.views.diff.hunk module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local hunk = require("gitlad.ui.views.diff.hunk")

-- =============================================================================
-- parse_hunk_header
-- =============================================================================

T["parse_hunk_header"] = MiniTest.new_set()

T["parse_hunk_header"]["parses standard header"] = function()
  local h = hunk.parse_hunk_header("@@ -1,5 +1,7 @@ function foo()")
  eq(h.old_start, 1)
  eq(h.old_count, 5)
  eq(h.new_start, 1)
  eq(h.new_count, 7)
  eq(h.text, "@@ -1,5 +1,7 @@ function foo()")
end

T["parse_hunk_header"]["parses header without counts (single line)"] = function()
  local h = hunk.parse_hunk_header("@@ -1 +1 @@")
  eq(h.old_start, 1)
  eq(h.old_count, 1)
  eq(h.new_start, 1)
  eq(h.new_count, 1)
end

T["parse_hunk_header"]["parses header with zero count"] = function()
  local h = hunk.parse_hunk_header("@@ -0,0 +1,3 @@")
  eq(h.old_start, 0)
  eq(h.old_count, 0)
  eq(h.new_start, 1)
  eq(h.new_count, 3)
end

T["parse_hunk_header"]["returns nil for non-header"] = function()
  eq(hunk.parse_hunk_header("not a header"), nil)
  eq(hunk.parse_hunk_header(""), nil)
  eq(hunk.parse_hunk_header("--- a/file.lua"), nil)
end

-- =============================================================================
-- pair_change_run
-- =============================================================================

T["pair_change_run"] = MiniTest.new_set()

T["pair_change_run"]["pairs equal counts as change"] = function()
  local pairs = hunk.pair_change_run(
    { "old line 1", "old line 2" },
    { 10, 11 },
    { "new line 1", "new line 2" },
    { 10, 11 }
  )
  eq(#pairs, 2)
  eq(pairs[1].left_line, "old line 1")
  eq(pairs[1].right_line, "new line 1")
  eq(pairs[1].left_type, "change")
  eq(pairs[1].right_type, "change")
  eq(pairs[1].left_lineno, 10)
  eq(pairs[1].right_lineno, 10)
end

T["pair_change_run"]["extra deletions become delete+filler"] = function()
  local pairs = hunk.pair_change_run({ "del 1", "del 2", "del 3" }, { 1, 2, 3 }, { "add 1" }, { 1 })
  eq(#pairs, 3)
  -- First pair: change
  eq(pairs[1].left_type, "change")
  eq(pairs[1].right_type, "change")
  -- Extra deletions
  eq(pairs[2].left_line, "del 2")
  eq(pairs[2].left_type, "delete")
  eq(pairs[2].right_line, nil)
  eq(pairs[2].right_type, "filler")
  eq(pairs[3].left_line, "del 3")
  eq(pairs[3].left_type, "delete")
  eq(pairs[3].right_type, "filler")
end

T["pair_change_run"]["extra additions become filler+add"] = function()
  local pairs = hunk.pair_change_run({ "del 1" }, { 1 }, { "add 1", "add 2", "add 3" }, { 1, 2, 3 })
  eq(#pairs, 3)
  eq(pairs[1].left_type, "change")
  eq(pairs[1].right_type, "change")
  eq(pairs[2].left_line, nil)
  eq(pairs[2].left_type, "filler")
  eq(pairs[2].right_line, "add 2")
  eq(pairs[2].right_type, "add")
  eq(pairs[3].right_line, "add 3")
  eq(pairs[3].right_type, "add")
end

T["pair_change_run"]["pure additions (no deletions)"] = function()
  local pairs = hunk.pair_change_run({}, {}, { "new 1", "new 2" }, { 5, 6 })
  eq(#pairs, 2)
  eq(pairs[1].left_type, "filler")
  eq(pairs[1].right_type, "add")
  eq(pairs[1].right_lineno, 5)
  eq(pairs[2].right_type, "add")
  eq(pairs[2].right_lineno, 6)
end

T["pair_change_run"]["pure deletions (no additions)"] = function()
  local pairs = hunk.pair_change_run({ "old 1", "old 2" }, { 5, 6 }, {}, {})
  eq(#pairs, 2)
  eq(pairs[1].left_type, "delete")
  eq(pairs[1].right_type, "filler")
  eq(pairs[1].left_lineno, 5)
  eq(pairs[2].left_type, "delete")
  eq(pairs[2].left_lineno, 6)
end

-- =============================================================================
-- transform_hunk_to_side_by_side
-- =============================================================================

T["transform_hunk_to_side_by_side"] = MiniTest.new_set()

T["transform_hunk_to_side_by_side"]["handles context lines"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    " line 1",
    " line 2",
  }, 1, 1)
  eq(#pairs, 2)
  eq(pairs[1].left_line, "line 1")
  eq(pairs[1].right_line, "line 1")
  eq(pairs[1].left_type, "context")
  eq(pairs[1].right_type, "context")
  eq(pairs[1].left_lineno, 1)
  eq(pairs[1].right_lineno, 1)
  eq(pairs[2].left_lineno, 2)
  eq(pairs[2].right_lineno, 2)
end

T["transform_hunk_to_side_by_side"]["handles pure additions"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    " context",
    "+added 1",
    "+added 2",
    " more context",
  }, 10, 10)
  eq(#pairs, 4)
  -- context
  eq(pairs[1].left_type, "context")
  eq(pairs[1].left_lineno, 10)
  eq(pairs[1].right_lineno, 10)
  -- additions
  eq(pairs[2].left_type, "filler")
  eq(pairs[2].right_type, "add")
  eq(pairs[2].right_line, "added 1")
  eq(pairs[2].right_lineno, 11)
  eq(pairs[3].right_type, "add")
  eq(pairs[3].right_line, "added 2")
  eq(pairs[3].right_lineno, 12)
  -- context after
  eq(pairs[4].left_type, "context")
  eq(pairs[4].left_lineno, 11)
  eq(pairs[4].right_lineno, 13)
end

T["transform_hunk_to_side_by_side"]["handles pure deletions"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    " context",
    "-deleted 1",
    "-deleted 2",
    " more context",
  }, 5, 5)
  eq(#pairs, 4)
  eq(pairs[1].left_type, "context")
  eq(pairs[2].left_type, "delete")
  eq(pairs[2].left_line, "deleted 1")
  eq(pairs[2].right_type, "filler")
  eq(pairs[3].left_type, "delete")
  eq(pairs[3].left_line, "deleted 2")
  eq(pairs[4].left_type, "context")
  eq(pairs[4].left_lineno, 8)
  eq(pairs[4].right_lineno, 6)
end

T["transform_hunk_to_side_by_side"]["handles mixed changes"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    "-old line",
    "+new line",
  }, 1, 1)
  eq(#pairs, 1)
  eq(pairs[1].left_line, "old line")
  eq(pairs[1].right_line, "new line")
  eq(pairs[1].left_type, "change")
  eq(pairs[1].right_type, "change")
end

T["transform_hunk_to_side_by_side"]["handles multi-line replacement"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    "-old 1",
    "-old 2",
    "+new 1",
    "+new 2",
    "+new 3",
  }, 1, 1)
  eq(#pairs, 3)
  -- Paired as change
  eq(pairs[1].left_type, "change")
  eq(pairs[1].right_type, "change")
  eq(pairs[2].left_type, "change")
  eq(pairs[2].right_type, "change")
  -- Extra addition
  eq(pairs[3].left_type, "filler")
  eq(pairs[3].right_type, "add")
  eq(pairs[3].right_line, "new 3")
end

T["transform_hunk_to_side_by_side"]["handles no-newline-at-EOF marker"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    "-old line",
    "\\ No newline at end of file",
    "+new line",
    "\\ No newline at end of file",
  }, 1, 1)
  eq(#pairs, 1)
  eq(pairs[1].left_type, "change")
  eq(pairs[1].right_type, "change")
  eq(pairs[1].left_line, "old line")
  eq(pairs[1].right_line, "new line")
end

T["transform_hunk_to_side_by_side"]["context between changes flushes runs"] = function()
  local pairs = hunk.transform_hunk_to_side_by_side({
    "-del 1",
    " context",
    "+add 1",
  }, 1, 1)
  eq(#pairs, 3)
  -- First run: single deletion
  eq(pairs[1].left_type, "delete")
  eq(pairs[1].right_type, "filler")
  -- Context
  eq(pairs[2].left_type, "context")
  -- Second run: single addition
  eq(pairs[3].left_type, "filler")
  eq(pairs[3].right_type, "add")
end

-- =============================================================================
-- detect_file_status
-- =============================================================================

T["detect_file_status"] = MiniTest.new_set()

T["detect_file_status"]["detects added files"] = function()
  eq(hunk.detect_file_status("/dev/null", "new_file.lua"), "A")
  eq(hunk.detect_file_status("", "new_file.lua"), "A")
end

T["detect_file_status"]["detects deleted files"] = function()
  eq(hunk.detect_file_status("old_file.lua", "/dev/null"), "D")
  eq(hunk.detect_file_status("old_file.lua", ""), "D")
end

T["detect_file_status"]["detects renamed files"] = function()
  eq(hunk.detect_file_status("old_name.lua", "new_name.lua"), "R")
end

T["detect_file_status"]["detects modified files"] = function()
  eq(hunk.detect_file_status("file.lua", "file.lua"), "M")
end

-- =============================================================================
-- parse_unified_diff — full integration
-- =============================================================================

T["parse_unified_diff"] = MiniTest.new_set()

T["parse_unified_diff"]["parses single file modification"] = function()
  local lines = {
    "diff --git a/src/auth.lua b/src/auth.lua",
    "index abc1234..def5678 100644",
    "--- a/src/auth.lua",
    "+++ b/src/auth.lua",
    "@@ -1,3 +1,4 @@",
    " local M = {}",
    "-function M.login()",
    "+function M.login(user)",
    "+  validate(user)",
    " end",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].old_path, "src/auth.lua")
  eq(fps[1].new_path, "src/auth.lua")
  eq(fps[1].status, "M")
  eq(fps[1].is_binary, false)
  eq(#fps[1].hunks, 1)

  local h = fps[1].hunks[1]
  eq(h.header.old_start, 1)
  eq(h.header.old_count, 3)
  eq(h.header.new_start, 1)
  eq(h.header.new_count, 4)

  -- Side-by-side pairs
  local p = h.pairs
  -- context: local M = {}
  eq(p[1].left_type, "context")
  eq(p[1].left_line, "local M = {}")
  -- change: login() -> login(user)
  eq(p[2].left_type, "change")
  eq(p[2].left_line, "function M.login()")
  eq(p[2].right_line, "function M.login(user)")
  -- addition: validate(user) (filler on left)
  eq(p[3].left_type, "filler")
  eq(p[3].right_type, "add")
  eq(p[3].right_line, "  validate(user)")
  -- context: end
  eq(p[4].left_type, "context")
end

T["parse_unified_diff"]["parses new file (added)"] = function()
  local lines = {
    "diff --git a/new.lua b/new.lua",
    "new file mode 100644",
    "index 0000000..abc1234",
    "--- /dev/null",
    "+++ b/new.lua",
    "@@ -0,0 +1,2 @@",
    "+line 1",
    "+line 2",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].status, "A")
  eq(fps[1].additions, 2)
  eq(fps[1].deletions, 0)
  eq(#fps[1].hunks, 1)
  eq(#fps[1].hunks[1].pairs, 2)
  eq(fps[1].hunks[1].pairs[1].right_type, "add")
  eq(fps[1].hunks[1].pairs[1].left_type, "filler")
end

T["parse_unified_diff"]["parses deleted file"] = function()
  local lines = {
    "diff --git a/old.lua b/old.lua",
    "deleted file mode 100644",
    "index abc1234..0000000",
    "--- a/old.lua",
    "+++ /dev/null",
    "@@ -1,2 +0,0 @@",
    "-line 1",
    "-line 2",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].status, "D")
  eq(fps[1].additions, 0)
  eq(fps[1].deletions, 2)
end

T["parse_unified_diff"]["parses renamed file"] = function()
  local lines = {
    "diff --git a/old_name.lua b/new_name.lua",
    "similarity index 95%",
    "rename from old_name.lua",
    "rename to new_name.lua",
    "index abc1234..def5678 100644",
    "--- a/old_name.lua",
    "+++ b/new_name.lua",
    "@@ -1,2 +1,2 @@",
    "-old content",
    "+new content",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].status, "R")
  eq(fps[1].old_path, "old_name.lua")
  eq(fps[1].new_path, "new_name.lua")
end

T["parse_unified_diff"]["parses multiple files"] = function()
  local lines = {
    "diff --git a/file1.lua b/file1.lua",
    "index abc..def 100644",
    "--- a/file1.lua",
    "+++ b/file1.lua",
    "@@ -1,1 +1,1 @@",
    "-old",
    "+new",
    "diff --git a/file2.lua b/file2.lua",
    "index 111..222 100644",
    "--- a/file2.lua",
    "+++ b/file2.lua",
    "@@ -1,1 +1,2 @@",
    " kept",
    "+added",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 2)
  eq(fps[1].new_path, "file1.lua")
  eq(fps[2].new_path, "file2.lua")
  eq(fps[1].additions, 1)
  eq(fps[1].deletions, 1)
  eq(fps[2].additions, 1)
  eq(fps[2].deletions, 0)
end

T["parse_unified_diff"]["parses multiple hunks in one file"] = function()
  local lines = {
    "diff --git a/big.lua b/big.lua",
    "index abc..def 100644",
    "--- a/big.lua",
    "+++ b/big.lua",
    "@@ -1,3 +1,3 @@",
    " line 1",
    "-old line 2",
    "+new line 2",
    " line 3",
    "@@ -10,3 +10,4 @@",
    " line 10",
    " line 11",
    "+inserted",
    " line 12",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(#fps[1].hunks, 2)
  eq(fps[1].hunks[1].header.old_start, 1)
  eq(fps[1].hunks[2].header.old_start, 10)
  eq(#fps[1].hunks[1].pairs, 3) -- context + change + context
  eq(#fps[1].hunks[2].pairs, 4) -- context + context + add + context
end

T["parse_unified_diff"]["handles binary files"] = function()
  local lines = {
    "diff --git a/image.png b/image.png",
    "index abc..def 100644",
    "Binary files a/image.png and b/image.png differ",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].is_binary, true)
  eq(#fps[1].hunks, 0)
end

T["parse_unified_diff"]["handles empty diff"] = function()
  local fps = hunk.parse_unified_diff({})
  eq(#fps, 0)
end

T["parse_unified_diff"]["counts additions and deletions correctly"] = function()
  local lines = {
    "diff --git a/file.lua b/file.lua",
    "--- a/file.lua",
    "+++ b/file.lua",
    "@@ -1,4 +1,5 @@",
    " context",
    "-deleted 1",
    "-deleted 2",
    "+added 1",
    "+added 2",
    "+added 3",
    " end",
  }
  local fps = hunk.parse_unified_diff(lines)
  -- 2 paired changes + 1 pure addition = 3 additions, 2 deletions
  eq(fps[1].additions, 3)
  eq(fps[1].deletions, 2)
end

T["parse_unified_diff"]["handles file with only context (mode change)"] = function()
  -- Sometimes git shows a diff header but no hunks (e.g., mode changes)
  local lines = {
    "diff --git a/script.sh b/script.sh",
    "old mode 100644",
    "new mode 100755",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].status, "M")
  eq(#fps[1].hunks, 0)
end

T["parse_unified_diff"]["deleted Lua comment lines (--- prefix) are not swallowed"] = function()
  -- Regression: deleted lines starting with "-- " produce diff lines like "--- comment"
  -- which matched the file header pattern "^--- " and got silently dropped.
  local lines = {
    "diff --git a/init.lua b/init.lua",
    "--- a/init.lua",
    "+++ b/init.lua",
    "@@ -1,5 +1,3 @@",
    " local M = {}",
    "--- This is a comment",
    "--- Another comment",
    " return M",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(fps[1].status, "M")
  eq(#fps[1].hunks, 1)

  local pairs = fps[1].hunks[1].pairs
  -- Should have 4 lines: context, 2 deletions, context
  eq(#pairs, 4)
  eq(pairs[1].left_type, "context")
  eq(pairs[1].left_line, "local M = {}")
  eq(pairs[2].left_type, "delete")
  eq(pairs[2].left_line, "-- This is a comment")
  eq(pairs[2].right_type, "filler")
  eq(pairs[3].left_type, "delete")
  eq(pairs[3].left_line, "-- Another comment")
  eq(pairs[3].right_type, "filler")
  eq(pairs[4].left_type, "context")
  eq(pairs[4].left_line, "return M")
end

T["parse_unified_diff"]["added lines with +++ prefix are not swallowed"] = function()
  -- Same issue: added lines starting with "++" produce "+++ ..." matching the header pattern.
  local lines = {
    "diff --git a/file.lua b/file.lua",
    "--- a/file.lua",
    "+++ b/file.lua",
    "@@ -1,2 +1,4 @@",
    " local M = {}",
    "+++ This is a weird line",
    "+++ Another one",
    " return M",
  }
  local fps = hunk.parse_unified_diff(lines)
  eq(#fps, 1)
  eq(#fps[1].hunks, 1)

  local pairs = fps[1].hunks[1].pairs
  eq(#pairs, 4)
  eq(pairs[1].right_type, "context")
  eq(pairs[2].right_type, "add")
  eq(pairs[2].right_line, "++ This is a weird line")
  eq(pairs[3].right_type, "add")
  eq(pairs[3].right_line, "++ Another one")
  eq(pairs[4].right_type, "context")
end

return T
