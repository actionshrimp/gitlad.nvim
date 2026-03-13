local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["worktrunk.parse.merge"] = MiniTest.new_set()

local function make_entry(branch, path)
  return {
    branch = branch,
    path = path,
    head = "abc123",
    is_main = false,
    is_bare = false,
    locked = false,
    prunable = false,
  }
end

local function make_info(branch, opts)
  opts = opts or {}
  return {
    branch = branch,
    path = opts.path or ("/repo/" .. branch),
    kind = "worktree",
    is_main = opts.is_main or false,
    is_current = opts.is_current or false,
    working_tree = opts.working_tree,
    main = opts.main,
    main_state = opts.main_state,
    operation_state = opts.operation_state,
  }
end

T["worktrunk.parse.merge"]["attaches wt field to matching entry"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = { make_entry("feature/foo", "/repo/feature-foo") }
  local infos = { make_info("feature/foo", { main = { ahead = 3, behind = 0 } }) }

  parse.merge(worktrees, infos)

  local wt = worktrees[1].wt
  MiniTest.expect.no_equality(wt, nil)
  eq(wt.main.ahead, 3)
  eq(wt.main.behind, 0)
end

T["worktrunk.parse.merge"]["does not attach wt field when no match"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = { make_entry("feature/foo", "/repo/feature-foo") }
  local infos = { make_info("other/branch") }

  parse.merge(worktrees, infos)

  eq(worktrees[1].wt, nil)
end

T["worktrunk.parse.merge"]["handles empty worktrees"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.merge({}, { make_info("main") })
  eq(#result, 0)
end

T["worktrunk.parse.merge"]["handles empty infos"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = { make_entry("main", "/repo") }
  local result = parse.merge(worktrees, {})
  eq(result[1].wt, nil)
end

T["worktrunk.parse.merge"]["merges multiple entries correctly"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = {
    make_entry("main", "/repo/main"),
    make_entry("feature/a", "/repo/feature-a"),
    make_entry("feature/b", "/repo/feature-b"),
  }
  local infos = {
    make_info("main", { is_main = true }),
    make_info("feature/a", { main = { ahead = 1, behind = 0 } }),
    -- feature/b intentionally missing from infos
  }

  parse.merge(worktrees, infos)

  MiniTest.expect.no_equality(worktrees[1].wt, nil)
  MiniTest.expect.no_equality(worktrees[2].wt, nil)
  eq(worktrees[3].wt, nil)
  eq(worktrees[2].wt.main.ahead, 1)
end

T["worktrunk.parse.merge"]["skips entries with nil branch (detached HEAD)"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local entry = {
    path = "/repo",
    head = "abc123",
    branch = nil,
    is_main = false,
    is_bare = false,
    locked = false,
    prunable = false,
  }
  local infos = { make_info("main") }

  parse.merge({ entry }, infos)

  eq(entry.wt, nil)
end

T["worktrunk.parse.merge"]["working_tree fields are accessible"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = { make_entry("feature/x", "/repo/x") }
  local infos = {
    make_info("feature/x", {
      working_tree = { staged = true, modified = false, untracked = true },
    }),
  }

  parse.merge(worktrees, infos)

  eq(worktrees[1].wt.working_tree.staged, true)
  eq(worktrees[1].wt.working_tree.modified, false)
  eq(worktrees[1].wt.working_tree.untracked, true)
end

T["worktrunk.parse.merge"]["operation_state is accessible"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = { make_entry("bugfix/x", "/repo/x") }
  local infos = { make_info("bugfix/x", { operation_state = "conflicts" }) }

  parse.merge(worktrees, infos)

  eq(worktrees[1].wt.operation_state, "conflicts")
end

T["worktrunk.parse.merge"]["returns the worktrees table"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local worktrees = { make_entry("main", "/repo") }
  local result = parse.merge(worktrees, {})
  eq(result, worktrees)
end

-- ============================================================
-- status_str tests
-- ============================================================

T["worktrunk.parse.status_str"] = MiniTest.new_set()

T["worktrunk.parse.status_str"]["nil returns empty string"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str(nil), "")
end

T["worktrunk.parse.status_str"]["uses wt symbols when present"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str({ symbols = "↑3", main_state = "ahead" }), "↑3")
end

T["worktrunk.parse.status_str"]["falls back to main_state empty"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str({ main_state = "empty" }), "_")
end

T["worktrunk.parse.status_str"]["falls back to main_state integrated"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str({ main_state = "integrated" }), "=")
end

T["worktrunk.parse.status_str"]["falls back to main ahead/behind"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str({ main_state = "ahead", main = { ahead = 3, behind = 0 } }), "↑3")
  eq(parse.status_str({ main_state = "ahead", main = { ahead = 3, behind = 2 } }), "↑3↓2")
  eq(parse.status_str({ main_state = "behind", main = { ahead = 0, behind = 1 } }), "↓1")
end

T["worktrunk.parse.status_str"]["appends dirty indicator"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.status_str({
    symbols = "↑2",
    working_tree = { staged = true, modified = false, untracked = false },
  })
  eq(result, "↑2 ●")
end

T["worktrunk.parse.status_str"]["appends conflict indicator"] = function()
  local parse = require("gitlad.worktrunk.parse")
  local result = parse.status_str({
    main_state = "ahead",
    main = { ahead = 1, behind = 0 },
    operation_state = "conflicts",
  })
  eq(result, "↑1 [C]")
end

T["worktrunk.parse.status_str"]["is_main with clean tree returns empty"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str({ main_state = "is_main", is_main = true }), "")
end

T["worktrunk.parse.status_str"]["symbols empty string falls back to structured"] = function()
  local parse = require("gitlad.worktrunk.parse")
  eq(parse.status_str({ symbols = "", main_state = "empty" }), "_")
end

return T
