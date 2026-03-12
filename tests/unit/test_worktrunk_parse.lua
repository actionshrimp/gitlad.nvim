local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["worktrunk.parse"] = MiniTest.new_set()

-- Load the fixture file and split into lines (path relative to project root)
local function load_fixture()
  local lines = {}
  for line in io.lines("tests/fixtures/wt_list.json") do
    table.insert(lines, line)
  end
  return lines
end

T["worktrunk.parse"]["parse_list returns WorktreeInfo array from NDJSON fixture"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(#result, 3)
end

T["worktrunk.parse"]["first entry is main worktree"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[1].branch, "main")
  eq(result[1].path, "/home/user/repo/main")
  eq(result[1].kind, "main")
end

T["worktrunk.parse"]["linked entry has working_tree stats"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[2].branch, "feature/new-ui")
  eq(result[2].kind, "linked")
  eq(result[2].working_tree.modified, 2)
  eq(result[2].working_tree.staged, 1)
  eq(result[2].working_tree.untracked, 3)
end

T["worktrunk.parse"]["linked entry has main ahead/behind"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[2].main.ahead, 4)
  eq(result[2].main.behind, 0)
end

T["worktrunk.parse"]["entry with ci status parses correctly"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[2].ci.status, "passing")
  eq(result[2].ci.stale, false)
end

T["worktrunk.parse"]["entry with operation_state parses correctly"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[3].operation_state, "conflicts")
end

T["worktrunk.parse"]["entry with stale ci and failing status"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[3].ci.status, "failing")
  eq(result[3].ci.stale, true)
end

T["worktrunk.parse"]["main entry has null ci (parsed as nil)"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[1].ci, vim.NIL)
end

T["worktrunk.parse"]["main entry has null main field (parsed as nil)"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local lines = load_fixture()
  local result = parse.parse_list(lines)
  eq(result[1].main, vim.NIL)
end

T["worktrunk.parse"]["empty lines are skipped"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({ "", "  ", "" })
  eq(#result, 0)
end

T["worktrunk.parse"]["single valid line returns one entry"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({
    '{"branch":"main","path":"/repo","kind":"main"}',
  })
  eq(#result, 1)
  eq(result[1].branch, "main")
end

T["worktrunk.parse"]["mixed valid and empty lines"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.parse_list({
    "",
    '{"branch":"main","path":"/repo","kind":"main"}',
    "",
    '{"branch":"feat","path":"/repo2","kind":"linked"}',
    "",
  })
  eq(#result, 2)
end

return T
