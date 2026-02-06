-- Tests for gitlad.git.history module
local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Helper to create a test entry
local function make_entry(overrides)
  return vim.tbl_deep_extend("force", {
    cmd = "status",
    args = { "status", "--porcelain=v2" },
    cwd = "/test/repo",
    exit_code = 0,
    stdout = { "# branch.head main" },
    stderr = {},
    timestamp = os.time(),
    duration_ms = 50,
  }, overrides or {})
end

T["GitHistory"] = MiniTest.new_set()

T["GitHistory"]["new creates empty history"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new()

  eq(h.count, 0)
  eq(#h:get_all(), 0)
end

T["GitHistory"]["add increments count"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new()

  h:add(make_entry())
  eq(h.count, 1)

  h:add(make_entry())
  eq(h.count, 2)
end

T["GitHistory"]["get_all returns entries in reverse order"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new()

  h:add(make_entry({ cmd = "first" }))
  h:add(make_entry({ cmd = "second" }))
  h:add(make_entry({ cmd = "third" }))

  local entries = h:get_all()
  eq(#entries, 3)
  eq(entries[1].cmd, "third") -- newest first
  eq(entries[2].cmd, "second")
  eq(entries[3].cmd, "first") -- oldest last
end

T["GitHistory"]["get_latest returns most recent"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new()

  h:add(make_entry({ cmd = "first" }))
  h:add(make_entry({ cmd = "second" }))

  local latest = h:get_latest()
  eq(latest.cmd, "second")
end

T["GitHistory"]["get_latest returns nil when empty"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new()

  eq(h:get_latest(), nil)
end

T["GitHistory"]["respects max_size as ring buffer"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new(3) -- max 3 entries

  h:add(make_entry({ cmd = "one" }))
  h:add(make_entry({ cmd = "two" }))
  h:add(make_entry({ cmd = "three" }))
  h:add(make_entry({ cmd = "four" })) -- should evict "one"

  eq(h.count, 3)
  local entries = h:get_all()
  eq(#entries, 3)
  eq(entries[1].cmd, "four")
  eq(entries[2].cmd, "three")
  eq(entries[3].cmd, "two")
end

T["GitHistory"]["clear resets history"] = function()
  local history = require("gitlad.git.history")
  local h = history.GitHistory.new()

  h:add(make_entry())
  h:add(make_entry())
  h:clear()

  eq(h.count, 0)
  eq(#h:get_all(), 0)
end

T["format_entry"] = MiniTest.new_set()

T["format_entry"]["formats success entry"] = function()
  local history = require("gitlad.git.history")

  local entry = make_entry({
    cmd = "status",
    exit_code = 0,
    duration_ms = 123,
  })

  local lines = history.format_entry(entry)
  eq(#lines, 1)
  -- Should contain checkmark, time, full command with args, duration
  local line = lines[1]
  assert(line:find("✓"), "Should have success checkmark")
  assert(line:find("status"), "Should have command name")
  assert(line:find("%-%-porcelain"), "Should have command args")
  assert(line:find("123ms"), "Should have duration")
end

T["format_entry"]["formats failure entry"] = function()
  local history = require("gitlad.git.history")

  local entry = make_entry({
    cmd = "push",
    args = { "push", "origin", "main" },
    exit_code = 1,
  })

  local lines = history.format_entry(entry)
  local line = lines[1]
  assert(line:find("✗"), "Should have failure X")
end

T["format_entry_full"] = MiniTest.new_set()

T["format_entry_full"]["includes all details"] = function()
  local history = require("gitlad.git.history")

  local entry = make_entry({
    cmd = "status",
    args = { "status", "--porcelain=v2" },
    cwd = "/test/repo",
    exit_code = 0,
    stdout = { "line1", "line2" },
    stderr = { "warning" },
  })

  local lines = history.format_entry_full(entry)

  -- Should have multiple lines with details
  assert(#lines > 1, "Should have multiple lines")

  local full_text = table.concat(lines, "\n")
  assert(full_text:find("cwd:"), "Should show cwd")
  assert(full_text:find("exit:"), "Should show exit code")
  assert(full_text:find("stdout:"), "Should show stdout")
  assert(full_text:find("stderr:"), "Should show stderr")
end

T["singleton"] = MiniTest.new_set()

T["singleton"]["get returns same instance"] = function()
  local history = require("gitlad.git.history")

  -- Clear first to ensure clean state
  history.clear()

  local h1 = history.get()
  local h2 = history.get()

  eq(h1, h2)
end

T["singleton"]["module functions use singleton"] = function()
  local history = require("gitlad.git.history")

  -- Clear and add via module function
  history.clear()
  history.add(make_entry({ cmd = "test" }))

  local entries = history.get_all()
  eq(#entries, 1)
  eq(entries[1].cmd, "test")

  local latest = history.get_latest()
  eq(latest.cmd, "test")
end

return T
