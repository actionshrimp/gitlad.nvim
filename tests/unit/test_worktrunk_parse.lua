local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["worktrunk.parse"] = MiniTest.new_set()

-- Load fixture lines (path relative to project root)
local function load_fixture_lines()
  local lines = {}
  for line in io.lines("tests/fixtures/wt_list.json") do
    table.insert(lines, line)
  end
  return lines
end

T["worktrunk.parse"]["parse_list returns WorktreeInfo array from JSON array fixture"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(#result, 3)
end

T["worktrunk.parse"]["first entry is main worktree"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(result[1].branch, "main")
  eq(result[1].path, "/home/user/repo/main")
  eq(result[1].is_main, true)
end

T["worktrunk.parse"]["linked entry has working_tree stats"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(result[2].branch, "feature/new-ui")
  eq(result[2].is_main, false)
  eq(result[2].working_tree.staged, true)
  eq(result[2].working_tree.modified, true)
  eq(result[2].working_tree.untracked, true)
end

T["worktrunk.parse"]["linked entry has main ahead/behind"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(result[2].main.ahead, 4)
  eq(result[2].main.behind, 0)
end

T["worktrunk.parse"]["entry with operation_state parses correctly"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(result[3].operation_state, "conflicts")
end

T["worktrunk.parse"]["entry has main_state field"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(result[1].main_state, "is_main")
  eq(result[2].main_state, "ahead")
end

T["worktrunk.parse"]["is_current field is set correctly"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture_lines()
  local result = parse.parse_list(lines)
  eq(result[1].is_current, false)
  eq(result[2].is_current, true)
end

T["worktrunk.parse"]["empty output returns empty array"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({})
  eq(#result, 0)
end

T["worktrunk.parse"]["empty lines return empty array"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({ "", "  ", "" })
  eq(#result, 0)
end

T["worktrunk.parse"]["single-line JSON array parses correctly"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({
    '[{"branch":"main","path":"/repo","kind":"worktree","is_main":true}]',
  })
  eq(#result, 1)
  eq(result[1].branch, "main")
  eq(result[1].is_main, true)
end

T["worktrunk.parse"]["NDJSON fallback: single valid line returns one entry"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({
    '{"branch":"main","path":"/repo","kind":"worktree","is_main":true}',
  })
  eq(#result, 1)
  eq(result[1].branch, "main")
end

T["worktrunk.parse"]["NDJSON fallback: mixed valid and empty lines"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({
    "",
    '{"branch":"main","path":"/repo","kind":"worktree","is_main":true}',
    "",
    '{"branch":"feat","path":"/repo2","kind":"worktree","is_main":false}',
    "",
  })
  eq(#result, 2)
end

return T
