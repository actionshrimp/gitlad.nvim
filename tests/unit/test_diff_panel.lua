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

--- Helper to find the first line number with a given type
---@param result DiffPanelRenderResult
---@param type_name string
---@return number|nil line_num
local function find_first_line_of_type(result, type_name)
  for i, info in _G.pairs(result.line_info) do
    if info.type == type_name then
      return i
    end
  end
  return nil
end

--- Helper to collect all line numbers with a given type
---@param result DiffPanelRenderResult
---@param type_name string
---@return number[]
local function find_all_lines_of_type(result, type_name)
  local lines = {}
  for i, info in _G.pairs(result.line_info) do
    if info.type == type_name then
      table.insert(lines, i)
    end
  end
  table.sort(lines)
  return lines
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

T["_render_file_list"]["renders single file with dir node"] = function()
  local pairs = { make_pair() } -- src/auth.lua
  local result = panel._render_file_list(pairs, 1, 40)

  -- header + separator + dir(src) + file(auth.lua) = 4 lines
  eq(#result.lines, 4)
  eq(result.line_info[3].type, "dir")
  eq(result.line_info[4].type, "file")
  eq(result.line_info[4].file_index, 1)
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

  -- header + separator + dir(src) + auth.lua + new.lua + new_file.lua + old_file.lua = 7
  eq(#result.lines, 7)
  eq(result.lines[1]:match("Files %(4%)") ~= nil, true)

  -- Check all status characters appear in file lines
  local file_lines = find_all_lines_of_type(result, "file")
  local found_statuses = {}
  for _, line_num in ipairs(file_lines) do
    local info = result.line_info[line_num]
    found_statuses[pairs[info.file_index].status] = true
  end
  expect.equality(found_statuses["M"], true)
  expect.equality(found_statuses["A"], true)
  expect.equality(found_statuses["D"], true)
  expect.equality(found_statuses["R"], true)
end

T["_render_file_list"]["shows selected indicator on correct file"] = function()
  local pairs = {
    make_pair({ new_path = "first.lua" }),
    make_pair({ new_path = "second.lua" }),
    make_pair({ new_path = "third.lua" }),
  }

  -- Select second file (root-level files, no dir nodes)
  local result = panel._render_file_list(pairs, 2, 40)

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
  local pairs = { make_pair({ additions = 10, deletions = 3 }) } -- src/auth.lua
  local result = panel._render_file_list(pairs, 1, 50)

  -- File line is after dir node: header(1) + sep(2) + dir(3) + file(4)
  local file_line = result.lines[4]
  expect.equality(file_line:match("%+10") ~= nil, true)
  expect.equality(file_line:match("%-3") ~= nil, true)
end

T["_render_file_list"]["shows only additions when deletions are zero"] = function()
  local pairs = { make_pair({ additions = 25, deletions = 0 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[4]
  expect.equality(file_line:match("%+25") ~= nil, true)
  expect.equality(file_line:match("%-0") == nil, true)
end

T["_render_file_list"]["shows only deletions when additions are zero"] = function()
  local pairs = { make_pair({ additions = 0, deletions = 15 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[4]
  expect.equality(file_line:match("%+0") == nil, true)
  expect.equality(file_line:match("%-15") ~= nil, true)
end

T["_render_file_list"]["shows binary for binary files"] = function()
  local pairs = { make_pair({ is_binary = true, additions = 0, deletions = 0 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_line = result.lines[4]
  expect.equality(file_line:match("binary") ~= nil, true)
end

T["_render_file_list"]["truncates long paths to fit panel width"] = function()
  local long_path = "very/deeply/nested/directory/structure/with/many/levels/file.lua"
  local pairs = { make_pair({ new_path = long_path }) }
  local result = panel._render_file_list(pairs, 1, 30)

  -- File is at depth 1 under flattened dir node
  local file_lines = find_all_lines_of_type(result, "file")
  expect.equality(#file_lines > 0, true)
  local file_line = result.lines[file_lines[1]]
  expect.equality(file_line:match("file%.lua") ~= nil, true)
end

T["_render_file_list"]["shows full filename when path is truncated"] = function()
  local long_path = "very/long/directory/path/somefile.lua"
  local pairs = { make_pair({ new_path = long_path }) }
  local result = panel._render_file_list(pairs, 1, 25)

  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
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
  -- Root-level files: no dir nodes, same positions as before
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

T["_render_file_list"]["file basename is displayed in line"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50)

  -- In tree mode, only the basename appears on the file line
  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
  expect.equality(file_line:match("auth%.lua") ~= nil, true)
end

T["_render_file_list"]["renamed file shows old -> new basenames"] = function()
  local pairs = {
    make_pair({ status = "R", old_path = "old_name.lua", new_path = "new_name.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 60)

  local file_line = result.lines[3]
  expect.equality(file_line:match("old_name%.lua %-> new_name%.lua") ~= nil, true)
end

T["_render_file_list"]["renamed file with same basename shows just the name"] = function()
  local pairs = {
    make_pair({ status = "R", old_path = "old_dir/file.lua", new_path = "new_dir/file.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 60)

  -- Same basename, so just show "file.lua" (no arrow)
  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
  expect.equality(file_line:match("file%.lua") ~= nil, true)
  expect.equality(file_line:match("->") == nil, true)
end

T["_render_file_list"]["file with no additions or deletions shows no stats"] = function()
  local pairs = { make_pair({ additions = 0, deletions = 0 }) }
  local result = panel._render_file_list(pairs, 1, 50)

  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
  expect.equality(file_line:match("%+%d") == nil, true)
  expect.equality(file_line:match("%-%d") == nil, true)
end

T["_render_file_list"]["separator line uses box-drawing character"] = function()
  local result = panel._render_file_list({}, 1, 35)

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
-- _render_file_list directory tree behavior
-- =============================================================================

T["_render_file_list tree"] = MiniTest.new_set()

T["_render_file_list tree"]["files with shared dir get grouped under dir node"] = function()
  local pairs = {
    make_pair({ new_path = "src/a.lua", status = "M" }),
    make_pair({ new_path = "src/b.lua", status = "A" }),
  }
  local result = panel._render_file_list(pairs, 1, 50)

  -- header + sep + dir(src) + a.lua + b.lua = 5
  eq(#result.lines, 5)
  eq(result.line_info[3].type, "dir")
  eq(result.line_info[3].dir_path, "src")
  eq(result.line_info[4].type, "file")
  eq(result.line_info[4].file_index, 1)
  eq(result.line_info[5].type, "file")
  eq(result.line_info[5].file_index, 2)
end

T["_render_file_list tree"]["root-level files have no extra indentation"] = function()
  local pairs = {
    make_pair({ new_path = "root.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  -- header + sep + file = 3 (no dir node for root-level file)
  eq(#result.lines, 3)
  eq(result.line_info[3].type, "file")
  -- No dir entries
  local dir_lines = find_all_lines_of_type(result, "dir")
  eq(#dir_lines, 0)
end

T["_render_file_list tree"]["file_index correct through tree"] = function()
  local pairs = {
    make_pair({ new_path = "z/third.lua" }),
    make_pair({ new_path = "a/first.lua" }),
    make_pair({ new_path = "root.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 50)

  -- Tree sort: dirs first (a, z), then files (root.lua)
  local file_lines = find_all_lines_of_type(result, "file")
  eq(#file_lines, 3)

  -- a/first.lua was pair #2
  eq(result.line_info[file_lines[1]].file_index, 2)
  -- z/third.lua was pair #1
  eq(result.line_info[file_lines[2]].file_index, 1)
  -- root.lua was pair #3
  eq(result.line_info[file_lines[3]].file_index, 3)
end

T["_render_file_list tree"]["dir line has type dir and dir_path"] = function()
  local pairs = {
    make_pair({ new_path = "lib/utils.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  local dir_lines = find_all_lines_of_type(result, "dir")
  eq(#dir_lines, 1)
  local info = result.line_info[dir_lines[1]]
  eq(info.type, "dir")
  eq(info.dir_path, "lib")
end

T["_render_file_list tree"]["collapsed dir hides its file children in render output"] = function()
  local pairs = {
    make_pair({ new_path = "src/a.lua" }),
    make_pair({ new_path = "src/b.lua" }),
    make_pair({ new_path = "root.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, nil, { ["src"] = true })

  -- header + sep + dir(src, collapsed) + root.lua = 4
  eq(#result.lines, 4)

  -- dir(src) is present but collapsed
  eq(result.line_info[3].type, "dir")
  -- Only root.lua file visible
  local file_lines = find_all_lines_of_type(result, "file")
  eq(#file_lines, 1)
  eq(result.line_info[file_lines[1]].file_index, 3) -- root.lua
end

T["_render_file_list tree"]["dir line shows fold icon"] = function()
  local pairs = {
    make_pair({ new_path = "src/a.lua" }),
  }

  -- Expanded: shows ▾
  local result_expanded = panel._render_file_list(pairs, 1, 40)
  local dir_line = result_expanded.lines[3]
  local expand_icon = "\xe2\x96\xbe" -- ▾
  expect.equality(dir_line:find(expand_icon, 1, true) ~= nil, true)

  -- Collapsed: shows ▸
  local result_collapsed = panel._render_file_list(pairs, 1, 40, nil, nil, nil, { ["src"] = true })
  local collapsed_dir_line = result_collapsed.lines[3]
  local collapse_icon = "\xe2\x96\xb8" -- ▸
  expect.equality(collapsed_dir_line:find(collapse_icon, 1, true) ~= nil, true)
end

T["_render_file_list tree"]["dir name appears in dir line"] = function()
  local pairs = {
    make_pair({ new_path = "mydir/file.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  local dir_lines = find_all_lines_of_type(result, "dir")
  local dir_line = result.lines[dir_lines[1]]
  expect.equality(dir_line:match("mydir") ~= nil, true)
end

T["_render_file_list tree"]["single-child dirs are flattened in display"] = function()
  local pairs = {
    make_pair({ new_path = "a/b/c/file.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 50)

  -- Dir should show flattened name "a/b/c"
  local dir_lines = find_all_lines_of_type(result, "dir")
  eq(#dir_lines, 1)
  local dir_line = result.lines[dir_lines[1]]
  expect.equality(dir_line:match("a/b/c") ~= nil, true)
end

T["_render_file_list tree"]["file entries store depth in line_info"] = function()
  local pairs = {
    make_pair({ new_path = "src/file.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  local file_lines = find_all_lines_of_type(result, "file")
  local info = result.line_info[file_lines[1]]
  eq(info.depth, 1)
end

T["_render_file_list tree"]["root-level file has depth 0"] = function()
  local pairs = {
    make_pair({ new_path = "root.lua" }),
  }
  local result = panel._render_file_list(pairs, 1, 40)

  local file_lines = find_all_lines_of_type(result, "file")
  local info = result.line_info[file_lines[1]]
  eq(info.depth, 0)
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
  local file_pairs = { make_pair() } -- src/auth.lua
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  -- Commits header(1) + sep(1) + All changes(1) + 3 commits(3) + sep(1) +
  -- Files header(1) + sep(1) + dir(src)(1) + file(auth.lua)(1) = 11 lines
  eq(#result.lines, 11)

  -- Verify the Commits header
  expect.equality(result.lines[1]:match("Commits %(3%)") ~= nil, true)
  eq(result.line_info[1].type, "header")
end

T["_render_file_list with PR commits"]["renders All changes entry"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  expect.equality(result.lines[3]:match("All changes") ~= nil, true)
  eq(result.line_info[3].type, "commit_all")
end

T["_render_file_list with PR commits"]["shows filled diamond for selected All changes"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

  local filled_diamond = "\xe2\x97\x86"
  expect.equality(result.lines[3]:find(filled_diamond, 1, true) ~= nil, true)
end

T["_render_file_list with PR commits"]["shows open diamond for unselected All changes"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, 1)

  local open_diamond = "\xe2\x97\x87"
  expect.equality(result.lines[3]:find(open_diamond, 1, true) ~= nil, true)
end

T["_render_file_list with PR commits"]["renders individual commit entries"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, nil)

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
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, 2)

  local filled_circle = "\xe2\x97\x8f"
  local open_circle = "\xe2\x97\x8b"

  expect.equality(result.lines[4]:find(open_circle, 1, true) ~= nil, true)
  expect.equality(result.lines[5]:find(filled_circle, 1, true) ~= nil, true)
  expect.equality(result.lines[6]:find(open_circle, 1, true) ~= nil, true)
end

T["_render_file_list with PR commits"]["shows triangle indicator for selected commit"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, 2)

  local triangle = "\xe2\x96\xb8"
  expect.equality(result.lines[4]:sub(1, 1) == " ", true)
  expect.equality(result.lines[5]:sub(1, 3) == triangle, true)
  expect.equality(result.lines[6]:sub(1, 1) == " ", true)
end

T["_render_file_list with PR commits"]["shows diff stats on commit entries"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 60, pr_info, nil)

  expect.equality(result.lines[4]:match("%+10") ~= nil, true)
  expect.equality(result.lines[4]:match("%-3") ~= nil, true)
end

T["_render_file_list with PR commits"]["has separator between commits and files sections"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info()
  local result = panel._render_file_list(file_pairs, 1, 50, pr_info, nil)

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
  expect.equality(result.lines[files_header_line]:match("Files %(2%)") ~= nil, true)

  -- File entries should exist
  local file_lines = find_all_lines_of_type(result, "file")
  eq(#file_lines, 2)
end

T["_render_file_list with PR commits"]["renders without commits when pr_info is nil"] = function()
  local file_pairs = { make_pair() } -- src/auth.lua
  local result = panel._render_file_list(file_pairs, 1, 40, nil, nil)

  -- header + separator + dir(src) + file(auth.lua) = 4 lines
  eq(#result.lines, 4)
  expect.equality(result.lines[1]:match("Files %(1%)") ~= nil, true)
end

T["_render_file_list with PR commits"]["renders without commits when pr_info has empty commits"] = function()
  local file_pairs = { make_pair() }
  local pr_info = make_pr_info({ commits = {} })
  local result = panel._render_file_list(file_pairs, 1, 40, pr_info, nil)

  -- header + separator + dir(src) + file(auth.lua) = 4 lines
  eq(#result.lines, 4)
end

-- =============================================================================
-- _render_file_list with file type icons (icon_fn)
-- =============================================================================

T["_render_file_list with icon_fn"] = MiniTest.new_set()

--- Mock icon_fn that returns a Lua icon
local function mock_icon_fn(filename)
  local icons = {
    ["auth.lua"] = { "\xef\x85\xa0", "DevIconLua" }, -- lua icon
    ["test.js"] = { "\xee\x9e\x81", "DevIconJs" }, -- js icon
  }
  local entry = icons[filename]
  if entry then
    return entry[1], entry[2]
  end
  return nil, nil
end

T["_render_file_list with icon_fn"]["renders file icon when icon_fn provided"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, mock_icon_fn)

  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
  local lua_icon = "\xef\x85\xa0"
  expect.equality(file_line:find(lua_icon, 1, true) ~= nil, true)
  expect.equality(file_line:match("auth%.lua") ~= nil, true)
end

T["_render_file_list with icon_fn"]["omits icon when icon_fn is nil"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, nil)

  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
  local lua_icon = "\xef\x85\xa0"
  expect.equality(file_line:find(lua_icon, 1, true) == nil, true)
  expect.equality(file_line:match("auth%.lua") ~= nil, true)
end

T["_render_file_list with icon_fn"]["stores icon_hl in line_info"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, mock_icon_fn)

  local file_lines = find_all_lines_of_type(result, "file")
  local info = result.line_info[file_lines[1]]
  eq(info.type, "file")
  eq(info.icon_hl, "DevIconLua")
  expect.equality(type(info.icon_byte_offset), "number")
end

T["_render_file_list with icon_fn"]["stores icon_byte_offset correctly for selected file"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, mock_icon_fn)

  local file_lines = find_all_lines_of_type(result, "file")
  local info = result.line_info[file_lines[1]]
  -- Triangle(3 bytes) + indent(2, depth 1) + status(1) + space(1) = offset 7
  eq(info.icon_byte_offset, 7)
end

T["_render_file_list with icon_fn"]["stores icon_byte_offset correctly for unselected file"] = function()
  local pairs = {
    make_pair({ new_path = "src/auth.lua" }),
    make_pair({ new_path = "src/test.js" }),
  }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, mock_icon_fn)

  -- Both under src/ at depth 1. Second file is unselected.
  local file_lines = find_all_lines_of_type(result, "file")
  local info = result.line_info[file_lines[2]] -- second file (test.js)
  -- Space(1 byte) + indent(2, depth 1) + status(1) + space(1) = offset 5
  eq(info.icon_byte_offset, 5)
end

T["_render_file_list with icon_fn"]["adjusts path width when icon present"] = function()
  local pairs = { make_pair({ new_path = "src/auth.lua", additions = 10, deletions = 3 }) }

  local result_no_icon = panel._render_file_list(pairs, 1, 30, nil, nil, nil)
  local result_with_icon = panel._render_file_list(pairs, 1, 30, nil, nil, mock_icon_fn)

  local file_lines_no = find_all_lines_of_type(result_no_icon, "file")
  local file_lines_with = find_all_lines_of_type(result_with_icon, "file")
  local line_no_icon = result_no_icon.lines[file_lines_no[1]]
  local line_with_icon = result_with_icon.lines[file_lines_with[1]]

  local lua_icon = "\xef\x85\xa0"
  expect.equality(line_with_icon:find(lua_icon, 1, true) ~= nil, true)
  expect.equality(line_no_icon:find(lua_icon, 1, true) == nil, true)
end

T["_render_file_list with icon_fn"]["handles icon_fn returning nil"] = function()
  local nil_icon_fn = function(_)
    return nil, nil
  end

  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, nil_icon_fn)

  local file_lines = find_all_lines_of_type(result, "file")
  local info = result.line_info[file_lines[1]]
  eq(info.type, "file")
  eq(info.icon_hl, nil)
  eq(info.icon_byte_offset, nil)
end

T["_render_file_list with icon_fn"]["does not add icon_hl when icon_fn returns icon but nil hl"] = function()
  local partial_icon_fn = function(_)
    return "\xef\x85\xa0", nil
  end

  local pairs = { make_pair({ new_path = "src/auth.lua" }) }
  local result = panel._render_file_list(pairs, 1, 50, nil, nil, partial_icon_fn)

  local file_lines = find_all_lines_of_type(result, "file")
  local file_line = result.lines[file_lines[1]]
  local lua_icon = "\xef\x85\xa0"
  expect.equality(file_line:find(lua_icon, 1, true) ~= nil, true)
  local info = result.line_info[file_lines[1]]
  eq(info.icon_hl, nil)
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
