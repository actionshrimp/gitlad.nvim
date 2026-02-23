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

-- =============================================================================
-- _build_pr_args
-- =============================================================================

T["_build_pr_args"] = MiniTest.new_set()

local function make_pr_info(overrides)
  overrides = overrides or {}
  return vim.tbl_deep_extend("force", {
    number = 42,
    title = "Fix auth bug",
    base_ref = "main",
    head_ref = "feature/auth",
    base_oid = "aaa1111222233334444555566667777aaaa1111",
    head_oid = "bbb2222333344445555666677778888bbbb2222",
    commits = {
      {
        oid = "ccc3333444455556666777788889999cccc3333",
        short_oid = "ccc3333",
        message_headline = "Fix login",
        author_name = "Jane",
        author_date = "2026-02-19T10:00:00Z",
        additions = 10,
        deletions = 3,
      },
      {
        oid = "ddd4444555566667777888899990000dddd4444",
        short_oid = "ddd4444",
        message_headline = "Add tests",
        author_name = "Jane",
        author_date = "2026-02-19T11:00:00Z",
        additions = 20,
        deletions = 0,
      },
      {
        oid = "eee5555666677778888999900001111eeee5555",
        short_oid = "eee5555",
        message_headline = "Clean up",
        author_name = "Jane",
        author_date = "2026-02-19T12:00:00Z",
        additions = 5,
        deletions = 8,
      },
    },
  }, overrides)
end

T["_build_pr_args"]["builds three-dot diff for full PR diff (selected_index nil)"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, nil)
  eq(err, nil)
  eq(args, { "diff", pr_info.base_oid .. "..." .. pr_info.head_oid })
end

T["_build_pr_args"]["uses base_oid as parent for first commit"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, 1)
  eq(err, nil)
  eq(args, { "diff", pr_info.base_oid .. ".." .. pr_info.commits[1].oid })
end

T["_build_pr_args"]["uses previous commit as parent for subsequent commits"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, 2)
  eq(err, nil)
  eq(args, { "diff", pr_info.commits[1].oid .. ".." .. pr_info.commits[2].oid })
end

T["_build_pr_args"]["uses previous commit as parent for third commit"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, 3)
  eq(err, nil)
  eq(args, { "diff", pr_info.commits[2].oid .. ".." .. pr_info.commits[3].oid })
end

T["_build_pr_args"]["returns error for invalid commit index"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, 99)
  expect.equality(err ~= nil, true)
  expect.equality(err:match("Invalid commit index") ~= nil, true)
  eq(#args, 0)
end

T["_build_pr_args"]["returns error for zero commit index"] = function()
  local pr_info = make_pr_info({ commits = {} })
  local args, err = source._build_pr_args(pr_info, 0)
  expect.equality(err ~= nil, true)
end

-- =============================================================================
-- _build_title for PR source
-- =============================================================================

T["_build_title"]["builds full PR title when no commit selected"] = function()
  local s = {
    type = "pr",
    pr_info = {
      number = 42,
      title = "Fix auth bug",
      commits = {},
    },
  }
  local files = { {}, {} }
  eq(source._build_title(s, files), "PR #42 Fix auth bug (2 files)")
end

T["_build_title"]["builds PR title with selected commit"] = function()
  local s = {
    type = "pr",
    pr_info = {
      number = 42,
      title = "Fix auth bug",
      commits = {
        {
          oid = "abc1234",
          short_oid = "abc1234",
          message_headline = "Fix login flow",
        },
      },
    },
    selected_commit = 1,
  }
  local files = { {} }
  eq(source._build_title(s, files), "PR #42: Fix login flow (abc1234) (1 file)")
end

T["_build_title"]["handles PR source without pr_info"] = function()
  local s = { type = "pr" }
  local files = { {} }
  eq(source._build_title(s, files), "PR (1 file)")
end

T["_build_title"]["handles PR source with invalid selected_commit"] = function()
  local s = {
    type = "pr",
    pr_info = {
      number = 42,
      title = "Fix auth bug",
      commits = {},
    },
    selected_commit = 99,
  }
  local files = { {} }
  -- Falls through to full PR title when commit not found
  eq(source._build_title(s, files), "PR #42 Fix auth bug (1 file)")
end

-- =============================================================================
-- PR integration
-- =============================================================================

T["integration"]["PR full diff builds correct args and title"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, nil)
  eq(err, nil)
  eq(args[1], "diff")
  expect.equality(args[2]:match("%.%.%.") ~= nil, true) -- three-dot diff

  local s = { type = "pr", pr_info = pr_info }
  local spec = source._build_diff_spec(s, { {}, {} }, "/repo")
  eq(spec.title, "PR #42 Fix auth bug (2 files)")
end

T["integration"]["PR single commit builds correct args and title"] = function()
  local pr_info = make_pr_info()
  local args, err = source._build_pr_args(pr_info, 2)
  eq(err, nil)
  eq(args[1], "diff")
  expect.equality(args[2]:match("%.%.") ~= nil, true) -- two-dot diff

  local s = { type = "pr", pr_info = pr_info, selected_commit = 2 }
  local spec = source._build_diff_spec(s, { {} }, "/repo")
  eq(spec.title, "PR #42: Add tests (ddd4444) (1 file)")
end

-- =============================================================================
-- _build_title for merge source
-- =============================================================================

T["_build_title"]["builds merge title with WORKTREE label"] = function()
  local s = { type = "merge" }
  local files = { {}, {} }
  eq(source._build_title(s, files), "3-way OURS|WORKTREE|THEIRS (2 files)")
end

T["_build_title"]["builds merge title with empty diff"] = function()
  local s = { type = "merge" }
  eq(source._build_title(s, {}), "3-way OURS|WORKTREE|THEIRS (empty)")
end

-- =============================================================================
-- _finalize_merge
-- =============================================================================

T["_finalize_merge"] = MiniTest.new_set()

T["_finalize_merge"]["builds three_way_files and file_pairs from ours/theirs diffs"] = function()
  local paths = { "file.lua" }
  local file_diffs = {
    ["file.lua"] = {
      ours_pairs = {
        {
          old_path = "a/file.lua",
          new_path = "b/file.lua",
          status = "M",
          hunks = {
            {
              header = { old_start = 1, old_count = 3, new_start = 1, new_count = 3 },
              pairs = {},
            },
          },
          additions = 5,
          deletions = 2,
          is_binary = false,
        },
      },
      theirs_pairs = {
        {
          old_path = "a/file.lua",
          new_path = "b/file.lua",
          status = "M",
          hunks = {
            {
              header = { old_start = 1, old_count = 3, new_start = 1, new_count = 3 },
              pairs = {},
            },
          },
          additions = 3,
          deletions = 1,
          is_binary = false,
        },
      },
    },
  }

  local result_spec
  source._finalize_merge("/repo", paths, file_diffs, function(spec, err)
    eq(err, nil)
    result_spec = spec
  end)

  eq(result_spec ~= nil, true)
  eq(result_spec.source.type, "merge")
  eq(#result_spec.file_pairs, 1)
  eq(result_spec.file_pairs[1].status, "U")
  eq(result_spec.file_pairs[1].additions, 8) -- 5 + 3
  eq(result_spec.file_pairs[1].deletions, 3) -- 2 + 1
  eq(#result_spec.three_way_files, 1)
  eq(result_spec.three_way_files[1].path, "file.lua")
  eq(#result_spec.three_way_files[1].staged_hunks, 1)
  eq(#result_spec.three_way_files[1].unstaged_hunks, 1)
end

T["_finalize_merge"]["handles missing ours (no :2: stage)"] = function()
  local paths = { "new_file.lua" }
  local file_diffs = {
    ["new_file.lua"] = {
      ours_pairs = {},
      theirs_pairs = {
        {
          old_path = "a/new_file.lua",
          new_path = "b/new_file.lua",
          status = "A",
          hunks = {
            { header = { old_start = 0, old_count = 0, new_start = 1, new_count = 3 }, pairs = {} },
          },
          additions = 3,
          deletions = 0,
          is_binary = false,
        },
      },
    },
  }

  local result_spec
  source._finalize_merge("/repo", paths, file_diffs, function(spec, err)
    eq(err, nil)
    result_spec = spec
  end)

  eq(#result_spec.three_way_files, 1)
  eq(#result_spec.three_way_files[1].staged_hunks, 0) -- No ours hunks
  eq(#result_spec.three_way_files[1].unstaged_hunks, 1) -- Has theirs hunks
end

T["_finalize_merge"]["handles multiple conflicted files"] = function()
  local paths = { "a.lua", "b.lua" }
  local file_diffs = {
    ["a.lua"] = { ours_pairs = {}, theirs_pairs = {} },
    ["b.lua"] = { ours_pairs = {}, theirs_pairs = {} },
  }

  local result_spec
  source._finalize_merge("/repo", paths, file_diffs, function(spec, err)
    eq(err, nil)
    result_spec = spec
  end)

  eq(#result_spec.file_pairs, 2)
  eq(result_spec.file_pairs[1].new_path, "a.lua")
  eq(result_spec.file_pairs[2].new_path, "b.lua")
end

return T
