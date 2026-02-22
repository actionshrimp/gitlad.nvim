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

return T
