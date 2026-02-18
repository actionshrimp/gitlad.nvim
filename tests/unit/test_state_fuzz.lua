-- Fuzz/property-based tests for state update race conditions
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Seeded RNG for reproducibility
local function make_rng(seed)
  -- Simple linear congruential generator
  local state = seed or 42
  local rng = {}
  function rng:next()
    state = (state * 1103515245 + 12345) % (2 ^ 31)
    return state
  end
  function rng:next_int(min, max)
    return min + (self:next() % (max - min + 1))
  end
  function rng:pick(list)
    if #list == 0 then
      return nil
    end
    return list[self:next_int(1, #list)]
  end
  return rng
end

-- Valid status codes for files in different sections
local INDEX_STATUSES = { "M", "A", "D", "R", "C", "T" }
local WORKTREE_STATUSES = { "M", "D", "T" }

--- Generate a random GitStatusResult with files distributed across sections
---@param seed number RNG seed for reproducibility
---@param n_files number Total number of files to generate
---@return GitStatusResult
local function make_random_status(seed, n_files)
  local rng = make_rng(seed)
  n_files = n_files or rng:next_int(5, 20)

  local status = {
    branch = "main",
    oid = string.format("%040x", seed),
    upstream = nil,
    ahead = 0,
    behind = 0,
    staged = {},
    unstaged = {},
    untracked = {},
    conflicted = {},
  }

  -- Generate unique file paths and distribute across sections
  local paths = {}
  for i = 1, n_files do
    local dir = rng:next_int(1, 3) == 1 and string.format("dir%d/", rng:next_int(1, 3)) or ""
    local name = string.format("%sfile_%03d.txt", dir, i)
    table.insert(paths, name)
  end
  table.sort(paths)

  for _, path in ipairs(paths) do
    local section = rng:next_int(1, 4)
    if section == 1 then
      -- Staged
      local idx_status = rng:pick(INDEX_STATUSES)
      table.insert(status.staged, {
        path = path,
        index_status = idx_status,
        worktree_status = ".",
      })
    elseif section == 2 then
      -- Unstaged
      local wt_status = rng:pick(WORKTREE_STATUSES)
      table.insert(status.unstaged, {
        path = path,
        index_status = ".",
        worktree_status = wt_status,
      })
    elseif section == 3 then
      -- Untracked
      table.insert(status.untracked, {
        path = path,
        index_status = "?",
        worktree_status = "?",
      })
    else
      -- Conflicted
      table.insert(status.conflicted, {
        path = path,
        index_status = "U",
        worktree_status = "U",
      })
    end
  end

  return status
end

--- Generate a random valid command for the current state
---@param status GitStatusResult
---@param rng table RNG instance
---@return StatusCommand|nil
local function generate_random_command(status, rng)
  local commands = require("gitlad.state.commands")

  -- Collect all possible commands
  local possible = {}

  -- stage_file from unstaged
  for _, entry in ipairs(status.unstaged) do
    -- Skip intent-to-add files (.A) for stage_file, they use stage normally
    if not (entry.index_status == "." and entry.worktree_status == "A") then
      table.insert(possible, function()
        return commands.stage_file(entry.path, "unstaged")
      end)
    end
  end

  -- stage_file from untracked
  for _, entry in ipairs(status.untracked) do
    -- Skip directory entries for staging (they trigger refresh, not optimistic update)
    if not entry.path:match("/$") then
      table.insert(possible, function()
        return commands.stage_file(entry.path, "untracked")
      end)
    end
  end

  -- unstage_file from staged
  for _, entry in ipairs(status.staged) do
    table.insert(possible, function()
      return commands.unstage_file(entry.path)
    end)
  end

  -- stage_intent from untracked (only non-directory files)
  for _, entry in ipairs(status.untracked) do
    if not entry.path:match("/$") then
      table.insert(possible, function()
        return commands.stage_intent(entry.path)
      end)
    end
  end

  -- unstage_intent from unstaged (.A files)
  for _, entry in ipairs(status.unstaged) do
    if entry.index_status == "." and entry.worktree_status == "A" then
      table.insert(possible, function()
        return commands.unstage_intent(entry.path)
      end)
    end
  end

  -- stage_all (if there are unstaged or untracked files)
  if #status.unstaged > 0 or #status.untracked > 0 then
    table.insert(possible, function()
      return commands.stage_all()
    end)
  end

  -- unstage_all (if there are staged files)
  if #status.staged > 0 then
    table.insert(possible, function()
      return commands.unstage_all()
    end)
  end

  -- remove_file from unstaged
  for _, entry in ipairs(status.unstaged) do
    table.insert(possible, function()
      return commands.remove_file(entry.path, "unstaged")
    end)
  end

  -- remove_file from untracked
  for _, entry in ipairs(status.untracked) do
    table.insert(possible, function()
      return commands.remove_file(entry.path, "untracked")
    end)
  end

  if #possible == 0 then
    return nil
  end

  local factory = rng:pick(possible)
  return factory()
end

--- Check structural invariants on a status result
---@param status GitStatusResult
---@param label string Context label for error messages
local function check_invariants(status, label)
  -- 1. No file path appears in more than one section
  local seen = {}
  local sections = {
    { name = "staged", entries = status.staged },
    { name = "unstaged", entries = status.unstaged },
    { name = "untracked", entries = status.untracked },
    { name = "conflicted", entries = status.conflicted },
  }

  for _, section in ipairs(sections) do
    for _, entry in ipairs(section.entries) do
      if seen[entry.path] then
        error(
          string.format(
            "%s: file '%s' appears in both '%s' and '%s'",
            label,
            entry.path,
            seen[entry.path],
            section.name
          )
        )
      end
      seen[entry.path] = section.name
    end
  end

  -- 2. Each section is sorted alphabetically by path
  for _, section in ipairs(sections) do
    for i = 2, #section.entries do
      if section.entries[i].path < section.entries[i - 1].path then
        error(
          string.format(
            "%s: section '%s' not sorted: '%s' < '%s' at index %d",
            label,
            section.name,
            section.entries[i].path,
            section.entries[i - 1].path,
            i
          )
        )
      end
    end
  end

  -- 3. No nil entries
  for _, section in ipairs(sections) do
    for i, entry in ipairs(section.entries) do
      if entry == nil then
        error(string.format("%s: nil entry in '%s' at index %d", label, section.name, i))
      end
      if entry.path == nil then
        error(string.format("%s: nil path in '%s' at index %d", label, section.name, i))
      end
    end
  end

  -- 4. Valid status codes per section
  for _, entry in ipairs(status.staged) do
    if entry.index_status == "." or entry.index_status == "?" then
      error(
        string.format(
          "%s: staged entry '%s' has invalid index_status '%s'",
          label,
          entry.path,
          entry.index_status
        )
      )
    end
  end

  for _, entry in ipairs(status.unstaged) do
    if entry.index_status ~= "." then
      error(
        string.format(
          "%s: unstaged entry '%s' has invalid index_status '%s' (expected '.')",
          label,
          entry.path,
          entry.index_status
        )
      )
    end
  end

  for _, entry in ipairs(status.untracked) do
    if entry.index_status ~= "?" or entry.worktree_status ~= "?" then
      error(
        string.format(
          "%s: untracked entry '%s' has invalid statuses '%s'/'%s' (expected '?'/'?')",
          label,
          entry.path,
          entry.index_status,
          entry.worktree_status
        )
      )
    end
  end
end

--- Count total files across all sections
---@param status GitStatusResult
---@return number
local function count_total_files(status)
  return #status.staged + #status.unstaged + #status.untracked + #status.conflicted
end

-- ============================================================================
-- Layer 1: Reducer Property Tests
-- ============================================================================

T["reducer properties"] = MiniTest.new_set()

T["reducer properties"]["invariants hold after random command sequences"] = function()
  local reducer = require("gitlad.state.reducer")

  -- Test with multiple seeds
  for seed = 1, 50 do
    local rng = make_rng(seed)
    local status = make_random_status(seed, rng:next_int(5, 15))

    check_invariants(status, string.format("seed=%d initial", seed))

    -- Apply random sequence of commands
    local n_commands = rng:next_int(10, 30)
    for step = 1, n_commands do
      local cmd = generate_random_command(status, rng)
      if cmd then
        status = reducer.apply(status, cmd)
        check_invariants(status, string.format("seed=%d step=%d cmd=%s", seed, step, cmd.type))
      end
    end
  end
end

T["reducer properties"]["immutability: original status unchanged after apply"] = function()
  local reducer = require("gitlad.state.reducer")

  for seed = 1, 20 do
    local rng = make_rng(seed)
    local status = make_random_status(seed, rng:next_int(5, 10))

    local n_commands = rng:next_int(5, 15)
    for _ = 1, n_commands do
      local cmd = generate_random_command(status, rng)
      if cmd then
        -- Snapshot the input before apply
        local before = vim.deepcopy(status)
        local new_status = reducer.apply(status, cmd)
        -- Input must not have been mutated
        eq(status.staged, before.staged)
        eq(status.unstaged, before.unstaged)
        eq(status.untracked, before.untracked)
        eq(status.conflicted, before.conflicted)
        -- Use new status for next command generation
        status = new_status
      end
    end
  end
end

T["reducer properties"]["stage_all then unstage_all round-trips file count"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  for seed = 1, 30 do
    local status = make_random_status(seed, 10)
    local initial_total = count_total_files(status)

    -- Stage all
    local staged = reducer.apply(status, commands.stage_all())
    check_invariants(staged, string.format("seed=%d after stage_all", seed))
    eq(count_total_files(staged), initial_total)
    eq(#staged.unstaged, 0)
    eq(#staged.untracked, 0)

    -- Unstage all
    local unstaged = reducer.apply(staged, commands.unstage_all())
    check_invariants(unstaged, string.format("seed=%d after unstage_all", seed))
    eq(count_total_files(unstaged), initial_total)
    eq(#unstaged.staged, 0)
  end
end

T["reducer properties"]["individual stage/unstage is a no-op on wrong section"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  -- Staging a file that's not in the source section should be a no-op
  for seed = 1, 20 do
    local status = make_random_status(seed, 8)

    -- Try to stage a file that only exists in staged (wrong source)
    if #status.staged > 0 then
      local path = status.staged[1].path
      local before = vim.deepcopy(status)
      local after = reducer.apply(status, commands.stage_file(path, "unstaged"))
      -- File wasn't in unstaged, so nothing should change in staged/unstaged
      -- (The file remains in staged)
      eq(#after.staged, #before.staged)
    end

    -- Try to unstage a file that's not staged
    if #status.unstaged > 0 then
      local path = status.unstaged[1].path
      local before_staged = #status.staged
      local after = reducer.apply(status, commands.unstage_file(path))
      -- File wasn't in staged, so nothing changes
      eq(#after.staged, before_staged)
    end
  end
end

T["reducer properties"]["commands are idempotent when source entry missing"] = function()
  local reducer = require("gitlad.state.reducer")
  local commands = require("gitlad.state.commands")

  -- Applying a command twice should be safe - second apply is a no-op
  for seed = 1, 20 do
    local status = make_random_status(seed, 8)

    if #status.untracked > 0 then
      local path = status.untracked[1].path
      if not path:match("/$") then
        local cmd = commands.stage_file(path, "untracked")
        local once = reducer.apply(status, cmd)
        local twice = reducer.apply(once, cmd)
        check_invariants(twice, string.format("seed=%d double stage", seed))
        -- Second apply is a no-op since file is no longer in untracked
        eq(#twice.staged, #once.staged)
        eq(#twice.untracked, #once.untracked)
      end
    end
  end
end

-- ============================================================================
-- Layer 2: Coordinator Race Simulation
-- ============================================================================

T["race simulation"] = MiniTest.new_set()

--- Simulator models RepoState's async behavior for testing race conditions
---@class Simulator
---@field status GitStatusResult What the UI sees
---@field ground_truth GitStatusResult What git would actually report
---@field handler AsyncHandler Real AsyncHandler
---@field pending_refreshes table[] Queue of {done: fun, snapshot: GitStatusResult}
---@field pending_optimistic_cmds StatusCommand[] Commands applied since last refresh dispatch
---@field use_fix boolean Whether to use the replay fix
local Simulator = {}
Simulator.__index = Simulator

--- Create a new Simulator
---@param initial_status GitStatusResult
---@param use_fix boolean Whether to use the replay fix
---@return Simulator
function Simulator.new(initial_status, use_fix)
  local async = require("gitlad.state.async")
  local self = setmetatable({}, Simulator)
  self.status = vim.deepcopy(initial_status)
  self.ground_truth = vim.deepcopy(initial_status)
  self.pending_refreshes = {}
  self.pending_optimistic_cmds = {}
  self.use_fix = use_fix

  self.handler = async.new(function(result)
    if self.use_fix then
      -- Replay optimistic commands on top of fresh result
      local reducer = require("gitlad.state.reducer")
      local cmds = self.pending_optimistic_cmds
      self.pending_optimistic_cmds = {}
      for _, cmd in ipairs(cmds) do
        result = reducer.apply(result, cmd)
      end
    end
    self.status = result
  end)

  return self
end

--- Apply an optimistic command (models stage/unstage after git command succeeds)
---@param cmd StatusCommand
function Simulator:apply_command(cmd)
  local reducer = require("gitlad.state.reducer")
  -- Update both UI state and ground truth
  self.status = reducer.apply(self.status, cmd)
  self.ground_truth = reducer.apply(self.ground_truth, cmd)
  -- Track for replay
  if self.use_fix then
    table.insert(self.pending_optimistic_cmds, cmd)
  end
end

--- Start a refresh: snapshot ground_truth and dispatch through AsyncHandler
function Simulator:start_refresh()
  local snapshot = vim.deepcopy(self.ground_truth)

  if self.use_fix then
    self.pending_optimistic_cmds = {}
  end

  self.handler:dispatch(function(done)
    -- Store the callback and snapshot for later completion
    table.insert(self.pending_refreshes, { done = done, snapshot = snapshot })
  end)
end

--- Complete the oldest pending refresh
---@return boolean Whether a refresh was completed
function Simulator:complete_oldest_refresh()
  if #self.pending_refreshes == 0 then
    return false
  end
  local refresh = table.remove(self.pending_refreshes, 1)
  refresh.done(refresh.snapshot)
  return true
end

--- Complete the newest (most recent) pending refresh
---@return boolean Whether a refresh was completed
function Simulator:complete_newest_refresh()
  if #self.pending_refreshes == 0 then
    return false
  end
  local refresh = table.remove(self.pending_refreshes, #self.pending_refreshes)
  refresh.done(refresh.snapshot)
  return true
end

--- Check if there are pending refreshes
---@return boolean
function Simulator:has_pending_refreshes()
  return #self.pending_refreshes > 0
end

--- Settle: complete all pending refreshes (newest first, as AsyncHandler drops stale)
function Simulator:settle()
  while #self.pending_refreshes > 0 do
    self:complete_newest_refresh()
  end
end

--- Assert status matches ground truth (only valid after settling)
---@param label string Context for error messages
function Simulator:assert_converged(label)
  local function entries_to_paths(entries)
    local paths = {}
    for _, e in ipairs(entries) do
      table.insert(paths, e.path)
    end
    table.sort(paths)
    return paths
  end

  local function assert_section(section_name)
    local status_paths = entries_to_paths(self.status[section_name] or {})
    local truth_paths = entries_to_paths(self.ground_truth[section_name] or {})
    if not vim.deep_equal(status_paths, truth_paths) then
      error(
        string.format(
          "%s: %s mismatch\n  status: %s\n  truth:  %s",
          label,
          section_name,
          vim.inspect(status_paths),
          vim.inspect(truth_paths)
        )
      )
    end
  end

  assert_section("staged")
  assert_section("unstaged")
  assert_section("untracked")
end

-- Helper to create a simple status for named race tests
local function make_simple_status()
  return {
    branch = "main",
    oid = "abc123",
    upstream = nil,
    ahead = 0,
    behind = 0,
    staged = {},
    unstaged = {
      { path = "a.txt", index_status = ".", worktree_status = "M" },
      { path = "b.txt", index_status = ".", worktree_status = "M" },
      { path = "c.txt", index_status = ".", worktree_status = "M" },
    },
    untracked = {
      { path = "new1.txt", index_status = "?", worktree_status = "?" },
      { path = "new2.txt", index_status = "?", worktree_status = "?" },
    },
    conflicted = {},
  }
end

-- Named race condition tests (these demonstrate the bug and verify the fix)

T["race simulation"]["refresh overwrites optimistic update"] = function()
  local commands = require("gitlad.state.commands")

  -- WITHOUT fix: refresh should overwrite the staged file
  local sim_broken = Simulator.new(make_simple_status(), false)
  sim_broken:start_refresh() -- dispatch refresh (snapshots current state)
  sim_broken:apply_command(commands.stage_file("a.txt", "unstaged")) -- user stages a.txt
  sim_broken:complete_oldest_refresh() -- refresh completes with pre-stage snapshot

  -- Bug: a.txt should be staged but refresh overwrote it
  local found_staged = false
  for _, e in ipairs(sim_broken.status.staged) do
    if e.path == "a.txt" then
      found_staged = true
    end
  end
  eq(found_staged, false) -- BUG: staged file was lost

  -- WITH fix: staged file should survive
  local sim_fixed = Simulator.new(make_simple_status(), true)
  sim_fixed:start_refresh()
  sim_fixed:apply_command(commands.stage_file("a.txt", "unstaged"))
  sim_fixed:complete_oldest_refresh()

  local found_staged_fixed = false
  for _, e in ipairs(sim_fixed.status.staged) do
    if e.path == "a.txt" then
      found_staged_fixed = true
    end
  end
  eq(found_staged_fixed, true) -- FIX: staged file preserved via replay
end

T["race simulation"]["multiple optimistic updates during slow refresh"] = function()
  local commands = require("gitlad.state.commands")

  -- WITHOUT fix
  local sim_broken = Simulator.new(make_simple_status(), false)
  sim_broken:start_refresh()
  sim_broken:apply_command(commands.stage_file("a.txt", "unstaged"))
  sim_broken:apply_command(commands.stage_file("b.txt", "unstaged"))
  sim_broken:complete_oldest_refresh()

  -- Bug: both staged files were lost
  eq(#sim_broken.status.staged, 0)

  -- WITH fix
  local sim_fixed = Simulator.new(make_simple_status(), true)
  sim_fixed:start_refresh()
  sim_fixed:apply_command(commands.stage_file("a.txt", "unstaged"))
  sim_fixed:apply_command(commands.stage_file("b.txt", "unstaged"))
  sim_fixed:complete_oldest_refresh()

  eq(#sim_fixed.status.staged, 2)
  eq(sim_fixed.status.staged[1].path, "a.txt")
  eq(sim_fixed.status.staged[2].path, "b.txt")
end

T["race simulation"]["optimistic update between refresh dispatch and extended fetch"] = function()
  local commands = require("gitlad.state.commands")

  -- Models: refresh dispatched → git status returns → user stages → extended fetch completes
  -- Same pattern as above but emphasizes the _fetch_extended_status delay
  local sim_fixed = Simulator.new(make_simple_status(), true)
  sim_fixed:start_refresh()
  sim_fixed:apply_command(commands.stage_file("c.txt", "unstaged"))
  sim_fixed:complete_oldest_refresh()

  local found = false
  for _, e in ipairs(sim_fixed.status.staged) do
    if e.path == "c.txt" then
      found = true
    end
  end
  eq(found, true)
  check_invariants(sim_fixed.status, "after extended fetch race")
end

T["race simulation"]["rapid stage/unstage with interleaved refresh"] = function()
  local commands = require("gitlad.state.commands")

  -- WITH fix: rapid stage → unstage → stage cycle during refresh
  local sim = Simulator.new(make_simple_status(), true)
  sim:start_refresh()
  sim:apply_command(commands.stage_file("a.txt", "unstaged")) -- stage
  sim:apply_command(commands.unstage_file("a.txt")) -- unstage
  sim:apply_command(commands.stage_file("a.txt", "unstaged")) -- stage again
  sim:complete_oldest_refresh()

  -- a.txt should be staged (final state of the sequence)
  local found = false
  for _, e in ipairs(sim.status.staged) do
    if e.path == "a.txt" then
      found = true
    end
  end
  eq(found, true)
  check_invariants(sim.status, "after rapid stage/unstage")
end

T["race simulation"]["auto-refresh races with user staging"] = function()
  local commands = require("gitlad.state.commands")

  -- Models: watcher triggers auto-refresh, user stages during it
  local sim = Simulator.new(make_simple_status(), true)

  -- Auto-refresh triggered by watcher
  sim:start_refresh()

  -- User stages two files while refresh is in-flight
  sim:apply_command(commands.stage_file("a.txt", "unstaged"))
  sim:apply_command(commands.stage_file("new1.txt", "untracked"))

  -- Auto-refresh completes with stale snapshot
  sim:complete_oldest_refresh()

  -- Both user actions should be preserved
  local staged_paths = {}
  for _, e in ipairs(sim.status.staged) do
    staged_paths[e.path] = true
  end
  eq(staged_paths["a.txt"], true)
  eq(staged_paths["new1.txt"], true)
  check_invariants(sim.status, "after auto-refresh race")
end

T["race simulation"]["stage_all during refresh preserves all files"] = function()
  local commands = require("gitlad.state.commands")

  local sim = Simulator.new(make_simple_status(), true)
  sim:start_refresh()
  sim:apply_command(commands.stage_all())
  sim:complete_oldest_refresh()

  -- All files should be staged
  eq(#sim.status.unstaged, 0)
  eq(#sim.status.untracked, 0)
  eq(#sim.status.staged, 5) -- 3 unstaged + 2 untracked
  check_invariants(sim.status, "after stage_all during refresh")
end

T["race simulation"]["unstage_all during refresh preserves unstaged state"] = function()
  local commands = require("gitlad.state.commands")
  local reducer = require("gitlad.state.reducer")

  -- Start with some staged files
  local initial = make_simple_status()
  initial = reducer.apply(initial, commands.stage_all())

  local sim = Simulator.new(initial, true)
  sim:start_refresh()
  sim:apply_command(commands.unstage_all())
  sim:complete_oldest_refresh()

  eq(#sim.status.staged, 0)
  check_invariants(sim.status, "after unstage_all during refresh")
end

T["race simulation"]["remove_file during refresh"] = function()
  local commands = require("gitlad.state.commands")

  local sim = Simulator.new(make_simple_status(), true)
  sim:start_refresh()
  sim:apply_command(commands.remove_file("new1.txt", "untracked"))
  sim:complete_oldest_refresh()

  -- File should stay removed
  local found = false
  for _, e in ipairs(sim.status.untracked) do
    if e.path == "new1.txt" then
      found = true
    end
  end
  eq(found, false)
  check_invariants(sim.status, "after remove during refresh")
end

T["race simulation"]["stage_intent during refresh"] = function()
  local commands = require("gitlad.state.commands")

  local sim = Simulator.new(make_simple_status(), true)
  sim:start_refresh()
  sim:apply_command(commands.stage_intent("new1.txt"))
  sim:complete_oldest_refresh()

  -- new1.txt should be in unstaged as .A, not in untracked
  local found_unstaged = false
  for _, e in ipairs(sim.status.unstaged) do
    if e.path == "new1.txt" and e.worktree_status == "A" then
      found_unstaged = true
    end
  end
  eq(found_unstaged, true)

  local found_untracked = false
  for _, e in ipairs(sim.status.untracked) do
    if e.path == "new1.txt" then
      found_untracked = true
    end
  end
  eq(found_untracked, false)
  check_invariants(sim.status, "after stage_intent during refresh")
end

T["race simulation"]["unstage_intent during refresh"] = function()
  local commands = require("gitlad.state.commands")
  local reducer = require("gitlad.state.reducer")

  -- Start with a file that's had intent-to-add
  local initial = make_simple_status()
  initial = reducer.apply(initial, commands.stage_intent("new1.txt"))

  local sim = Simulator.new(initial, true)
  sim:start_refresh()
  sim:apply_command(commands.unstage_intent("new1.txt"))
  sim:complete_oldest_refresh()

  -- new1.txt should be back in untracked
  local found_untracked = false
  for _, e in ipairs(sim.status.untracked) do
    if e.path == "new1.txt" then
      found_untracked = true
    end
  end
  eq(found_untracked, true)
  check_invariants(sim.status, "after unstage_intent during refresh")
end

T["race simulation"]["multiple refreshes: only latest applied"] = function()
  local commands = require("gitlad.state.commands")

  local sim = Simulator.new(make_simple_status(), true)
  sim:start_refresh() -- refresh 1
  sim:start_refresh() -- refresh 2 (supersedes 1)
  sim:apply_command(commands.stage_file("a.txt", "unstaged"))

  -- Complete refresh 1 first (stale, should be dropped by AsyncHandler)
  sim:complete_oldest_refresh()
  -- a.txt should still be staged (refresh 1 was dropped)
  local found = false
  for _, e in ipairs(sim.status.staged) do
    if e.path == "a.txt" then
      found = true
    end
  end
  eq(found, true)

  -- Complete refresh 2 (latest, should be applied with replay)
  sim:complete_oldest_refresh()
  found = false
  for _, e in ipairs(sim.status.staged) do
    if e.path == "a.txt" then
      found = true
    end
  end
  eq(found, true)
  check_invariants(sim.status, "after multiple refreshes")
end

T["race simulation"]["random interleaved sequences converge after settling"] = function()
  for seed = 1, 50 do
    local rng = make_rng(seed)
    local initial = make_random_status(seed, rng:next_int(5, 12))
    local sim = Simulator.new(initial, true)

    local n_steps = rng:next_int(15, 40)
    for step = 1, n_steps do
      local action = rng:next_int(1, 10)

      if action <= 5 then
        -- Optimistic command (50% chance)
        local cmd = generate_random_command(sim.status, rng)
        if cmd then
          sim:apply_command(cmd)
        end
      elseif action <= 8 then
        -- Start refresh (30% chance)
        sim:start_refresh()
      elseif action == 9 then
        -- Complete oldest refresh (10% chance)
        sim:complete_oldest_refresh()
      else
        -- Complete newest refresh (10% chance)
        sim:complete_newest_refresh()
      end

      check_invariants(sim.status, string.format("seed=%d step=%d", seed, step))
    end

    -- Settle and verify convergence
    sim:settle()
    check_invariants(sim.status, string.format("seed=%d settled", seed))
    sim:assert_converged(string.format("seed=%d", seed))
  end
end

return T
