local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Helper to create a temporary file
local function create_temp_file(content)
  local path = vim.fn.tempname()
  local f = io.open(path, "w")
  f:write(content)
  f:close()
  return path
end

-- Helper to cleanup temp file
local function cleanup_file(path)
  os.remove(path)
end

-- has_conflict_markers tests
T["has_conflict_markers"] = MiniTest.new_set()

T["has_conflict_markers"]["returns true for file with standard conflict markers"] = function()
  local status = require("gitlad.ui.views.status")
  local content = [[line1
<<<<<<< HEAD
our changes
=======
their changes
>>>>>>> feature
line2]]

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, true)
end

T["has_conflict_markers"]["returns true when markers at start of file"] = function()
  local status = require("gitlad.ui.views.status")
  local content = [[<<<<<<< HEAD
our changes
=======
their changes
>>>>>>> feature]]

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, true)
end

T["has_conflict_markers"]["returns false for file without markers"] = function()
  local status = require("gitlad.ui.views.status")
  local content = [[line1
line2
line3
normal content here]]

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, false)
end

T["has_conflict_markers"]["returns false for empty file"] = function()
  local status = require("gitlad.ui.views.status")
  local content = ""

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, false)
end

T["has_conflict_markers"]["returns false for non-existent file"] = function()
  local status = require("gitlad.ui.views.status")
  local result = status._has_conflict_markers("/non/existent/path/file.txt")

  eq(result, false)
end

T["has_conflict_markers"]["returns false for partial marker (less than 7 chars)"] = function()
  local status = require("gitlad.ui.views.status")
  -- Only 6 < characters - not a valid conflict marker
  local content = [[line1
<<<<<< not enough
line2]]

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, false)
end

T["has_conflict_markers"]["returns true for marker with 7+ chars"] = function()
  local status = require("gitlad.ui.views.status")
  -- Exactly 7 < characters
  local content = [[line1
<<<<<<< HEAD
line2]]

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, true)
end

T["has_conflict_markers"]["returns false when markers not at line start"] = function()
  local status = require("gitlad.ui.views.status")
  -- Markers indented - not valid
  local content = [[line1
  <<<<<<< HEAD
line2]]

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, false)
end

T["has_conflict_markers"]["handles binary-like content gracefully"] = function()
  local status = require("gitlad.ui.views.status")
  -- Content with null bytes and special chars
  local content = "line1\0line2\nline3"

  local path = create_temp_file(content)
  local result = status._has_conflict_markers(path)
  cleanup_file(path)

  eq(result, false)
end

return T
