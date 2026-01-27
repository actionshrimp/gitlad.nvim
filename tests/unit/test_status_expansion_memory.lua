-- Tests for expansion memory data structures in status buffer
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["remembered_file_states"] = MiniTest.new_set()

T["remembered_file_states"]["stores hunk expansion state by cache key"] = function()
  local remembered_file_states = {}

  -- Save hunk state when collapsing a file
  remembered_file_states["unstaged:file.lua"] = { [1] = true, [3] = true }

  -- Verify storage
  eq(remembered_file_states["unstaged:file.lua"][1], true)
  eq(remembered_file_states["unstaged:file.lua"][2], nil)
  eq(remembered_file_states["unstaged:file.lua"][3], true)
end

T["remembered_file_states"]["can restore hunk state on re-expand"] = function()
  local remembered_file_states = {}
  local expanded_files = {}

  -- Simulate: user has hunks 1 and 3 expanded, then collapses file
  local original_state = { [1] = true, [3] = true }
  remembered_file_states["unstaged:file.lua"] = vim.deepcopy(original_state)
  expanded_files["unstaged:file.lua"] = false -- collapsed

  -- Later: user re-expands the file
  local remembered = remembered_file_states["unstaged:file.lua"]
  if remembered then
    expanded_files["unstaged:file.lua"] = vim.deepcopy(remembered)
  else
    expanded_files["unstaged:file.lua"] = true -- default to fully expanded
  end

  -- Verify restored state
  eq(type(expanded_files["unstaged:file.lua"]), "table")
  eq(expanded_files["unstaged:file.lua"][1], true)
  eq(expanded_files["unstaged:file.lua"][3], true)
end

T["remembered_file_states"]["defaults to fully expanded when no memory"] = function()
  local remembered_file_states = {}
  local expanded_files = {}

  -- No prior state
  local remembered = remembered_file_states["unstaged:file.lua"]
  if remembered then
    expanded_files["unstaged:file.lua"] = vim.deepcopy(remembered)
  else
    expanded_files["unstaged:file.lua"] = true -- default to fully expanded
  end

  eq(expanded_files["unstaged:file.lua"], true)
end

T["remembered_file_states"]["preserves state across multiple collapse/expand cycles"] = function()
  local remembered_file_states = {}
  local expanded_files = {}

  -- First expansion: all hunks expanded
  expanded_files["unstaged:file.lua"] = true

  -- User collapses hunk 2
  expanded_files["unstaged:file.lua"] = { [1] = true, [3] = true }

  -- User collapses file - save state
  remembered_file_states["unstaged:file.lua"] = vim.deepcopy(expanded_files["unstaged:file.lua"])
  expanded_files["unstaged:file.lua"] = false

  -- User re-expands file - restore state
  expanded_files["unstaged:file.lua"] = vim.deepcopy(remembered_file_states["unstaged:file.lua"])

  -- User collapses file again
  remembered_file_states["unstaged:file.lua"] = vim.deepcopy(expanded_files["unstaged:file.lua"])
  expanded_files["unstaged:file.lua"] = false

  -- Verify state still preserved
  eq(remembered_file_states["unstaged:file.lua"][1], true)
  eq(remembered_file_states["unstaged:file.lua"][2], nil)
  eq(remembered_file_states["unstaged:file.lua"][3], true)
end

T["remembered_section_states"] = MiniTest.new_set()

T["remembered_section_states"]["stores file expansion states by section"] = function()
  local remembered_section_states = {}

  -- Save file states when collapsing a section
  remembered_section_states["stashes"] = {
    files = {
      ["stashes:stash@{0}"] = true,
      ["stashes:stash@{1}"] = { [1] = true },
    },
  }

  -- Verify storage
  eq(remembered_section_states["stashes"].files["stashes:stash@{0}"], true)
  eq(type(remembered_section_states["stashes"].files["stashes:stash@{1}"]), "table")
end

T["remembered_section_states"]["can restore file states on section re-expand"] = function()
  local remembered_section_states = {}
  local expanded_files = {}
  local collapsed_sections = {}

  -- Simulate: user has some files expanded in section, then collapses section
  expanded_files["unstaged:file1.lua"] = true
  expanded_files["unstaged:file2.lua"] = { [1] = true }
  expanded_files["staged:other.lua"] = true -- Different section

  -- Save unstaged section state before collapsing
  local files_in_section = {}
  for key, state in pairs(expanded_files) do
    if key:match("^unstaged:") then
      files_in_section[key] = vim.deepcopy(state)
    end
  end
  remembered_section_states["unstaged"] = { files = files_in_section }
  collapsed_sections["unstaged"] = true

  -- Clear expansion states for collapsed section
  for key, _ in pairs(expanded_files) do
    if key:match("^unstaged:") then
      expanded_files[key] = nil
    end
  end

  -- Later: user re-expands the section
  collapsed_sections["unstaged"] = false
  local remembered = remembered_section_states["unstaged"]
  if remembered and remembered.files then
    for key, state in pairs(remembered.files) do
      expanded_files[key] = vim.deepcopy(state)
    end
  end

  -- Verify restored states
  eq(expanded_files["unstaged:file1.lua"], true)
  eq(type(expanded_files["unstaged:file2.lua"]), "table")
  eq(expanded_files["unstaged:file2.lua"][1], true)
  -- Other section unchanged
  eq(expanded_files["staged:other.lua"], true)
end

T["remembered_section_states"]["works independently for each section"] = function()
  local remembered_section_states = {}

  remembered_section_states["stashes"] = { files = { ["stashes:stash@{0}"] = true } }
  remembered_section_states["recent"] = { files = {} }
  remembered_section_states["unpushed_upstream"] =
    { files = { ["unpushed_upstream:abc123"] = true } }

  eq(remembered_section_states["stashes"].files["stashes:stash@{0}"], true)
  eq(remembered_section_states["recent"].files["recent:abc123"], nil)
  eq(remembered_section_states["unpushed_upstream"].files["unpushed_upstream:abc123"], true)
end

T["expansion state interactions"] = MiniTest.new_set()

T["expansion state interactions"]["file memory is separate from section memory"] = function()
  -- File memory tracks hunk states within a file
  -- Section memory tracks which files were expanded when section collapsed
  local remembered_file_states = {}
  local remembered_section_states = {}

  -- User has file1 with hunks 1,2 expanded
  remembered_file_states["unstaged:file1.lua"] = { [1] = true, [2] = true }

  -- User collapses section while file1 was expanded
  remembered_section_states["unstaged"] = {
    files = { ["unstaged:file1.lua"] = true },
  }

  -- These are independent - section memory says "file was expanded"
  -- file memory says "which hunks were expanded in that file"
  eq(remembered_section_states["unstaged"].files["unstaged:file1.lua"], true)
  eq(remembered_file_states["unstaged:file1.lua"][1], true)
  eq(remembered_file_states["unstaged:file1.lua"][2], true)
end

T["expansion state interactions"]["cache key format is section:path"] = function()
  -- Verify the cache key format used throughout
  local section = "staged"
  local path = "lua/test.lua"
  local key = section .. ":" .. path

  eq(key, "staged:lua/test.lua")

  -- Same path in different sections should have different keys
  local unstaged_key = "unstaged:" .. path
  local staged_key = "staged:" .. path

  expect.no_equality(unstaged_key, staged_key)
end

return T
