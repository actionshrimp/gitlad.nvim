-- Tests for gitlad.state.reducer module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- Helper to create minimal status
local function make_status(overrides)
  return vim.tbl_deep_extend("force", {
    branch = "main",
    oid = "abc123",
    upstream = nil,
    ahead = 0,
    behind = 0,
    staged = {},
    unstaged = {},
    untracked = {},
    conflicted = {},
  }, overrides or {})
end

T["apply"] = MiniTest.new_set()

T["apply"]["stage_file from untracked"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    untracked = { { path = "new.txt", index_status = "?", worktree_status = "?" } },
  })

  local cmd = commands.stage_file("new.txt", "untracked")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.untracked, 0)
  eq(#new_status.staged, 1)
  eq(new_status.staged[1].path, "new.txt")
  eq(new_status.staged[1].index_status, "A")
  eq(new_status.staged[1].worktree_status, ".")
end

T["apply"]["stage_file from unstaged"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    unstaged = { { path = "mod.txt", index_status = ".", worktree_status = "M" } },
  })

  local cmd = commands.stage_file("mod.txt", "unstaged")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.unstaged, 0)
  eq(#new_status.staged, 1)
  eq(new_status.staged[1].path, "mod.txt")
  eq(new_status.staged[1].index_status, "M")
  eq(new_status.staged[1].worktree_status, ".")
end

T["apply"]["stage_file partially staged file"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  -- File is in both staged and unstaged (MM status)
  local status = make_status({
    staged = { { path = "both.txt", index_status = "M", worktree_status = "M" } },
    unstaged = { { path = "both.txt", index_status = "M", worktree_status = "M" } },
  })

  local cmd = commands.stage_file("both.txt", "unstaged")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.unstaged, 0)
  eq(#new_status.staged, 1)
  eq(new_status.staged[1].path, "both.txt")
  eq(new_status.staged[1].worktree_status, ".")
end

T["apply"]["stage_file nonexistent file is no-op"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    unstaged = { { path = "other.txt", index_status = ".", worktree_status = "M" } },
  })

  local cmd = commands.stage_file("nonexistent.txt", "unstaged")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.unstaged, 1)
  eq(#new_status.staged, 0)
end

T["apply"]["unstage_file added file becomes untracked"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = { { path = "new.txt", index_status = "A", worktree_status = "." } },
  })

  local cmd = commands.unstage_file("new.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 0)
  eq(#new_status.untracked, 1)
  eq(new_status.untracked[1].path, "new.txt")
  eq(new_status.untracked[1].index_status, "?")
  eq(new_status.untracked[1].worktree_status, "?")
end

T["apply"]["unstage_file modified file goes to unstaged"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = { { path = "mod.txt", index_status = "M", worktree_status = "." } },
  })

  local cmd = commands.unstage_file("mod.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 0)
  eq(#new_status.unstaged, 1)
  eq(new_status.unstaged[1].path, "mod.txt")
  eq(new_status.unstaged[1].index_status, ".")
  eq(new_status.unstaged[1].worktree_status, "M")
end

T["apply"]["unstage_file deleted file goes to unstaged"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = { { path = "del.txt", index_status = "D", worktree_status = "." } },
  })

  local cmd = commands.unstage_file("del.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 0)
  eq(#new_status.unstaged, 1)
  eq(new_status.unstaged[1].worktree_status, "D")
end

T["apply"]["unstage_file partially staged updates unstaged entry"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  -- File has staged changes AND unstaged changes
  local status = make_status({
    staged = { { path = "both.txt", index_status = "M", worktree_status = "M" } },
    unstaged = { { path = "both.txt", index_status = "M", worktree_status = "M" } },
  })

  local cmd = commands.unstage_file("both.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 0)
  eq(#new_status.unstaged, 1)
  eq(new_status.unstaged[1].index_status, ".")
end

T["apply"]["unstage_file nonexistent file is no-op"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = { { path = "other.txt", index_status = "M", worktree_status = "." } },
  })

  local cmd = commands.unstage_file("nonexistent.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 1)
end

T["apply"]["refresh replaces entire status"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local old_status = make_status({
    staged = { { path = "old.txt", index_status = "A", worktree_status = "." } },
  })

  local new_git_status = make_status({
    branch = "feature",
    unstaged = { { path = "different.txt", index_status = ".", worktree_status = "M" } },
  })

  local cmd = commands.refresh(new_git_status)
  local new_status = reducer.apply(old_status, cmd)

  eq(#new_status.staged, 0)
  eq(#new_status.unstaged, 1)
  eq(new_status.unstaged[1].path, "different.txt")
  eq(new_status.branch, "feature")
end

T["apply"]["stage_all stages everything"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    unstaged = {
      { path = "mod1.txt", index_status = ".", worktree_status = "M" },
      { path = "mod2.txt", index_status = ".", worktree_status = "D" },
    },
    untracked = {
      { path = "new.txt", index_status = "?", worktree_status = "?" },
    },
  })

  local cmd = commands.stage_all()
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.unstaged, 0)
  eq(#new_status.untracked, 0)
  eq(#new_status.staged, 3)
end

T["apply"]["unstage_all unstages everything"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = {
      { path = "mod.txt", index_status = "M", worktree_status = "." },
      { path = "new.txt", index_status = "A", worktree_status = "." },
    },
  })

  local cmd = commands.unstage_all()
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 0)
  eq(#new_status.unstaged, 1)
  eq(new_status.unstaged[1].path, "mod.txt")
  eq(#new_status.untracked, 1)
  eq(new_status.untracked[1].path, "new.txt")
end

T["immutability"] = MiniTest.new_set()

T["immutability"]["apply does not modify input status"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    unstaged = { { path = "file.txt", index_status = ".", worktree_status = "M" } },
  })

  local original_count = #status.unstaged
  local cmd = commands.stage_file("file.txt", "unstaged")
  reducer.apply(status, cmd)

  -- Original should be unchanged
  eq(#status.unstaged, original_count)
  eq(status.unstaged[1].path, "file.txt")
end

T["immutability"]["apply does not modify input arrays"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local entry = { path = "file.txt", index_status = ".", worktree_status = "M" }
  local status = make_status({
    unstaged = { entry },
  })

  local cmd = commands.stage_file("file.txt", "unstaged")
  local new_status = reducer.apply(status, cmd)

  -- Original entry should be unchanged
  eq(entry.index_status, ".")
  eq(entry.worktree_status, "M")
  -- New status has different entry
  eq(new_status.staged[1].index_status, "M")
end

T["preserves metadata"] = MiniTest.new_set()

T["preserves metadata"]["stage_file preserves orig_path for renames"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    unstaged = {
      {
        path = "new_name.txt",
        orig_path = "old_name.txt",
        index_status = ".",
        worktree_status = "R",
      },
    },
  })

  local cmd = commands.stage_file("new_name.txt", "unstaged")
  local new_status = reducer.apply(status, cmd)

  eq(new_status.staged[1].orig_path, "old_name.txt")
end

T["preserves metadata"]["stage_file preserves submodule info"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    unstaged = {
      {
        path = "submod",
        index_status = ".",
        worktree_status = "M",
        submodule = "SC..",
      },
    },
  })

  local cmd = commands.stage_file("submod", "unstaged")
  local new_status = reducer.apply(status, cmd)

  eq(new_status.staged[1].submodule, "SC..")
end

T["sort order"] = MiniTest.new_set()

T["sort order"]["stage_file inserts in alphabetical order"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  -- Start with staged files: a.txt, c.txt
  local status = make_status({
    staged = {
      { path = "a.txt", index_status = "M", worktree_status = "." },
      { path = "c.txt", index_status = "M", worktree_status = "." },
    },
    unstaged = {
      { path = "b.txt", index_status = ".", worktree_status = "M" },
    },
  })

  -- Stage b.txt - should be inserted between a.txt and c.txt
  local cmd = commands.stage_file("b.txt", "unstaged")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 3)
  eq(new_status.staged[1].path, "a.txt")
  eq(new_status.staged[2].path, "b.txt")
  eq(new_status.staged[3].path, "c.txt")
end

T["sort order"]["stage_file from untracked inserts in alphabetical order"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = {
      { path = "aaa.txt", index_status = "M", worktree_status = "." },
      { path = "zzz.txt", index_status = "M", worktree_status = "." },
    },
    untracked = {
      { path = "mmm.txt", index_status = "?", worktree_status = "?" },
    },
  })

  local cmd = commands.stage_file("mmm.txt", "untracked")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 3)
  eq(new_status.staged[1].path, "aaa.txt")
  eq(new_status.staged[2].path, "mmm.txt")
  eq(new_status.staged[3].path, "zzz.txt")
end

T["sort order"]["unstage_file inserts in alphabetical order to unstaged"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = {
      { path = "b.txt", index_status = "M", worktree_status = "." },
    },
    unstaged = {
      { path = "a.txt", index_status = ".", worktree_status = "M" },
      { path = "c.txt", index_status = ".", worktree_status = "M" },
    },
  })

  local cmd = commands.unstage_file("b.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.unstaged, 3)
  eq(new_status.unstaged[1].path, "a.txt")
  eq(new_status.unstaged[2].path, "b.txt")
  eq(new_status.unstaged[3].path, "c.txt")
end

T["sort order"]["unstage_file added file inserts in alphabetical order to untracked"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = {
      { path = "new_b.txt", index_status = "A", worktree_status = "." },
    },
    untracked = {
      { path = "new_a.txt", index_status = "?", worktree_status = "?" },
      { path = "new_c.txt", index_status = "?", worktree_status = "?" },
    },
  })

  local cmd = commands.unstage_file("new_b.txt")
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.untracked, 3)
  eq(new_status.untracked[1].path, "new_a.txt")
  eq(new_status.untracked[2].path, "new_b.txt")
  eq(new_status.untracked[3].path, "new_c.txt")
end

T["sort order"]["stage_all maintains alphabetical order"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = {
      { path = "b.txt", index_status = "M", worktree_status = "." },
    },
    unstaged = {
      { path = "d.txt", index_status = ".", worktree_status = "M" },
    },
    untracked = {
      { path = "a.txt", index_status = "?", worktree_status = "?" },
      { path = "c.txt", index_status = "?", worktree_status = "?" },
    },
  })

  local cmd = commands.stage_all()
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.staged, 4)
  eq(new_status.staged[1].path, "a.txt")
  eq(new_status.staged[2].path, "b.txt")
  eq(new_status.staged[3].path, "c.txt")
  eq(new_status.staged[4].path, "d.txt")
end

T["sort order"]["unstage_all maintains alphabetical order"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  local status = make_status({
    staged = {
      { path = "b.txt", index_status = "M", worktree_status = "." },
      { path = "d.txt", index_status = "A", worktree_status = "." },
    },
    unstaged = {
      { path = "c.txt", index_status = ".", worktree_status = "M" },
    },
    untracked = {
      { path = "a.txt", index_status = "?", worktree_status = "?" },
    },
  })

  local cmd = commands.unstage_all()
  local new_status = reducer.apply(status, cmd)

  eq(#new_status.unstaged, 2)
  eq(new_status.unstaged[1].path, "b.txt")
  eq(new_status.unstaged[2].path, "c.txt")

  eq(#new_status.untracked, 2)
  eq(new_status.untracked[1].path, "a.txt")
  eq(new_status.untracked[2].path, "d.txt")
end

return T
