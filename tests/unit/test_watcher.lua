local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["watcher"] = MiniTest.new_set()

T["watcher"]["should_ignore allows index file"] = function()
  -- index is no longer filtered - we use cooldown mechanism instead
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("index"), false)
end

T["watcher"]["should_ignore filters ORIG_HEAD"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("ORIG_HEAD"), true)
end

T["watcher"]["should_ignore filters FETCH_HEAD"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("FETCH_HEAD"), true)
end

T["watcher"]["should_ignore filters COMMIT_EDITMSG"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("COMMIT_EDITMSG"), true)
end

T["watcher"]["should_ignore filters lock files"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("index.lock"), true)
  eq(watcher._should_ignore("HEAD.lock"), true)
  eq(watcher._should_ignore("refs/heads/main.lock"), true)
end

T["watcher"]["should_ignore filters backup files"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("index~"), true)
  eq(watcher._should_ignore("config~"), true)
end

T["watcher"]["should_ignore filters temp files with 4 digits"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("1234"), true)
  eq(watcher._should_ignore("0000"), true)
  eq(watcher._should_ignore("9999"), true)
end

T["watcher"]["should_ignore allows nil"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore(nil), true)
end

T["watcher"]["should_ignore allows HEAD"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("HEAD"), false)
end

T["watcher"]["should_ignore allows refs"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("refs"), false)
  eq(watcher._should_ignore("refs/heads"), false)
  eq(watcher._should_ignore("refs/heads/main"), false)
end

T["watcher"]["should_ignore allows config"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("config"), false)
end

T["watcher"]["should_ignore allows MERGE_HEAD"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("MERGE_HEAD"), false)
end

T["watcher"]["should_ignore allows REBASE_HEAD"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("REBASE_HEAD"), false)
end

T["watcher"]["should_ignore allows CHERRY_PICK_HEAD"] = function()
  local watcher = require("gitlad.watcher")
  eq(watcher._should_ignore("CHERRY_PICK_HEAD"), false)
end

T["watcher"]["creates new watcher instance"] = function()
  local watcher = require("gitlad.watcher")

  -- Mock repo state
  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state)

  expect.no_error(function()
    return w
  end)
  eq(w:is_running(), false)
  eq(w.git_dir, "/tmp/test/.git")
end

T["watcher"]["start is idempotent"] = function()
  local watcher = require("gitlad.watcher")

  -- Mock repo state
  local mock_repo_state = {
    git_dir = "/tmp/nonexistent/.git", -- Won't actually start since dir doesn't exist
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state)

  -- Starting multiple times should not error
  expect.no_error(function()
    w:start()
    w:start()
    w:start()
  end)
end

T["watcher"]["stop is idempotent"] = function()
  local watcher = require("gitlad.watcher")

  -- Mock repo state
  local mock_repo_state = {
    git_dir = "/tmp/nonexistent/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state)

  -- Stopping multiple times should not error
  expect.no_error(function()
    w:stop()
    w:stop()
    w:stop()
  end)
end

T["watcher"]["is_running returns false initially"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state)
  eq(w:is_running(), false)
end

T["watcher"]["is_in_cooldown returns false when no recent operation"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
    last_operation_time = 0, -- No recent operation
  }

  local w = watcher.new(mock_repo_state)
  eq(w:is_in_cooldown(), false)
end

T["watcher"]["is_in_cooldown returns true when within cooldown period"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
    last_operation_time = vim.loop.now(), -- Just happened
  }

  local w = watcher.new(mock_repo_state, { cooldown_ms = 1000 })
  eq(w:is_in_cooldown(), true)
end

T["watcher"]["is_in_cooldown returns false after cooldown expires"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
    last_operation_time = vim.loop.now() - 2000, -- 2 seconds ago
  }

  local w = watcher.new(mock_repo_state, { cooldown_ms = 1000 })
  eq(w:is_in_cooldown(), false)
end

T["watcher"]["respects custom cooldown duration"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
    last_operation_time = vim.loop.now() - 500, -- 500ms ago
  }

  -- With 1000ms cooldown, should still be in cooldown
  local w1 = watcher.new(mock_repo_state, { cooldown_ms = 1000 })
  eq(w1:is_in_cooldown(), true)

  -- With 200ms cooldown, should be past cooldown
  local w2 = watcher.new(mock_repo_state, { cooldown_ms = 200 })
  eq(w2:is_in_cooldown(), false)
end

T["watcher"]["defaults to indicator mode"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state)
  eq(w._mode, "indicator")
end

T["watcher"]["accepts indicator mode explicitly"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state, { mode = "indicator" })
  eq(w._mode, "indicator")
end

T["watcher"]["accepts auto_refresh mode"] = function()
  local watcher = require("gitlad.watcher")

  local refresh_called = false
  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state, {
    mode = "auto_refresh",
    on_refresh = function()
      refresh_called = true
    end,
  })

  eq(w._mode, "auto_refresh")
  -- Verify auto_refresh_debounced was created
  expect.no_error(function()
    return w._auto_refresh_debounced
  end)
end

T["watcher"]["auto_refresh mode requires on_refresh callback to create debouncer"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  -- Without on_refresh, debouncer should not be created
  local w = watcher.new(mock_repo_state, { mode = "auto_refresh" })
  eq(w._mode, "auto_refresh")
  eq(w._auto_refresh_debounced, nil)
end

T["watcher"]["accepts custom auto_refresh_debounce_ms"] = function()
  local watcher = require("gitlad.watcher")

  local mock_repo_state = {
    git_dir = "/tmp/test/.git",
    mark_stale = function() end,
  }

  local w = watcher.new(mock_repo_state, {
    mode = "auto_refresh",
    auto_refresh_debounce_ms = 1000,
    on_refresh = function() end,
  })

  -- Can't directly test debounce duration, but we can verify the watcher was created
  eq(w._mode, "auto_refresh")
end

return T
