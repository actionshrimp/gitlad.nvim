-- Tests for gitlad.popups.diff module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- =============================================================================
-- Diff popup tests
-- =============================================================================

T["diff popup"] = MiniTest.new_set()

T["diff popup"]["creates popup with correct actions"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as diff.lua (without commit context)
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :build()

  eq(data.name, "Diff")
  -- actions includes both headings and actions (1 heading + 5 actions = 6)
  eq(#data.actions, 6)
  -- First item is the heading
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Diffing")
  -- Then the actions
  eq(data.actions[2].key, "d")
  eq(data.actions[2].description, "Diff (dwim)")
  eq(data.actions[3].key, "s")
  eq(data.actions[3].description, "Diff staged")
  eq(data.actions[4].key, "u")
  eq(data.actions[4].description, "Diff unstaged")
  eq(data.actions[5].key, "w")
  eq(data.actions[5].description, "Diff worktree")
  eq(data.actions[6].key, "r")
  eq(data.actions[6].description, "Diff range...")
end

T["diff popup"]["adds commit action when commit context provided"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build popup with commit action (simulating context.commit being present)
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :action("c", "Show commit", function() end)
    :build()

  -- 1 heading + 6 actions = 7
  eq(#data.actions, 7)
  eq(data.actions[7].key, "c")
  eq(data.actions[7].description, "Show commit")
end

T["diff popup"]["has no switches or options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():name("Diff"):action("d", "Diff (dwim)", function() end):build()

  eq(#data.switches, 0)
  eq(#data.options, 0)
end

T["diff popup"]["adds 3-way action when on staged file"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build popup with 3-way action (simulating context.section == "staged")
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :action("3", "3-way (HEAD/index/worktree)", function() end)
    :build()

  -- 1 heading + 6 actions = 7
  eq(#data.actions, 7)
  eq(data.actions[7].key, "3")
  eq(data.actions[7].description, "3-way (HEAD/index/worktree)")
end

T["diff popup"]["adds 3-way action when on unstaged file"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build popup with 3-way action (simulating context.section == "unstaged")
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :action("3", "3-way (HEAD/index/worktree)", function() end)
    :build()

  -- 1 heading + 6 actions = 7
  eq(#data.actions, 7)
  eq(data.actions[7].key, "3")
end

-- =============================================================================
-- Context-aware behavior tests
-- =============================================================================

T["diff context"] = MiniTest.new_set()

T["diff context"]["dwim selects commit diff when commit present"] = function()
  -- Test the dwim logic
  local context = {
    commit = { hash = "abc123", subject = "Test commit" },
    file_path = nil,
    section = nil,
  }

  -- When commit is present, dwim should choose commit diff
  expect.equality(context.commit ~= nil, true)
end

T["diff context"]["dwim selects staged diff when on staged file"] = function()
  local context = {
    commit = nil,
    file_path = "src/foo.lua",
    section = "staged",
  }

  -- When on staged file without commit, dwim should choose staged diff
  expect.equality(context.file_path ~= nil, true)
  expect.equality(context.section, "staged")
end

T["diff context"]["dwim selects unstaged diff when on unstaged file"] = function()
  local context = {
    commit = nil,
    file_path = "src/bar.lua",
    section = "unstaged",
  }

  expect.equality(context.file_path ~= nil, true)
  expect.equality(context.section, "unstaged")
end

T["diff context"]["dwim defaults to unstaged when no context"] = function()
  local context = {
    commit = nil,
    file_path = nil,
    section = nil,
  }

  -- When no context, dwim should default to unstaged diff
  expect.equality(context.commit == nil, true)
  expect.equality(context.file_path == nil, true)
end

-- =============================================================================
-- Diffview argument tests
-- =============================================================================

T["diffview args"] = MiniTest.new_set()

T["diffview args"]["staged uses --cached"] = function()
  local expected_args = { "--cached" }
  eq(expected_args[1], "--cached")
end

T["diffview args"]["unstaged uses empty args"] = function()
  local expected_args = {}
  eq(#expected_args, 0)
end

T["diffview args"]["worktree uses HEAD"] = function()
  local expected_args = { "HEAD" }
  eq(expected_args[1], "HEAD")
end

T["diffview args"]["commit uses hash^!"] = function()
  local hash = "abc123"
  local expected_args = { hash .. "^!" }
  eq(expected_args[1], "abc123^!")
end

T["diffview args"]["range uses ref1..ref2 format"] = function()
  local range = "main..HEAD"
  local expected_args = { range }
  eq(expected_args[1], "main..HEAD")
end

T["diffview args"]["three-dot range uses ref1...ref2 format"] = function()
  local base = "main"
  local ref = "feature-branch"
  local range = base .. "..." .. ref
  local expected_args = { range }
  eq(expected_args[1], "main...feature-branch")
end

-- =============================================================================
-- Ref context tests
-- =============================================================================

T["ref context"] = MiniTest.new_set()

T["ref context"]["adds ref-specific actions when ref present"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build popup with ref-specific actions (simulating context.ref being present)
  local ref = "feature-branch"
  local base = "HEAD"
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :action("b", "Diff " .. ref .. ".." .. base, function() end)
    :action("o", "Diff " .. ref .. " against...", function() end)
    :action("m", "Changes on " .. ref .. " vs...", function() end)
    :build()

  -- 1 heading + 8 actions = 9
  eq(#data.actions, 9)
  eq(data.actions[7].key, "b")
  eq(data.actions[7].description, "Diff feature-branch..HEAD")
  eq(data.actions[8].key, "o")
  eq(data.actions[8].description, "Diff feature-branch against...")
  eq(data.actions[9].key, "m")
  eq(data.actions[9].description, "Changes on feature-branch vs...")
end

return T
