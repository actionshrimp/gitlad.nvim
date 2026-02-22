local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local tree = require("gitlad.ui.views.diff.tree")

--- Helper to create a mock DiffFilePair
---@param overrides? table
---@return DiffFilePair
local function make_pair(overrides)
  overrides = overrides or {}
  return vim.tbl_deep_extend("force", {
    old_path = "file.lua",
    new_path = "file.lua",
    status = "M",
    hunks = {},
    additions = 0,
    deletions = 0,
    is_binary = false,
  }, overrides)
end

-- =============================================================================
-- build_tree
-- =============================================================================

T["build_tree"] = MiniTest.new_set()

T["build_tree"]["returns empty root for empty list"] = function()
  local root = tree.build_tree({})
  eq(root.is_dir, true)
  eq(next(root.children), nil)
end

T["build_tree"]["creates file node at root for simple filename"] = function()
  local root = tree.build_tree({ make_pair({ new_path = "file.lua" }) })
  expect.equality(root.children["file.lua"] ~= nil, true)
  eq(root.children["file.lua"].is_dir, false)
  eq(root.children["file.lua"].file_index, 1)
  eq(root.children["file.lua"].status, "M")
end

T["build_tree"]["creates intermediate directory nodes"] = function()
  local root = tree.build_tree({ make_pair({ new_path = "src/auth.lua" }) })
  expect.equality(root.children["src"] ~= nil, true)
  eq(root.children["src"].is_dir, true)
  eq(root.children["src"].path, "src")
  expect.equality(root.children["src"].children["auth.lua"] ~= nil, true)
  eq(root.children["src"].children["auth.lua"].file_index, 1)
end

T["build_tree"]["shares directory nodes for files in same dir"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/a.lua" }),
    make_pair({ new_path = "src/b.lua" }),
  })
  eq(root.children["src"].is_dir, true)
  expect.equality(root.children["src"].children["a.lua"] ~= nil, true)
  expect.equality(root.children["src"].children["b.lua"] ~= nil, true)
  eq(root.children["src"].children["a.lua"].file_index, 1)
  eq(root.children["src"].children["b.lua"].file_index, 2)
end

T["build_tree"]["creates deep directory chain"] = function()
  local root = tree.build_tree({ make_pair({ new_path = "a/b/c/file.lua" }) })
  eq(root.children["a"].is_dir, true)
  eq(root.children["a"].path, "a")
  eq(root.children["a"].children["b"].is_dir, true)
  eq(root.children["a"].children["b"].path, "a/b")
  eq(root.children["a"].children["b"].children["c"].is_dir, true)
  eq(root.children["a"].children["b"].children["c"].path, "a/b/c")
  eq(root.children["a"].children["b"].children["c"].children["file.lua"].file_index, 1)
end

T["build_tree"]["uses new_path for tree placement"] = function()
  local root = tree.build_tree({
    make_pair({ status = "R", old_path = "old/file.lua", new_path = "new/file.lua" }),
  })
  -- File should be under new/, not old/
  expect.equality(root.children["old"], nil)
  expect.equality(root.children["new"] ~= nil, true)
  eq(root.children["new"].children["file.lua"].file_index, 1)
end

T["build_tree"]["falls back to old_path when new_path is empty"] = function()
  local root = tree.build_tree({
    make_pair({ old_path = "src/deleted.lua", new_path = "", status = "D" }),
  })
  expect.equality(root.children["src"] ~= nil, true)
  eq(root.children["src"].children["deleted.lua"].file_index, 1)
end

T["build_tree"]["preserves file_index for multiple files"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "z.lua" }),
    make_pair({ new_path = "a.lua" }),
    make_pair({ new_path = "m.lua" }),
  })
  eq(root.children["z.lua"].file_index, 1)
  eq(root.children["a.lua"].file_index, 2)
  eq(root.children["m.lua"].file_index, 3)
end

-- =============================================================================
-- flatten
-- =============================================================================

T["flatten"] = MiniTest.new_set()

T["flatten"]["returns empty list for empty tree"] = function()
  local root = tree.build_tree({})
  local entries = tree.flatten(root)
  eq(#entries, 0)
end

T["flatten"]["single root-level file produces one file entry, no dir"] = function()
  local root = tree.build_tree({ make_pair({ new_path = "file.lua" }) })
  local entries = tree.flatten(root)
  eq(#entries, 1)
  eq(entries[1].type, "file")
  eq(entries[1].name, "file.lua")
  eq(entries[1].depth, 0)
  eq(entries[1].file_index, 1)
end

T["flatten"]["files under same dir produce one dir + files"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/a.lua" }),
    make_pair({ new_path = "src/b.lua" }),
  })
  local entries = tree.flatten(root)
  eq(#entries, 3)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "src")
  eq(entries[1].depth, 0)
  eq(entries[2].type, "file")
  eq(entries[2].name, "a.lua")
  eq(entries[2].depth, 1)
  eq(entries[2].file_index, 1)
  eq(entries[3].type, "file")
  eq(entries[3].name, "b.lua")
  eq(entries[3].depth, 1)
  eq(entries[3].file_index, 2)
end

T["flatten"]["single-child dir flattening merges a/b into a/b"] = function()
  local root = tree.build_tree({ make_pair({ new_path = "a/b/file.lua" }) })
  local entries = tree.flatten(root)
  eq(#entries, 2)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "a/b")
  eq(entries[1].path, "a/b")
  eq(entries[1].depth, 0)
  eq(entries[2].type, "file")
  eq(entries[2].name, "file.lua")
  eq(entries[2].depth, 1)
end

T["flatten"]["multi-level single-child flatten chain"] = function()
  local root = tree.build_tree({ make_pair({ new_path = "a/b/c/d/file.lua" }) })
  local entries = tree.flatten(root)
  eq(#entries, 2)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "a/b/c/d")
  eq(entries[1].path, "a/b/c/d")
  eq(entries[2].type, "file")
  eq(entries[2].name, "file.lua")
  eq(entries[2].depth, 1)
end

T["flatten"]["mixed: some dirs flatten, some don't"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "a/b/c.lua" }),
    make_pair({ new_path = "a/b/d.lua" }),
    make_pair({ new_path = "x/y/z/file.lua" }),
  })
  local entries = tree.flatten(root)

  -- a has one child b (dir), b has 2 children -> a flattens to a/b
  -- x has one child y, y has one child z, z has one child file.lua (FILE, not dir) -> x/y/z
  eq(entries[1].type, "dir")
  eq(entries[1].name, "a/b")
  eq(entries[2].type, "file")
  eq(entries[2].name, "c.lua")
  eq(entries[3].type, "file")
  eq(entries[3].name, "d.lua")
  eq(entries[4].type, "dir")
  eq(entries[4].name, "x/y/z")
  eq(entries[5].type, "file")
  eq(entries[5].name, "file.lua")
  eq(#entries, 5)
end

T["flatten"]["correct depth values for nested structure"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/lib/auth.lua" }),
    make_pair({ new_path = "src/lib/utils.lua" }),
    make_pair({ new_path = "src/main.lua" }),
  })
  local entries = tree.flatten(root)

  -- src has 2 children: lib (dir) and main.lua (file)
  -- lib doesn't flatten because src has multiple children... wait
  -- Actually: src has children: lib (dir), main.lua (file) = 2 children
  -- So src doesn't flatten. src appears at depth 0.
  -- Under src: lib (dir, depth 1), main.lua (file, depth 1)
  -- Under lib: auth.lua (depth 2), utils.lua (depth 2)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "src")
  eq(entries[1].depth, 0)
  eq(entries[2].type, "dir")
  eq(entries[2].name, "lib")
  eq(entries[2].depth, 1)
  eq(entries[3].type, "file")
  eq(entries[3].name, "auth.lua")
  eq(entries[3].depth, 2)
  eq(entries[4].type, "file")
  eq(entries[4].name, "utils.lua")
  eq(entries[4].depth, 2)
  eq(entries[5].type, "file")
  eq(entries[5].name, "main.lua")
  eq(entries[5].depth, 1)
end

T["flatten"]["sort order: dirs before files, alphabetical"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "z.lua" }),
    make_pair({ new_path = "a.lua" }),
    make_pair({ new_path = "lib/x.lua" }),
    make_pair({ new_path = "abc/y.lua" }),
  })
  local entries = tree.flatten(root)

  -- Dirs first (abc, lib), then files (a.lua, z.lua)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "abc")
  eq(entries[2].type, "file")
  eq(entries[2].name, "y.lua")
  eq(entries[3].type, "dir")
  eq(entries[3].name, "lib")
  eq(entries[4].type, "file")
  eq(entries[4].name, "x.lua")
  eq(entries[5].type, "file")
  eq(entries[5].name, "a.lua")
  eq(entries[6].type, "file")
  eq(entries[6].name, "z.lua")
end

T["flatten"]["collapse hides children"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/a.lua" }),
    make_pair({ new_path = "src/b.lua" }),
  })
  local entries = tree.flatten(root, { ["src"] = true })

  eq(#entries, 1)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "src")
  eq(entries[1].is_collapsed, true)
end

T["flatten"]["collapse parent hides all descendants"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/lib/auth.lua" }),
    make_pair({ new_path = "src/lib/utils.lua" }),
    make_pair({ new_path = "src/main.lua" }),
  })
  -- Collapse src (which has lib/ and main.lua as children)
  local entries = tree.flatten(root, { ["src"] = true })

  eq(#entries, 1)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "src")
  eq(entries[1].is_collapsed, true)
end

T["flatten"]["collapse flattened dir uses innermost path as key"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "a/b/c.lua" }),
    make_pair({ new_path = "a/b/d.lua" }),
  })
  -- The dir "a/b" is flattened from a -> b. Collapse key is "a/b" (innermost path).
  local entries = tree.flatten(root, { ["a/b"] = true })

  eq(#entries, 1)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "a/b")
  eq(entries[1].is_collapsed, true)
end

T["flatten"]["collapsing intermediate path does not affect flattened dir"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "a/b/c.lua" }),
    make_pair({ new_path = "a/b/d.lua" }),
  })
  -- Collapsing just "a" has no effect because the flattened dir key is "a/b"
  local entries = tree.flatten(root, { ["a"] = true })

  eq(#entries, 3) -- dir(a/b) + c.lua + d.lua
  eq(entries[1].is_collapsed, false)
end

T["flatten"]["renamed file placed under new_path dir, preserves file_index"] = function()
  local root = tree.build_tree({
    make_pair({ status = "R", old_path = "old/file.lua", new_path = "new/file.lua" }),
  })
  local entries = tree.flatten(root)

  eq(#entries, 2)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "new")
  eq(entries[2].type, "file")
  eq(entries[2].name, "file.lua")
  eq(entries[2].file_index, 1)
  eq(entries[2].status, "R")
end

T["flatten"]["file_index correctly maps through tree"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "z/third.lua" }),
    make_pair({ new_path = "a/first.lua" }),
    make_pair({ new_path = "root.lua" }),
  })
  local entries = tree.flatten(root)

  -- Sort: dirs first (a, z), then files (root.lua)
  -- a/first.lua has file_index=2, z/third.lua has file_index=1, root.lua has file_index=3
  eq(entries[1].type, "dir")
  eq(entries[1].name, "a")
  eq(entries[2].type, "file")
  eq(entries[2].file_index, 2) -- a/first.lua was pair #2
  eq(entries[3].type, "dir")
  eq(entries[3].name, "z")
  eq(entries[4].type, "file")
  eq(entries[4].file_index, 1) -- z/third.lua was pair #1
  eq(entries[5].type, "file")
  eq(entries[5].file_index, 3) -- root.lua was pair #3
end

T["flatten"]["preserves status on file entries"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "a.lua", status = "M" }),
    make_pair({ new_path = "b.lua", status = "A" }),
    make_pair({ new_path = "c.lua", status = "D" }),
  })
  local entries = tree.flatten(root)

  eq(entries[1].status, "M")
  eq(entries[2].status, "A")
  eq(entries[3].status, "D")
end

T["flatten"]["dir entries have nil file_index and status"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/file.lua" }),
  })
  local entries = tree.flatten(root)

  eq(entries[1].type, "dir")
  eq(entries[1].file_index, nil)
  eq(entries[1].status, nil)
end

T["flatten"]["expanded dir has is_collapsed false"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/file.lua" }),
  })
  local entries = tree.flatten(root, {})

  eq(entries[1].type, "dir")
  eq(entries[1].is_collapsed, false)
end

T["flatten"]["file entries have nil is_collapsed"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "file.lua" }),
  })
  local entries = tree.flatten(root)

  eq(entries[1].type, "file")
  eq(entries[1].is_collapsed, nil)
end

T["flatten"]["only collapses the targeted dir, siblings remain expanded"] = function()
  local root = tree.build_tree({
    make_pair({ new_path = "src/a.lua" }),
    make_pair({ new_path = "lib/b.lua" }),
  })
  local entries = tree.flatten(root, { ["src"] = true })

  -- src collapsed (1 entry), lib expanded (dir + file = 2 entries)
  eq(#entries, 3)
  eq(entries[1].type, "dir")
  eq(entries[1].name, "lib")
  eq(entries[1].is_collapsed, false)
  eq(entries[2].type, "file")
  eq(entries[2].name, "b.lua")
  eq(entries[3].type, "dir")
  eq(entries[3].name, "src")
  eq(entries[3].is_collapsed, true)
end

return T
