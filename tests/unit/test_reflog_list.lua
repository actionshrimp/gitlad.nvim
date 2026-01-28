---@diagnostic disable: undefined-global
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["reflog_list"] = MiniTest.new_set()

local function make_entry(hash, selector, action_type, subject)
  return {
    hash = hash,
    author = "Test Author",
    selector = selector,
    subject = subject,
    action_type = action_type,
  }
end

T["reflog_list"]["render returns lines with correct format"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234def", "HEAD@{0}", "commit", "commit: Initial commit"),
    make_entry("def5678ghi", "HEAD@{1}", "checkout", "checkout: moving from main to feature"),
  }

  local result = reflog_list.render(entries, { indent = 2 })

  eq(#result.lines, 2)
  -- First line should contain hash, selector, action type, and message
  assert(result.lines[1]:find("abc1234"), "Should contain hash")
  assert(result.lines[1]:find("HEAD@{0}"), "Should contain selector")
  assert(result.lines[1]:find("commit"), "Should contain action type")
  assert(result.lines[1]:find("Initial commit"), "Should contain message")

  -- Second line
  assert(result.lines[2]:find("def5678"), "Should contain hash")
  assert(result.lines[2]:find("HEAD@{1}"), "Should contain selector")
  assert(result.lines[2]:find("checkout"), "Should contain action type")
  assert(result.lines[2]:find("moving from main to feature"), "Should contain message")
end

T["reflog_list"]["render returns line_info with correct metadata"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234def", "HEAD@{0}", "commit", "commit: Initial commit"),
  }

  local result = reflog_list.render(entries, { section = "test_section" })

  eq(#result.lines, 1)
  local info = result.line_info[1]
  eq(info.type, "reflog")
  eq(info.hash, "abc1234def")
  eq(info.section, "test_section")
  eq(info.entry.selector, "HEAD@{0}")
  eq(info.entry.action_type, "commit")

  -- Column positions should be tracked
  assert(type(info.selector_start_col) == "number", "selector_start_col should be number")
  assert(type(info.selector_end_col) == "number", "selector_end_col should be number")
  assert(type(info.action_start_col) == "number", "action_start_col should be number")
  assert(type(info.action_end_col) == "number", "action_end_col should be number")
end

T["reflog_list"]["render tracks entry_ranges"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234", "HEAD@{0}", "commit", "commit: First"),
    make_entry("def5678", "HEAD@{1}", "checkout", "checkout: Second"),
    make_entry("ghi9012", "HEAD@{2}", "reset", "reset: Third"),
  }

  local result = reflog_list.render(entries)

  -- Each entry should have its range tracked by selector
  eq(result.entry_ranges["HEAD@{0}"].start, 1)
  eq(result.entry_ranges["HEAD@{0}"].end_line, 1)
  eq(result.entry_ranges["HEAD@{1}"].start, 2)
  eq(result.entry_ranges["HEAD@{1}"].end_line, 2)
  eq(result.entry_ranges["HEAD@{2}"].start, 3)
  eq(result.entry_ranges["HEAD@{2}"].end_line, 3)
end

T["reflog_list"]["render respects hash_length option"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234def5678", "HEAD@{0}", "commit", "commit: Test"),
  }

  -- Default hash length is 7
  local result = reflog_list.render(entries)
  assert(result.lines[1]:find("abc1234"), "Should contain 7 char hash")
  assert(not result.lines[1]:find("abc1234d"), "Should not contain 8 char hash")

  -- Custom hash length
  result = reflog_list.render(entries, { hash_length = 10 })
  assert(result.lines[1]:find("abc1234def"), "Should contain 10 char hash")
end

T["reflog_list"]["render respects indent option"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234", "HEAD@{0}", "commit", "commit: Test"),
  }

  -- Indent of 4
  local result = reflog_list.render(entries, { indent = 4 })
  assert(result.lines[1]:match("^    "), "Should have 4 space indent")

  -- Indent of 0
  result = reflog_list.render(entries, { indent = 0 })
  assert(result.lines[1]:match("^abc1234"), "Should have no indent")
end

T["reflog_list"]["render handles empty input"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local result = reflog_list.render({})

  eq(#result.lines, 0)
  eq(vim.tbl_count(result.line_info), 0)
  eq(vim.tbl_count(result.entry_ranges), 0)
end

T["reflog_list"]["render extracts message after colon from subject"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234", "HEAD@{0}", "commit", "commit: The actual message"),
    make_entry("def5678", "HEAD@{1}", "checkout", "checkout: moving from main to feature"),
  }

  local result = reflog_list.render(entries)

  -- Message should be extracted (without the "commit: " prefix)
  assert(result.lines[1]:find("The actual message"), "Should contain message")
  -- The line might still contain "commit" as the action type column, but not "commit: The"
  assert(not result.lines[1]:find("commit: The"), "Should not contain prefix with message")

  assert(result.lines[2]:find("moving from main to feature"), "Should contain message")
end

T["reflog_list"]["get_entries_in_range returns unique entries"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234", "HEAD@{0}", "commit", "commit: First"),
    make_entry("def5678", "HEAD@{1}", "checkout", "checkout: Second"),
    make_entry("ghi9012", "HEAD@{2}", "reset", "reset: Third"),
  }

  local result = reflog_list.render(entries)

  -- Get entries in range 1-2
  local selected = reflog_list.get_entries_in_range(result.line_info, 1, 2)
  eq(#selected, 2)
  eq(selected[1].hash, "abc1234")
  eq(selected[2].hash, "def5678")

  -- Get single entry
  selected = reflog_list.get_entries_in_range(result.line_info, 2, 2)
  eq(#selected, 1)
  eq(selected[1].hash, "def5678")
end

T["reflog_list"]["get_entries_in_range handles empty range"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local result = reflog_list.render({})
  local selected = reflog_list.get_entries_in_range(result.line_info, 1, 10)
  eq(#selected, 0)
end

T["reflog_list"]["render pads action type to fixed width"] = function()
  local reflog_list = require("gitlad.ui.components.reflog_list")

  local entries = {
    make_entry("abc1234", "HEAD@{0}", "commit", "commit: Test"),
    make_entry("def5678", "HEAD@{1}", "cherry-pick", "cherry-pick: Test"),
  }

  local result = reflog_list.render(entries, { action_type_width = 14 })

  -- Both action types should result in same column alignment for message
  local info1 = result.line_info[1]
  local info2 = result.line_info[2]

  -- Action columns should end at same position (due to padding)
  eq(info1.action_end_col, info2.action_end_col)
end

return T
