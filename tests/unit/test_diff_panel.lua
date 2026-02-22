local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local panel = require("gitlad.ui.views.diff.panel")

--- Helper to create a mock DiffFilePair
---@param overrides? table
---@return DiffFilePair
local function make_pair(overrides)
  overrides = overrides or {}
  return vim.tbl_deep_extend("force", {
    old_path = "src/auth.lua",
    new_path = "src/auth.lua",
    status = "M",
    hunks = {},
    additions = 10,
    deletions = 3,
    is_binary = false,
  }, overrides)
end

-- =============================================================================
-- _render_file_list
-- =============================================================================

T["_render_file_list"] = MiniTest.new_set()

T["_render_file_list"]["returns header and separator for empty file list"] = function()
  local result = panel._render_file_list({}, 1, 35)

  eq(#result.lines, 2)
  expect.equality(result.lines[1]:match("Files %(0%)") ~= nil, true)
  eq(result.line_info[1].type, "header")
  eq(result.line_info[2].type, "separator")
end

T["_render_file_list"]["renders single file"] = function()
  local pairs = { make_pair() }
  local result = panel._render_file_list(pairs, 1, 40)

  eq(#result.lines, 3) -- header + separator + 1 file
  eq(result.line_info[3].type, "file")
  eq(result.line_info[3].file_index, 1)
end

T["_render_file_list"]["renders multiple files with different statuses"] = function()
  local pairs = {
    make_pair({ status = "M", new_path = "src/auth.lua", additions = 10, deletions = 3 }),
    make_pair({ status = "A", new_path = "new_file.lua", additions = 25, deletions = 0 }),
    make_pair({ status = "D", new_path = "old_file.lua", additions = 0, deletions = 15 }),
    make_pair({
      status = "R",
      old_path = "old.lua",
      new_path = "new.lua",
      additions = 2,
      deletions = 1,
    }),
  }
  local result = panel._render_file_list(pairs, 1, 50)

  eq(#result.lines, 6) -- header + separator + 4 files
  eq(result.lines[1]:match("Files %(4%)") ~= nil, true)

  -- Check status characters appear in lines
  -- Line 3 (first file): indicator + "M"
  expect.equality(result.lines[3]:match("M") ~= nil, true)
  expect.equality(result.lines[4]:match("A") ~= nil, true)
  expect.equality(result.lines[5]:match("D") ~= nil, true)
  expect.equality(result.lines[6]:match("R") ~= nil, true)
end

T["_render_file_list"]["shows selected indicator on correct file"] = function()
  local pairs = {
    make_pair({ new_path = "first.lua" }),
    make_pair({ new_path = "second.lua" }),
    make_pair({ new_path = "third.lua" }),
  }

  -- Select second file
  local result = panel._render_file_list(pairs, 2, 40)

  -- First file (line 3): space indicator
  -- The triangle indicator is UTF-8: \xe2\x96\xb8
  local triangle = "\xe2\x96\xb8"
  expect.equality(result.lines[3]:sub(1, 1) == " ", true)
  expect.equality(result.lines[4]:sub(1, 3) == triangle, true)
  expect.equality(result.lines[5]:sub(1, 1) == " ", true)
end

T["_render_file_list"]["shows selected indicator on first file by default"] = function()
  local pairs = {
    make_pair({ new_path = "first.lua" }),
    make_pair({ new_path = "second.lua" }),
  }

  local result = panel._render_file_list(pairs, 1, 40)

  local triangle = "\xe2\x96\xb8"
  expect.equality(result.lines[3]:sub(1, 3) == triangle, true)
  expect.equality(result.lines[4]:sub(1, 1) == " ", true)
end

T["_render_file_list"]["shows diff stats with additions and deletions"] = function()
  local pairs = { make_pair({ additions = 10, deletions = 3 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[3]
  expect.equality(file_line:match("%+10") ~= nil, true)
  expect.equality(file_line:match("%-3") ~= nil, true)
end

T["_render_file_list"]["shows only additions when deletions are zero"] = function()
  local pairs = { make_pair({ additions = 25, deletions = 0 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[3]
  expect.equality(file_line:match("%+25") ~= nil, true)
  -- Should not contain -0
  expect.equality(file_line:match("%-0") == nil, true)
end

T["_render_file_list"]["shows only deletions when additions are zero"] = function()
  local pairs = { make_pair({ additions = 0, deletions = 15 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[3]
  -- Should not contain +0
  expect.equality(file_line:match("%+0") == nil, true)
  expect.equality(file_line:match("%-15") ~= nil, true)
end

T["_render_file_list"]["shows binary for binary files"] = function()
  local pairs = { make_pair({ is_binary = true, additions = 0, deletions = 0 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[3]
  expect.equality(file_line:match("binary") ~= nil, true)
end

T["_render_file_list"]["truncates long paths to fit panel width"] = function()
  local long_path = "very/deeply/nested/directory/structure/with/many/levels/file.lua"
  local pairs = { make_pair({ new_path = long_path }) }
  local result = panel._render_file_list(pairs, 1, 30)

  local file_line = result.lines[3]
  -- Line should not exceed panel width significantly
  -- The filename should be shown, possibly truncated
  expect.equality(file_line:match("file%.lua") ~= nil, true)
end

T["_render_file_list"]["shows full filename when path is truncated"] = function()
  local long_path = "very/long/directory/path/somefile.lua"
  local pairs = { make_pair({ new_path = long_path }) }
  local result = panel._render_file_list(pairs, 1, 25)

  local file_line = result.lines[3]
  -- Should show at least the filename
  expect.equality(file_line:match("somefile%.lua") ~= nil, true)
end

T["_render_file_list"]["line_info maps header correctly"] = function()
  local pairs = { make_pair() }
  local result = panel._render_file_list(pairs, 1, 35)

  eq(result.line_info[1].type, "header")
  eq(result.line_info[1].file_index, nil)
end

T["_render_file_list"]["line_info maps separator correctly"] = function()
  local pairs = { make_pair() }
  local result = panel._render_file_list(pairs, 1, 35)

  eq(result.line_info[2].type, "separator")
  eq(result.line_info[2].file_index, nil)
end

T["_render_file_list"]["line_info maps file lines correctly"] = function()
  local pairs = {
    make_pair({ new_path = "first.lua" }),
    make_pair({ new_path = "second.lua" }),
    make_pair({ new_path = "third.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  eq(result.line_info[3].type, "file")
  eq(result.line_info[3].file_index, 1)
  eq(result.line_info[4].type, "file")
  eq(result.line_info[4].file_index, 2)
  eq(result.line_info[5].type, "file")
  eq(result.line_info[5].file_index, 3)
end

T["_render_file_list"]["header shows correct file count"] = function()
  local pairs = {
    make_pair({ new_path = "a.lua" }),
    make_pair({ new_path = "b.lua" }),
    make_pair({ new_path = "c.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  expect.equality(result.lines[1]:match("Files %(3%)") ~= nil, true)
end

T["_render_file_list"]["file path is displayed in line"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50)

  expect.equality(result.lines[3]:match("src/auth%.lua") ~= nil, true)
end

T["_render_file_list"]["renamed file shows old -> new path"] = function()
  local pairs = {
    make_pair({ status = "R", old_path = "old_name.lua", new_path = "new_name.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 60)

  local file_line = result.lines[3]
  expect.equality(file_line:match("old_name%.lua %-> new_name%.lua") ~= nil, true)
end

T["_render_file_list"]["file with no additions or deletions shows no stats"] = function()
  local pairs = { make_pair({ additions = 0, deletions = 0 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[3]
  -- Should not have any +N or -N
  expect.equality(file_line:match("%+%d") == nil, true)
  expect.equality(file_line:match("%-%d") == nil, true)
end

T["_render_file_list"]["separator line uses box-drawing character"] = function()
  local result = panel._render_file_list({}, 1, 35)

  -- The separator uses \xe2\x94\x80 (box drawing light horizontal)
  local box_char = "\xe2\x94\x80"
  expect.equality(result.lines[2]:find(box_char, 1, true) ~= nil, true)
end

T["_render_file_list"]["handles copied file status"] = function()
  local pairs = { make_pair({ status = "C", new_path = "copied.lua" }) }
  local result = panel._render_file_list(pairs, 1, 40)

  expect.equality(result.lines[3]:match("C") ~= nil, true)
  expect.equality(result.lines[3]:match("copied%.lua") ~= nil, true)
end

-- =============================================================================
-- _render_file_list with PR commits
-- =============================================================================

T["_render_file_list with PR commits"] = MiniTest.new_set()

--- Helper to create mock PR info
---@param overrides? table
---@return table
local function make_pr_info(overrides)
  overrides = overrides or {}
  return vim.tbl_deep_extend("force", {
    number = 42,
    title = "Fix auth bug",
    base_ref = "main",
    head_ref = "feature/auth",
    base_oid = "aaa111",
    head_oid = "bbb222",
    commits = {
      {
        oid = "abc1234",
        short_oid = "abc1234",
        message_headline = "Fix auth",
        author_name = "Jane",
        author_date = "2026-02-19T10:00:00Z",
        additions = 10,
        deletions = 3,
      },
      {
        oid = "def5678",
        short_oid = "def5678",
        message_headline = "Add validation",
        author_name = "John",
        author_date = "2026-02-19T11:00:00Z",
        additions = 15,
        deletions = 5,
      },
      {
        oid = "ghi9012",
        short_oid = "ghi9012",
        message_headline = "Update tests",
        author_name = "Jane",
        author_date = "2026-02-19T12:00:00Z",
        additions = 17,
        deletions = 10,
      },
    },
  }, overrides)
end

T["_render_file_list with PR commits"]["renders commits section when pr_info provided"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Commits header(1) + sep(1) + All changes(1) + 3 commits(3) + sep(1) +
  -- Files header(1) + sep(1) + 1 file(1) = 10 lines
  eq(#result.lines, 10)

  -- Verify the Commits header
  expect.equality(result.lines[1]:match("Commits %(3%)") ~= nil, true)
  eq(result.line_info[1].type, "header")
end

T["_render_file_list with PR commits"]["renders All changes entry"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  -- selected_commit = nil means "All changes" is selected
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Line 3 should be "All changes"
  expect.equality(result.lines[3]:match("All changes") ~= nil, true)
  eq(result.line_info[3].type, "commit_all")
end

T["_render_file_list with PR commits"]["shows filled diamond for selected All changes"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  -- selected_commit = nil means "All changes" is selected
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Filled diamond: U+25C6 = \xe2\x97\x86
  local filled_diamond = "\xe2\x97\x86"
  expect.equality(result.lines[3]:find(filled_diamond, 1, true) ~= nil, true)
end

T["_render_file_list with PR commits"]["shows open diamond for unselected All changes"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  -- selected_commit = 1 means first commit is selected, not All changes
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, 1)

  -- Open diamond: U+25C7 = \xe2\x97\x87
  local open_diamond = "\xe2\x97\x87"
  expect.equality(result.lines[3]:find(open_diamond, 1, true) ~= nil, true)
end

T["_render_file_list with PR commits"]["renders individual commit entries"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, nil)

  -- Commits at lines 4, 5, 6
  expect.equality(result.lines[4]:match("abc1234") ~= nil, true)
  expect.equality(result.lines[4]:match("Fix auth") ~= nil, true)
  eq(result.line_info[4].type, "commit")
  eq(result.line_info[4].commit_index, 1)

  expect.equality(result.lines[5]:match("def5678") ~= nil, true)
  expect.equality(result.lines[5]:match("Add validation") ~= nil, true)
  eq(result.line_info[5].type, "commit")
  eq(result.line_info[5].commit_index, 2)

  expect.equality(result.lines[6]:match("ghi9012") ~= nil, true)
  expect.equality(result.lines[6]:match("Update tests") ~= nil, true)
  eq(result.line_info[6].type, "commit")
  eq(result.line_info[6].commit_index, 3)
end

T["_render_file_list with PR commits"]["shows filled circle for selected commit"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  -- Select commit 2
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, 2)

  -- Filled circle: U+25CF = \xe2\x97\x8f
  local filled_circle = "\xe2\x97\x8f"
  -- Open circle: U+25CB = \xe2\x97\x8b
  local open_circle = "\xe2\x97\x8b"

  -- Commit 1 (line 4) should have open circle
  expect.equality(result.lines[4]:find(open_circle, 1, true) ~= nil, true)
  -- Commit 2 (line 5) should have filled circle
  expect.equality(result.lines[5]:find(filled_circle, 1, true) ~= nil, true)
  -- Commit 3 (line 6) should have open circle
  expect.equality(result.lines[6]:find(open_circle, 1, true) ~= nil, true)
end

T["_render_file_list with PR commits"]["shows triangle indicator for selected commit"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  -- Select commit 2
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, 2)

  local triangle = "\xe2\x96\xb8"
  -- Commit 1 (line 4): space indicator
  expect.equality(result.lines[4]:sub(1, 1) == " ", true)
  -- Commit 2 (line 5): triangle indicator
  expect.equality(result.lines[5]:sub(1, 3) == triangle, true)
  -- Commit 3 (line 6): space indicator
  expect.equality(result.lines[6]:sub(1, 1) == " ", true)
end

T["_render_file_list with PR commits"]["shows diff stats on commit entries"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, nil)

  -- First commit: +10 -3
  expect.equality(result.lines[4]:match("%+10") ~= nil, true)
  expect.equality(result.lines[4]:match("%-3") ~= nil, true)
end

T["_render_file_list with PR commits"]["has separator between commits and files sections"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Line 7 should be a separator (between commit and file sections)
  eq(result.line_info[7].type, "separator")
end

T["_render_file_list with PR commits"]["files section follows commits section"] = function()
  local file_pairs = {
    make_pair({ new_path = "src/auth.lua" }),
    make_pair({ new_path = "src/test.lua" }),
  }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Find Files header
  local files_header_line = nil
  for i, info in _G.pairs(result.line_info) do
    if info.type == "header" and result.lines[i]:match("Files") then
      files_header_line = i
      break
    end
  end
  expect.equality(files_header_line ~= nil, true)

  -- Files header should contain count
  expect.equality(result.lines[files_header_line]:match("Files %(2%)") ~= nil, true)

  -- File entries should follow
  local file_lines = {}
  for i, info in _G.pairs(result.line_info) do
    if info.type == "file" then
      table.insert(file_lines, i)
    end
  end
  eq(#file_lines, 2)
end

T["_render_file_list with PR commits"]["renders without commits when pr_info is nil"] = function()
  local file_pairs = { make_pair() }
  -- No pr_info -> should render like normal (no commit section)
  local result = panel._render_file_list(file_pairs, 1, 40, nil, nil)

  -- Same as normal: header + separator + 1 file = 3 lines
  eq(#result.lines, 3)
  expect.equality(result.lines[1]:match("Files %(1%)") ~= nil, true)
end

T["_render_file_list with PR commits"]["renders without commits when pr_info has empty commits"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info({ commits = {} })
  -- Empty commits -> should skip commit section
  local result = panel._render_file_list(file_pairs, 1, 40, pr_info, nil)

  -- Just files: header + separator + 1 file = 3 lines
  eq(#result.lines, 3)
end

T["_render_file_list with PR commits"]["line_info correctly identifies all commit-related lines"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Count each type
  local counts = { header = 0, separator = 0, commit_all = 0, commit = 0, file = 0 }
  for _, info in _G.pairs(result.line_info) do
    counts[info.type] = (counts[info.type] or 0) + 1
  end

  -- 2 headers (Commits + Files), 3 separators, 1 commit_all, 3 commits, 1 file
  eq(counts.header, 2)
  eq(counts.separator, 3)
  eq(counts.commit_all, 1)
  eq(counts.commit, 3)
  eq(counts.file, 1)
end

return T
