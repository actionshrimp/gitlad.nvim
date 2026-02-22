-- Tests for gitlad.ui.views.diff.inline module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local inline = require("gitlad.ui.views.diff.inline")

-- =============================================================================
-- _tokenize tests
-- =============================================================================

T["tokenize"] = MiniTest.new_set()

T["tokenize"]["simple words"] = function()
  local tokens = inline._tokenize("hello world")
  eq(tokens, { "hello", " ", "world" })
end

T["tokenize"]["code with parens"] = function()
  local tokens = inline._tokenize("function foo(x)")
  eq(tokens, { "function", " ", "foo", "(", "x", ")" })
end

T["tokenize"]["assignment with spaces"] = function()
  local tokens = inline._tokenize("x = 10")
  eq(tokens, { "x", " ", "=", " ", "10" })
end

T["tokenize"]["empty string"] = function()
  local tokens = inline._tokenize("")
  eq(tokens, {})
end

T["tokenize"]["only whitespace"] = function()
  local tokens = inline._tokenize(" ")
  eq(tokens, { " " })
end

T["tokenize"]["multiple spaces preserved"] = function()
  local tokens = inline._tokenize("a  b")
  eq(tokens, { "a", "  ", "b" })
end

T["tokenize"]["underscores part of words"] = function()
  local tokens = inline._tokenize("my_var = other_var")
  eq(tokens, { "my_var", " ", "=", " ", "other_var" })
end

T["tokenize"]["consecutive punctuation grouped"] = function()
  local tokens = inline._tokenize("a->b")
  eq(tokens, { "a", "->", "b" })
end

T["tokenize"]["mixed symbols and words"] = function()
  local tokens = inline._tokenize("if (x == 10)")
  eq(tokens, { "if", " ", "(", "x", " ", "==", " ", "10", ")" })
end

T["tokenize"]["tabs as whitespace"] = function()
  local tokens = inline._tokenize("a\tb")
  eq(tokens, { "a", "\t", "b" })
end

T["tokenize"]["digits are word characters"] = function()
  local tokens = inline._tokenize("foo123")
  eq(tokens, { "foo123" })
end

T["tokenize"]["single character"] = function()
  local tokens = inline._tokenize("x")
  eq(tokens, { "x" })
end

T["tokenize"]["single punctuation"] = function()
  local tokens = inline._tokenize("(")
  eq(tokens, { "(" })
end

-- =============================================================================
-- _lcs_tokens tests
-- =============================================================================

T["lcs_tokens"] = MiniTest.new_set()

T["lcs_tokens"]["identical sequences"] = function()
  local lcs = inline._lcs_tokens({ "a", "b", "c" }, { "a", "b", "c" })
  eq(lcs[1], 1)
  eq(lcs[2], 2)
  eq(lcs[3], 3)
end

T["lcs_tokens"]["completely different"] = function()
  local lcs = inline._lcs_tokens({ "a", "b" }, { "c", "d" })
  -- No matches
  eq(next(lcs), nil)
end

T["lcs_tokens"]["empty old"] = function()
  local lcs = inline._lcs_tokens({}, { "a", "b" })
  eq(next(lcs), nil)
end

T["lcs_tokens"]["empty new"] = function()
  local lcs = inline._lcs_tokens({ "a", "b" }, {})
  eq(next(lcs), nil)
end

T["lcs_tokens"]["both empty"] = function()
  local lcs = inline._lcs_tokens({}, {})
  eq(next(lcs), nil)
end

T["lcs_tokens"]["partial match"] = function()
  local lcs = inline._lcs_tokens({ "a", "b", "c" }, { "a", "x", "c" })
  eq(lcs[1], 1)
  eq(lcs[2], nil)
  eq(lcs[3], 3)
end

T["lcs_tokens"]["insertion in new"] = function()
  local lcs = inline._lcs_tokens({ "a", "b" }, { "a", "x", "b" })
  eq(lcs[1], 1)
  eq(lcs[2], 3)
end

T["lcs_tokens"]["deletion from old"] = function()
  local lcs = inline._lcs_tokens({ "a", "x", "b" }, { "a", "b" })
  eq(lcs[1], 1)
  eq(lcs[2], nil)
  eq(lcs[3], 2)
end

-- =============================================================================
-- compute_inline_diff tests
-- =============================================================================

T["compute_inline_diff"] = MiniTest.new_set()

T["compute_inline_diff"]["identical lines return empty ranges"] = function()
  local result = inline.compute_inline_diff("hello world", "hello world")
  eq(result.old_ranges, {})
  eq(result.new_ranges, {})
end

T["compute_inline_diff"]["single word change"] = function()
  local result = inline.compute_inline_diff("return old", "return new")
  -- "return" and " " match, "old"/"new" differ
  eq(#result.old_ranges, 1)
  eq(#result.new_ranges, 1)
  -- "return " = 7 chars, then "old" starts at col 7
  eq(result.old_ranges[1].col_start, 7)
  eq(result.old_ranges[1].col_end, 10)
  -- "return " = 7 chars, then "new" starts at col 7
  eq(result.new_ranges[1].col_start, 7)
  eq(result.new_ranges[1].col_end, 10)
end

T["compute_inline_diff"]["added word"] = function()
  local result = inline.compute_inline_diff("a b", "a c b")
  -- Old: "a" " " "b" - all in LCS
  eq(#result.old_ranges, 0)
  -- New: "a" " " "c" " " "b"
  -- LCS matches: a(1->1), " "(2->4), b(3->5)
  -- Non-LCS in new: " "(idx 2, col 1..2) and "c"(idx 3, col 2..3), merged to col 1..3
  eq(#result.new_ranges, 1)
  eq(result.new_ranges[1].col_start, 1)
  eq(result.new_ranges[1].col_end, 3)
end

T["compute_inline_diff"]["deleted word"] = function()
  local result = inline.compute_inline_diff("a b c", "a c")
  -- Old: "a" " " "b" " " "c"
  -- New: "a" " " "c"
  -- LCS matches: a(1->1), " "(4->2), c(5->3)
  -- Non-LCS in old: " "(idx 2, col 1..2) and "b"(idx 3, col 2..3), merged to col 1..3
  eq(#result.old_ranges, 1)
  eq(result.old_ranges[1].col_start, 1)
  eq(result.old_ranges[1].col_end, 3)
  -- New: "a" " " "c" - all in LCS
  eq(#result.new_ranges, 0)
end

T["compute_inline_diff"]["completely different lines"] = function()
  local result = inline.compute_inline_diff("abc", "xyz")
  eq(#result.old_ranges, 1)
  eq(result.old_ranges[1].col_start, 0)
  eq(result.old_ranges[1].col_end, 3)
  eq(#result.new_ranges, 1)
  eq(result.new_ranges[1].col_start, 0)
  eq(result.new_ranges[1].col_end, 3)
end

T["compute_inline_diff"]["empty old line"] = function()
  local result = inline.compute_inline_diff("", "hello")
  eq(#result.old_ranges, 0)
  eq(#result.new_ranges, 1)
  eq(result.new_ranges[1].col_start, 0)
  eq(result.new_ranges[1].col_end, 5)
end

T["compute_inline_diff"]["empty new line"] = function()
  local result = inline.compute_inline_diff("hello", "")
  eq(#result.old_ranges, 1)
  eq(result.old_ranges[1].col_start, 0)
  eq(result.old_ranges[1].col_end, 5)
  eq(#result.new_ranges, 0)
end

T["compute_inline_diff"]["both empty lines"] = function()
  local result = inline.compute_inline_diff("", "")
  eq(result.old_ranges, {})
  eq(result.new_ranges, {})
end

T["compute_inline_diff"]["symbol change in code"] = function()
  local result = inline.compute_inline_diff("foo(x)", "foo(y)")
  -- "foo" "(" match, "x"/"y" differ, ")" matches
  eq(#result.old_ranges, 1)
  eq(#result.new_ranges, 1)
  -- "foo" (3) + "(" (1) = col 4, "x" at 4..5
  eq(result.old_ranges[1].col_start, 4)
  eq(result.old_ranges[1].col_end, 5)
  eq(result.new_ranges[1].col_start, 4)
  eq(result.new_ranges[1].col_end, 5)
end

T["compute_inline_diff"]["whitespace change"] = function()
  local result = inline.compute_inline_diff("a  b", "a b")
  -- Old tokens: "a" "  " "b"
  -- New tokens: "a" " " "b"
  -- "a" and "b" match, whitespace differs
  eq(#result.old_ranges, 1)
  eq(#result.new_ranges, 1)
  -- "a" (1), then "  " at col 1..3
  eq(result.old_ranges[1].col_start, 1)
  eq(result.old_ranges[1].col_end, 3)
  -- "a" (1), then " " at col 1..2
  eq(result.new_ranges[1].col_start, 1)
  eq(result.new_ranges[1].col_end, 2)
end

T["compute_inline_diff"]["multiple changes"] = function()
  local result = inline.compute_inline_diff("old1 keep old2", "new1 keep new2")
  -- "old1"/"new1" differ, " " matches, "keep" matches, " " matches, "old2"/"new2" differ
  eq(#result.old_ranges, 2)
  eq(#result.new_ranges, 2)
  -- First range: "old1" at col 0..4
  eq(result.old_ranges[1].col_start, 0)
  eq(result.old_ranges[1].col_end, 4)
  -- Second range: "old2" at col 10..14 ("old1" 4 + " " 1 + "keep" 4 + " " 1 = 10)
  eq(result.old_ranges[2].col_start, 10)
  eq(result.old_ranges[2].col_end, 14)
  -- Same positions for new
  eq(result.new_ranges[1].col_start, 0)
  eq(result.new_ranges[1].col_end, 4)
  eq(result.new_ranges[2].col_start, 10)
  eq(result.new_ranges[2].col_end, 14)
end

T["compute_inline_diff"]["operator change"] = function()
  local result = inline.compute_inline_diff("x + y", "x - y")
  -- "x" " " match, "+"/" -" differ, " " "y" match
  eq(#result.old_ranges, 1)
  eq(#result.new_ranges, 1)
  -- "x" (1) + " " (1) = col 2, "+" at 2..3
  eq(result.old_ranges[1].col_start, 2)
  eq(result.old_ranges[1].col_end, 3)
  eq(result.new_ranges[1].col_start, 2)
  eq(result.new_ranges[1].col_end, 3)
end

T["compute_inline_diff"]["leading whitespace difference"] = function()
  local result = inline.compute_inline_diff("  foo", "    foo")
  -- Old tokens: "  " "foo"
  -- New tokens: "    " "foo"
  -- "foo" matches, whitespace differs
  eq(#result.old_ranges, 1)
  eq(#result.new_ranges, 1)
  eq(result.old_ranges[1].col_start, 0)
  eq(result.old_ranges[1].col_end, 2)
  eq(result.new_ranges[1].col_start, 0)
  eq(result.new_ranges[1].col_end, 4)
end

T["compute_inline_diff"]["real code change"] = function()
  local result =
    inline.compute_inline_diff('local x = require("old_module")', 'local x = require("new_module")')
  -- Most tokens match, only "old_module"/"new_module" differ
  eq(#result.old_ranges, 1)
  eq(#result.new_ranges, 1)
end

T["compute_inline_diff"]["adjacent different tokens merge"] = function()
  -- "ab cd" vs "ef gh" - word tokens differ but space matches in LCS
  -- Old tokens: "ab" " " "cd"
  -- New tokens: "ef" " " "gh"
  -- LCS matches the space: " "(2->2)
  -- Two separate ranges on each side (gap at the matching space)
  local result = inline.compute_inline_diff("ab cd", "ef gh")
  eq(#result.old_ranges, 2)
  eq(result.old_ranges[1].col_start, 0)
  eq(result.old_ranges[1].col_end, 2)
  eq(result.old_ranges[2].col_start, 3)
  eq(result.old_ranges[2].col_end, 5)
  eq(#result.new_ranges, 2)
  eq(result.new_ranges[1].col_start, 0)
  eq(result.new_ranges[1].col_end, 2)
  eq(result.new_ranges[2].col_start, 3)
  eq(result.new_ranges[2].col_end, 5)
end

return T
