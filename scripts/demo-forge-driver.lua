-- Demo driver: Forge/GitHub (~45-60s)
-- Covers: forge popup, PR list dashboard, PR detail view (comments, checks),
-- PR diff in native viewer with inline review threads, thread navigation.
--
-- Uses a real GitHub repo (set up by create-forge-test-repo.sh).
--
-- Usage: GITLAD_DEMO_DRIVER=demo-forge-driver.lua nvim -u scripts/demo-init.lua

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
end

local queue = {}
local idx = 1

local function step(delay_ms, fn)
  table.insert(queue, { delay = delay_ms, fn = fn })
end

local function keys(delay_ms, k)
  step(delay_ms, function()
    type_keys(k)
  end)
end

local function run_next()
  if idx > #queue then
    vim.defer_fn(function()
      vim.cmd("qa!")
    end, 2000)
    return
  end
  local s = queue[idx]
  idx = idx + 1
  vim.defer_fn(function()
    s.fn()
    vim.schedule(run_next)
  end, s.delay)
end

-- ============================================================================
-- Demo sequence (~45-60s)
-- ============================================================================

-- Phase 1: Open status view
keys(1200, ":Gitlad<CR>")
step(2500, function() end)

-- Phase 2: Forge popup — show provider detection
keys(800, "N")
step(2000, function() end)

-- Phase 3: List PRs — triggers API call
keys(500, "l")
-- Wait generously for API response
step(4000, function() end)

-- Pause to show the PR list dashboard
step(2000, function() end)

-- Phase 4: Navigate to the PR and open detail view
keys(400, "gj")
step(600, function() end)
keys(500, "<CR>")
-- Wait for PR detail to load
step(4000, function() end)

-- Phase 5: Browse the PR detail
-- Scroll through comments
keys(250, "gj")
step(500, function() end)
keys(250, "gj")
step(500, function() end)
keys(250, "gj")
step(500, function() end)
keys(250, "gj")
step(500, function() end)

-- Toggle the checks section
keys(500, "<Tab>")
step(1500, function() end)
keys(500, "<Tab>")
step(800, function() end)

-- Continue scrolling
keys(250, "gj")
step(500, function() end)
keys(250, "gj")
step(500, function() end)

-- Phase 6: Open PR diff in native viewer
keys(600, "d")
step(3500, function() end)

-- Navigate files
keys(500, "gj")
step(1000, function() end)
keys(500, "gj")
step(1000, function() end)

-- Navigate review threads
keys(500, "]t")
step(1200, function() end)

-- Expand/collapse thread
keys(500, "<Tab>")
step(1500, function() end)

-- Next thread
keys(500, "]t")
step(1200, function() end)
keys(500, "<Tab>")
step(1500, function() end)

-- Previous thread
keys(500, "[t")
step(1000, function() end)

-- Close the diff viewer
keys(600, "q")
step(800, function() end)

-- Close PR detail
keys(600, "q")
step(800, function() end)

-- Close PR list
keys(600, "q")
step(800, function() end)

-- Final pause on status
step(1500, function() end)

-- ============================================================================
-- Start the demo
-- ============================================================================
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(run_next, 500)
  end,
})
