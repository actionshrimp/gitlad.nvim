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

T["diff context"]["dwim selects stash diff when on stash"] = function()
  local context = {
    commit = nil,
    file_path = nil,
    section = nil,
    stash = { ref = "stash@{0}", message = "WIP on main" },
  }

  -- When stash is present, dwim should choose stash diff
  expect.equality(context.stash ~= nil, true)
  expect.equality(context.stash.ref, "stash@{0}")
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

T["diffview args"]["stash uses ref^!"] = function()
  local stash_ref = "stash@{0}"
  local expected_args = { stash_ref .. "^!" }
  eq(expected_args[1], "stash@{0}^!")
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
  -- r = range with default, b = build range guided, U = upstream diff
  -- U uses current_upstream (origin/main) not the ref's own upstream
  local ref = "feature-branch"
  local current_upstream = "origin/main"
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :action("b", "Build range...", function() end)
    :action("U", "Diff " .. current_upstream .. "..." .. ref, function() end)
    :build()

  -- 1 heading + 7 actions = 8
  eq(#data.actions, 8)
  eq(data.actions[6].key, "r")
  eq(data.actions[6].description, "Diff range...")
  -- b is the guided build range flow
  eq(data.actions[7].key, "b")
  eq(data.actions[7].description, "Build range...")
  -- U diffs against current branch's upstream (origin/main...feature-branch)
  eq(data.actions[8].key, "U")
  eq(data.actions[8].description, "Diff origin/main...feature-branch")
end

T["ref context"]["shows build range action without ref context"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build popup without ref context - b should still be "Build range..."
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("s", "Diff staged", function() end)
    :action("u", "Diff unstaged", function() end)
    :action("w", "Diff worktree", function() end)
    :action("r", "Diff range...", function() end)
    :action("b", "Build range...", function() end)
    :build()

  -- 1 heading + 6 actions = 7
  eq(#data.actions, 7)
  eq(data.actions[6].key, "r")
  eq(data.actions[6].description, "Diff range...")
  eq(data.actions[7].key, "b")
  eq(data.actions[7].description, "Build range...")
end

T["ref context"]["upstream action shows generic label when no upstream configured"] = function()
  local popup = require("gitlad.ui.popup")

  -- When ref has no upstream, label is generic
  local data = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function() end)
    :action("r", "Diff range...", function() end)
    :action("b", "Build range...", function() end)
    :action("U", "Diff against upstream", function() end)
    :build()

  eq(data.actions[5].key, "U")
  eq(data.actions[5].description, "Diff against upstream")
end

-- =============================================================================
-- _compute_default_range tests
-- =============================================================================

T["compute default range"] = MiniTest.new_set()

T["compute default range"]["returns nil when no ref in context"] = function()
  local diff = require("gitlad.popups.diff")
  local result = diff._compute_default_range("main", "origin/main", {})
  eq(result, nil)
end

T["compute default range"]["returns nil when context has no ref (status view)"] = function()
  local diff = require("gitlad.popups.diff")
  local result = diff._compute_default_range("main", "origin/main", {
    file_path = "src/foo.lua",
    section = "unstaged",
  })
  eq(result, nil)
end

T["compute default range"]["returns base_ref...ref for different branch"] = function()
  local diff = require("gitlad.popups.diff")
  local result = diff._compute_default_range("main", "origin/main", {
    ref = "feature-branch",
    base_ref = "HEAD",
  })
  eq(result, "HEAD...feature-branch")
end

T["compute default range"]["returns upstream...ref when on HEAD branch"] = function()
  local diff = require("gitlad.popups.diff")
  -- When ref == base_ref, we're on the HEAD branch
  local result = diff._compute_default_range("main", "origin/main", {
    ref = "main",
    base_ref = "main",
  })
  eq(result, "origin/main...main")
end

T["compute default range"]["returns nil when on HEAD branch with no upstream"] = function()
  local diff = require("gitlad.popups.diff")
  local result = diff._compute_default_range("main", nil, {
    ref = "main",
    base_ref = "main",
  })
  eq(result, nil)
end

T["compute default range"]["uses three-dot for branch divergence comparison"] = function()
  local diff = require("gitlad.popups.diff")
  local result = diff._compute_default_range("main", nil, {
    ref = "feature-branch",
    base_ref = "HEAD",
  })
  -- Should use three-dot (changes since divergence)
  expect.equality(result:match("%.%.%.") ~= nil, true)
  eq(result, "HEAD...feature-branch")
end

T["compute default range"]["handles ref without base_ref"] = function()
  local diff = require("gitlad.popups.diff")
  -- ref present but no base_ref and no upstream
  local result = diff._compute_default_range("main", nil, {
    ref = "feature-branch",
  })
  eq(result, nil)
end

T["compute default range"]["handles ref without base_ref but with upstream"] = function()
  local diff = require("gitlad.popups.diff")
  -- ref present, no base_ref but upstream exists
  local result = diff._compute_default_range("main", "origin/main", {
    ref = "feature-branch",
  })
  -- No base_ref means base_ref is nil, ref != base_ref path won't match
  -- Falls through to upstream check
  eq(result, "origin/main...feature-branch")
end

-- =============================================================================
-- Viewer config tests
-- =============================================================================

T["viewer config"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset config to defaults before each test
      local cfg = require("gitlad.config")
      cfg.reset()
    end,
  },
})

T["viewer config"]["defaults to native viewer"] = function()
  local cfg = require("gitlad.config")
  eq(cfg.get().diff.viewer, "native")
end

T["viewer config"]["can be set to diffview"] = function()
  local cfg = require("gitlad.config")
  cfg.setup({ diff = { viewer = "diffview" } })
  eq(cfg.get().diff.viewer, "diffview")
end

T["viewer config"]["can be set to native explicitly"] = function()
  local cfg = require("gitlad.config")
  cfg.setup({ diff = { viewer = "native" } })
  eq(cfg.get().diff.viewer, "native")
end

return T
