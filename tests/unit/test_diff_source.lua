-- Tests for gitlad.ui.views.diff.source module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local source = require("gitlad.ui.views.diff.source")

-- =============================================================================
-- _build_args
-- =============================================================================

T["_build_args"] = MiniTest.new_set()

T["_build_args"]["builds staged diff args"] = function()
  local args = source._build_args("staged")
  eq(args, { "diff", "--cached" })
end

T["_build_args"]["builds unstaged diff args"] = function()
  local args = source._build_args("unstaged")
  eq(args, { "diff" })
end

T["_build_args"]["builds worktree diff args"] = function()
  local args = source._build_args("worktree")
  eq(args, { "diff", "HEAD" })
end

T["_build_args"]["builds commit diff args with ref"] = function()
  local args = source._build_args("commit", "abc1234")
  eq(args, { "show", "--format=", "abc1234" })
end

T["_build_args"]["builds commit diff args with full hash"] = function()
  local args = source._build_args("commit", "abc1234def5678abc1234def5678abc1234def567")
  eq(args, { "show", "--format=", "abc1234def5678abc1234def5678abc1234def567" })
end

T["_build_args"]["builds range diff args"] = function()
  local args = source._build_args("range", "main..HEAD")
  eq(args, { "diff", "main..HEAD" })
end

T["_build_args"]["builds range diff args with three-dot range"] = function()
  local args = source._build_args("range", "main...feature")
  eq(args, { "diff", "main...feature" })
end

T["_build_args"]["builds stash diff args"] = function()
  local args = source._build_args("stash", "stash@{0}")
  eq(args, { "stash", "show", "-p", "stash@{0}" })
end

T["_build_args"]["builds stash diff args with numbered ref"] = function()
  local args = source._build_args("stash", "stash@{3}")
  eq(args, { "stash", "show", "-p", "stash@{3}" })
end

T["_build_args"]["errors on commit without ref"] = function()
  local ok, err = pcall(source._build_args, "commit", nil)
  eq(ok, false)
  expect.equality(err:find("commit source requires a ref") ~= nil, true)
end

T["_build_args"]["errors on range without range expression"] = function()
  local ok, err = pcall(source._build_args, "range", nil)
  eq(ok, false)
  expect.equality(err:find("range source requires a range expression") ~= nil, true)
end

T["_build_args"]["errors on stash without stash ref"] = function()
  local ok, err = pcall(source._build_args, "stash", nil)
  eq(ok, false)
  expect.equality(err:find("stash source requires a stash ref") ~= nil, true)
end

T["_build_args"]["errors on unknown source type"] = function()
  local ok, err = pcall(source._build_args, "invalid_type")
  eq(ok, false)
  expect.equality(err:find("Unknown diff source type") ~= nil, true)
end

-- =============================================================================
-- _format_file_count
-- =============================================================================

T["_format_file_count"] = MiniTest.new_set()

T["_format_file_count"]["returns '(empty)' for no files"] = function()
  eq(source._format_file_count({}), " (empty)")
end

T["_format_file_count"]["returns '(1 file)' for single file"] = function()
  local files = { { new_path = "a.lua" } }
  eq(source._format_file_count(files), " (1 file)")
end

T["_format_file_count"]["returns '(N files)' for multiple files"] = function()
  local files = { { new_path = "a.lua" }, { new_path = "b.lua" }, { new_path = "c.lua" } }
  eq(source._format_file_count(files), " (3 files)")
end

-- =============================================================================
-- _build_title
-- =============================================================================

T["_build_title"] = MiniTest.new_set()

T["_build_title"]["builds staged title with file count"] = function()
  local s = { type = "staged" }
  local files = { {}, {}, {} }
  eq(source._build_title(s, files), "Diff staged (3 files)")
end

T["_build_title"]["builds staged title with single file"] = function()
  local s = { type = "staged" }
  local files = { {} }
  eq(source._build_title(s, files), "Diff staged (1 file)")
end

T["_build_title"]["builds staged title with empty diff"] = function()
  local s = { type = "staged" }
  eq(source._build_title(s, {}), "Diff staged (empty)")
end

T["_build_title"]["builds unstaged title"] = function()
  local s = { type = "unstaged" }
  local files = { {}, {} }
  eq(source._build_title(s, files), "Diff unstaged (2 files)")
end

T["_build_title"]["builds worktree title"] = function()
  local s = { type = "worktree" }
  local files = { {} }
  eq(source._build_title(s, files), "Diff worktree (1 file)")
end

T["_build_title"]["builds commit title with short ref"] = function()
  local s = { type = "commit", ref = "abc1234" }
  local files = { {}, {}, {}, {}, {} }
  eq(source._build_title(s, files), "Commit abc1234 (5 files)")
end

T["_build_title"]["truncates long commit ref to 7 chars"] = function()
  local s = { type = "commit", ref = "abc1234def5678901234567890" }
  local files = { {} }
  eq(source._build_title(s, files), "Commit abc1234 (1 file)")
end

T["_build_title"]["builds range title"] = function()
  local s = { type = "range", range = "main..HEAD" }
  local files = { {}, {}, {}, {}, {} }
  eq(source._build_title(s, files), "Diff main..HEAD (5 files)")
end

T["_build_title"]["builds stash title"] = function()
  local s = { type = "stash", ref = "stash@{0}" }
  local files = { {}, {} }
  eq(source._build_title(s, files), "Stash stash@{0} (2 files)")
end

T["_build_title"]["handles missing ref in commit source"] = function()
  local s = { type = "commit" }
  local files = { {} }
  eq(source._build_title(s, files), "Commit unknown (1 file)")
end

T["_build_title"]["handles missing range in range source"] = function()
  local s = { type = "range" }
  local files = { {} }
  eq(source._build_title(s, files), "Diff unknown (1 file)")
end

T["_build_title"]["handles unknown source type"] = function()
  local s = { type = "something_else" }
  local files = { {} }
  eq(source._build_title(s, files), "Diff (1 file)")
end

-- =============================================================================
-- _build_diff_spec
-- =============================================================================

T["_build_diff_spec"] = MiniTest.new_set()

T["_build_diff_spec"]["builds complete DiffSpec for staged source"] = function()
  local s = { type = "staged" }
  local file_pairs = {
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
  local repo_root = "/home/user/project"

  local spec = source._build_diff_spec(s, file_pairs, repo_root)

  eq(spec.source, s)
  eq(spec.file_pairs, file_pairs)
  eq(spec.title, "Diff staged (1 file)")
  eq(spec.repo_root, "/home/user/project")
end

T["_build_diff_spec"]["builds DiffSpec for commit with multiple files"] = function()
  local s = { type = "commit", ref = "abc1234" }
  local file_pairs = {
    { old_path = "a.lua", new_path = "a.lua", status = "M" },
    { old_path = "b.lua", new_path = "b.lua", status = "M" },
    { old_path = "/dev/null", new_path = "c.lua", status = "A" },
  }
  local repo_root = "/tmp/repo"

  local spec = source._build_diff_spec(s, file_pairs, repo_root)

  eq(spec.source.type, "commit")
  eq(spec.source.ref, "abc1234")
  eq(#spec.file_pairs, 3)
  eq(spec.title, "Commit abc1234 (3 files)")
  eq(spec.repo_root, "/tmp/repo")
end

T["_build_diff_spec"]["builds DiffSpec for empty diff"] = function()
  local s = { type = "unstaged" }
  local spec = source._build_diff_spec(s, {}, "/repo")

  eq(spec.source.type, "unstaged")
  eq(#spec.file_pairs, 0)
  eq(spec.title, "Diff unstaged (empty)")
  eq(spec.repo_root, "/repo")
end

T["_build_diff_spec"]["builds DiffSpec for range source"] = function()
  local s = { type = "range", range = "main..feature/foo" }
  local file_pairs = { {}, {}, {}, {} }
  local spec = source._build_diff_spec(s, file_pairs, "/repo")

  eq(spec.source.type, "range")
  eq(spec.source.range, "main..feature/foo")
  eq(spec.title, "Diff main..feature/foo (4 files)")
end

T["_build_diff_spec"]["builds DiffSpec for stash source"] = function()
  local s = { type = "stash", ref = "stash@{2}" }
  local file_pairs = { {} }
  local spec = source._build_diff_spec(s, file_pairs, "/repo")

  eq(spec.source.type, "stash")
  eq(spec.source.ref, "stash@{2}")
  eq(spec.title, "Stash stash@{2} (1 file)")
end

T["_build_diff_spec"]["preserves source fields like pr_info and selected_commit"] = function()
  local s = {
    type = "pr",
    pr_info = { number = 42, title = "My PR" },
    selected_commit = 3,
  }
  local spec = source._build_diff_spec(s, { {} }, "/repo")

  eq(spec.source.pr_info.number, 42)
  eq(spec.source.pr_info.title, "My PR")
  eq(spec.source.selected_commit, 3)
end

-- =============================================================================
-- Integration: _build_args + _build_diff_spec work together
-- =============================================================================

T["integration"] = MiniTest.new_set()

T["integration"]["staged source produces correct args and spec"] = function()
  local args = source._build_args("staged")
  eq(args[1], "diff")
  eq(args[2], "--cached")

  local s = { type = "staged" }
  local spec = source._build_diff_spec(s, { {}, {} }, "/repo")
  eq(spec.title, "Diff staged (2 files)")
end

T["integration"]["commit source produces correct args and spec"] = function()
  local ref = "deadbeef12345678"
  local args = source._build_args("commit", ref)
  eq(args[1], "show")
  eq(args[2], "--format=")
  eq(args[3], ref)

  local s = { type = "commit", ref = ref }
  local spec = source._build_diff_spec(s, { {} }, "/repo")
  -- Title should truncate the ref to 7 chars
  eq(spec.title, "Commit deadbee (1 file)")
end

T["integration"]["stash source produces correct args and spec"] = function()
  local stash_ref = "stash@{0}"
  local args = source._build_args("stash", stash_ref)
  eq(args[1], "stash")
  eq(args[2], "show")
  eq(args[3], "-p")
  eq(args[4], stash_ref)

  local s = { type = "stash", ref = stash_ref }
  local spec = source._build_diff_spec(s, {}, "/repo")
  eq(spec.title, "Stash stash@{0} (empty)")
end

return T
