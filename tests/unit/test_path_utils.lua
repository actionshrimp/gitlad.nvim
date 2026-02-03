-- Tests for gitlad.utils.path module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["format_rename"] = MiniTest.new_set()

T["format_rename"]["handles simple file rename in same directory"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("old.txt", "new.txt"), "{old.txt => new.txt}")
end

T["format_rename"]["handles rename with common directory prefix"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("dir/old.txt", "dir/new.txt"), "dir/{old.txt => new.txt}")
end

T["format_rename"]["handles rename with deep common prefix"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("a/b/c/old.txt", "a/b/c/new.txt"), "a/b/c/{old.txt => new.txt}")
end

T["format_rename"]["handles rename with common suffix"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("a/b/file.txt", "a/c/file.txt"), "a/{b => c}/file.txt")
end

T["format_rename"]["handles rename with deep common suffix"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("old/path/to/file.txt", "new/path/to/file.txt"), "{old => new}/path/to/file.txt")
end

T["format_rename"]["handles rename with no common parts"] = function()
  local path = require("gitlad.utils.path")

  eq(
    path.format_rename("olddir/sub/file.txt", "newdir/other/renamed.txt"),
    "{olddir/sub/file.txt => newdir/other/renamed.txt}"
  )
end

T["format_rename"]["handles identical paths"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("same/path.txt", "same/path.txt"), "same/path.txt")
end

T["format_rename"]["handles nil orig path"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename(nil, "new.txt"), "new.txt")
end

T["format_rename"]["handles nil new path"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("old.txt", nil), "old.txt")
end

T["format_rename"]["handles both nil paths"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename(nil, nil), "")
end

T["format_rename"]["handles move between sibling directories"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("src/old/module.lua", "src/new/module.lua"), "src/{old => new}/module.lua")
end

T["format_rename"]["handles move with both prefix and suffix match"] = function()
  local path = require("gitlad.utils.path")

  eq(
    path.format_rename("project/src/old/utils/helper.lua", "project/src/new/utils/helper.lua"),
    "project/src/{old => new}/utils/helper.lua"
  )
end

T["format_rename"]["handles simple rename at root with extension"] = function()
  local path = require("gitlad.utils.path")

  eq(path.format_rename("config.json", "settings.json"), "{config.json => settings.json}")
end

T["format_rename"]["handles directory move (path with trailing content)"] = function()
  local path = require("gitlad.utils.path")

  -- Moving file from one directory structure to another
  eq(path.format_rename("lib/old.lua", "src/new.lua"), "{lib/old.lua => src/new.lua}")
end

T["format_rename"]["handles partial directory match"] = function()
  local path = require("gitlad.utils.path")

  -- Only first directory matches
  eq(path.format_rename("shared/a/b/file.txt", "shared/x/y/file.txt"), "shared/{a/b => x/y}/file.txt")
end

return T
