local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local pending_ops

T["pending_ops"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      pending_ops = require("gitlad.state.pending_ops")
      pending_ops.clear_all()
    end,
    post_case = function()
      pending_ops.clear_all()
    end,
  },
})

T["pending_ops"]["register() returns a done closure"] = function()
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")
  expect.equality(type(done), "function")
  done()
end

T["pending_ops"]["is_pending() returns true for registered path"] = function()
  local done = pending_ops.register("/tmp/wt", "delete", "Deleting...", "/tmp/repo")
  eq(pending_ops.is_pending("/tmp/wt"), true)
  done()
end

T["pending_ops"]["is_pending() returns false for unregistered path"] = function()
  eq(pending_ops.is_pending("/tmp/wt"), false)
end

T["pending_ops"]["is_pending() returns false after done()"] = function()
  local done = pending_ops.register("/tmp/wt", "delete", "Deleting...", "/tmp/repo")
  done()
  eq(pending_ops.is_pending("/tmp/wt"), false)
end

T["pending_ops"]["has_any() reflects pending state"] = function()
  eq(pending_ops.has_any(), false)
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")
  eq(pending_ops.has_any(), true)
  done()
  eq(pending_ops.has_any(), false)
end

T["pending_ops"]["get_all() returns all pending ops"] = function()
  local done1 = pending_ops.register("/tmp/wt1", "add", "Creating 1...", "/tmp/repo")
  local done2 = pending_ops.register("/tmp/wt2", "delete", "Deleting 2...", "/tmp/repo")

  local all = pending_ops.get_all()
  eq(all["/tmp/wt1"].type, "add")
  eq(all["/tmp/wt1"].description, "Creating 1...")
  eq(all["/tmp/wt2"].type, "delete")
  eq(all["/tmp/wt2"].description, "Deleting 2...")

  done1()
  done2()
end

T["pending_ops"]["get_spinner_char() returns a braille frame"] = function()
  local char = pending_ops.get_spinner_char()
  -- Should be one of the braille spinner frames
  expect.equality(type(char), "string")
  expect.equality(#char > 0, true)
end

T["pending_ops"]["path normalization strips trailing slash"] = function()
  local done = pending_ops.register("/tmp/wt/", "add", "Creating...", "/tmp/repo")
  eq(pending_ops.is_pending("/tmp/wt"), true)
  eq(pending_ops.is_pending("/tmp/wt/"), true)
  done()
end

T["pending_ops"]["done() is idempotent (calling twice is safe)"] = function()
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")
  done()
  done() -- second call should be a no-op
  eq(pending_ops.is_pending("/tmp/wt"), false)
end

T["pending_ops"]["on_change fires when op is registered"] = function()
  local fired = 0
  local cb = function()
    fired = fired + 1
  end
  pending_ops.on_change(cb)
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")
  eq(fired, 1)
  done()
  eq(fired, 2) -- fires again on done
end

T["pending_ops"]["off_change removes callback"] = function()
  local fired = 0
  local cb = function()
    fired = fired + 1
  end
  pending_ops.on_change(cb)
  pending_ops.off_change(cb)
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")
  eq(fired, 0)
  done()
end

T["pending_ops"]["on_tick fires on timer ticks"] = function()
  local tick_count = 0
  local cb = function()
    tick_count = tick_count + 1
  end
  pending_ops.on_tick(cb)
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")

  -- Wait for a few ticks (timer runs at 80ms)
  vim.wait(300, function()
    return tick_count >= 2
  end, 10)

  expect.equality(tick_count >= 2, true)
  done()
end

T["pending_ops"]["off_tick removes callback"] = function()
  local tick_count = 0
  local cb = function()
    tick_count = tick_count + 1
  end
  pending_ops.on_tick(cb)
  pending_ops.off_tick(cb)
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")

  vim.wait(200, function()
    return false
  end, 10)

  eq(tick_count, 0)
  done()
end

T["pending_ops"]["timer stops when last op completes"] = function()
  local tick_count = 0
  local cb = function()
    tick_count = tick_count + 1
  end
  pending_ops.on_tick(cb)
  local done = pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")

  -- Wait for timer to start ticking
  vim.wait(200, function()
    return tick_count >= 1
  end, 10)

  done()
  local count_after_done = tick_count

  -- Wait a bit more, tick count should not increase
  vim.wait(200, function()
    return false
  end, 10)

  eq(tick_count, count_after_done)
end

T["pending_ops"]["clear_all resets everything"] = function()
  pending_ops.register("/tmp/wt", "add", "Creating...", "/tmp/repo")
  local fired = false
  pending_ops.on_change(function()
    fired = true
  end)

  pending_ops.clear_all()

  eq(pending_ops.has_any(), false)
  eq(pending_ops.is_pending("/tmp/wt"), false)

  -- Callbacks should have been cleared too
  fired = false
  pending_ops.register("/tmp/wt2", "add", "Creating...", "/tmp/repo")
  eq(fired, false) -- callback was cleared

  pending_ops.clear_all()
end

T["pending_ops"]["multiple ops keep timer alive until all done"] = function()
  local tick_count = 0
  local cb = function()
    tick_count = tick_count + 1
  end
  pending_ops.on_tick(cb)

  local done1 = pending_ops.register("/tmp/wt1", "add", "Creating 1...", "/tmp/repo")
  local done2 = pending_ops.register("/tmp/wt2", "delete", "Deleting 2...", "/tmp/repo")

  done1()
  -- Timer should still be running (done2 not called yet)
  tick_count = 0
  vim.wait(200, function()
    return tick_count >= 1
  end, 10)
  expect.equality(tick_count >= 1, true)

  done2()
  -- Now timer should stop
  tick_count = 0
  vim.wait(200, function()
    return false
  end, 10)
  eq(tick_count, 0)
end

T["pending_ops"]["get_all entry has correct fields"] = function()
  local done = pending_ops.register("/tmp/wt", "add", "Creating worktree...", "/tmp/repo")
  local all = pending_ops.get_all()
  local entry = all["/tmp/wt"]

  eq(entry.type, "add")
  eq(entry.path, "/tmp/wt")
  eq(entry.description, "Creating worktree...")
  eq(entry.repo_root, "/tmp/repo")
  done()
end

return T
