local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local sections = require("gitlad.ui.views.status_sections")
local config = require("gitlad.config")

T["normalize_section"] = MiniTest.new_set()

T["normalize_section"]["handles string input"] = function()
  local name, opts = sections.normalize_section("staged")
  eq(name, "staged")
  eq(opts, {})
end

T["normalize_section"]["handles table with name only"] = function()
  local name, opts = sections.normalize_section({ "staged" })
  eq(name, "staged")
  eq(opts, {})
end

T["normalize_section"]["handles table with options"] = function()
  local name, opts = sections.normalize_section({ "recent", count = 5 })
  eq(name, "recent")
  eq(opts.count, 5)
end

T["normalize_section"]["handles table with multiple options"] = function()
  local name, opts = sections.normalize_section({ "recent", count = 10, foo = "bar" })
  eq(name, "recent")
  eq(opts.count, 10)
  eq(opts.foo, "bar")
end

T["normalize_section"]["handles empty/nil gracefully"] = function()
  local name, opts = sections.normalize_section({})
  eq(name, nil)
  eq(opts, {})
end

T["get_sections"] = MiniTest.new_set()

T["get_sections"]["returns default sections when not configured"] = function()
  config.reset()
  config.setup({})

  local result = sections.get_sections()
  eq(result, sections.DEFAULT_SECTIONS)
end

T["get_sections"]["returns custom sections when configured"] = function()
  config.reset()
  config.setup({
    status = {
      sections = { "staged", "unstaged" },
    },
  })

  local result = sections.get_sections()
  eq(result, { "staged", "unstaged" })

  -- Reset for other tests
  config.reset()
end

T["get_sections"]["returns sections with options"] = function()
  config.reset()
  config.setup({
    status = {
      sections = { "staged", { "recent", count = 5 } },
    },
  })

  local result = sections.get_sections()
  eq(#result, 2)
  eq(result[1], "staged")
  eq(result[2][1], "recent")
  eq(result[2].count, 5)

  -- Reset for other tests
  config.reset()
end

T["has_file_changes"] = MiniTest.new_set()

T["has_file_changes"]["returns false for empty status"] = function()
  local status = {
    staged = {},
    unstaged = {},
    untracked = {},
    conflicted = {},
  }
  eq(sections.has_file_changes(status), false)
end

T["has_file_changes"]["returns true if staged files exist"] = function()
  local status = {
    staged = { { path = "file.txt" } },
    unstaged = {},
    untracked = {},
    conflicted = {},
  }
  eq(sections.has_file_changes(status), true)
end

T["has_file_changes"]["returns true if unstaged files exist"] = function()
  local status = {
    staged = {},
    unstaged = { { path = "file.txt" } },
    untracked = {},
    conflicted = {},
  }
  eq(sections.has_file_changes(status), true)
end

T["has_file_changes"]["returns true if untracked files exist"] = function()
  local status = {
    staged = {},
    unstaged = {},
    untracked = { { path = "file.txt" } },
    conflicted = {},
  }
  eq(sections.has_file_changes(status), true)
end

T["has_file_changes"]["returns true if conflicted files exist"] = function()
  local status = {
    staged = {},
    unstaged = {},
    untracked = {},
    conflicted = { { path = "file.txt" } },
  }
  eq(sections.has_file_changes(status), true)
end

T["DEFAULT_SECTIONS"] = MiniTest.new_set()

T["DEFAULT_SECTIONS"]["contains all expected sections"] = function()
  local defaults = sections.DEFAULT_SECTIONS
  -- Note: submodules excluded by default (like magit)
  -- worktrees has min_count option
  eq(#defaults, 9)
  eq(defaults[1], "untracked")
  eq(defaults[2], "unstaged")
  eq(defaults[3], "staged")
  eq(defaults[4], "conflicted")
  eq(defaults[5], "stashes")
  -- worktrees is a table with min_count option
  eq(type(defaults[6]), "table")
  eq(defaults[6][1], "worktrees")
  eq(defaults[6].min_count, 2)
  eq(defaults[7], "unpushed")
  eq(defaults[8], "unpulled")
  eq(defaults[9], "recent")
end

T["SECTION_DEFS"] = MiniTest.new_set()

T["SECTION_DEFS"]["has render functions for all default sections"] = function()
  for _, section in ipairs(sections.DEFAULT_SECTIONS) do
    -- Handle both string and table section configs
    local name = sections.normalize_section(section)
    local def = sections.SECTION_DEFS[name]
    expect.no_equality(def, nil)
    eq(type(def.render), "function")
  end
end

return T
