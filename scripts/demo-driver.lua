-- Demo driver for asciinema recording
-- Sends keystrokes with delays to showcase gitlad features
--
-- Usage: nvim -u scripts/demo-init.lua

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
-- Demo sequence (~60s)
-- ============================================================================

-- Phase 1: Status overview — shows Head + Merge with remote tracking
keys(1200, ":Gitlad<CR>")
step(2500, function() end)

-- Phase 2: Help popup — overview of all keybindings
keys(800, "?")
step(2500, function() end)
keys(600, "q")
step(500, function() end)

-- Phase 3: Staging workflow
-- Navigate to Button.js (6×gj past untracked + unstaged files)
keys(300, "gj")
keys(150, "gj")
keys(150, "gj")
keys(150, "gj")
keys(150, "gj")
keys(150, "gj")

-- Expand inline diff — Button.js has a nice mix of added/removed lines
keys(600, "<Tab>")
step(1500, function() end)

-- Scroll through the diff
keys(200, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
step(600, function() end)

-- Collapse diff
keys(600, "<Tab>")
step(300, function() end)

-- Stage the whole file
keys(500, "s")
step(500, function() end)

-- Next file — expand for hunk staging demo
keys(300, "gj")
keys(500, "<Tab>")
step(800, function() end)

-- Move into the diff hunk
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")

-- Stage just this hunk
keys(500, "s")
step(500, function() end)

-- Collapse
keys(400, "<Tab>")
step(300, function() end)

-- Phase 4: Commit popup
keys(800, "c")
step(2000, function() end)
keys(600, "q")
step(300, function() end)

-- Phase 5: Diffview integration — show staged diff side-by-side
keys(800, "d")
step(1500, function() end)
keys(600, "s")
step(3000, function() end)
keys(300, ":DiffviewClose<CR>")
step(800, function() end)

-- Phase 6: Branch popup
keys(800, "b")
step(1500, function() end)
keys(600, "q")
step(300, function() end)

-- Phase 7: Refs popup → refs view
keys(800, "yr")
step(1000, function() end)
keys(500, "r")
step(2000, function() end)
keys(600, "q")
step(300, function() end)

-- Phase 8: Worktrees — navigate to section via M-n (section jump)
-- Sections: Untracked → Unstaged → Staged → Worktrees (4th with M-n)
keys(300, "gg")
keys(300, "<M-n>")
keys(200, "<M-n>")
keys(200, "<M-n>")
keys(200, "<M-n>")
step(800, function() end)

-- Browse worktree entries
keys(250, "gj")
keys(200, "gj")
step(800, function() end)

-- Worktree popup
keys(600, "Z")
step(2000, function() end)
keys(600, "q")
step(300, function() end)

-- Phase 9: Log + Rebase popup
keys(800, "l")
step(1000, function() end)
keys(500, "l")
step(1500, function() end)

-- Expand first commit details
keys(600, "<Tab>")
step(1200, function() end)

-- Collapse
keys(500, "<Tab>")

-- Limit controls: double with +, halve with -
keys(600, "+")
step(800, function() end)
keys(600, "-")
step(800, function() end)

-- Navigate down a few commits
keys(250, "gj")
keys(200, "gj")
keys(200, "gj")
step(600, function() end)

-- Rebase popup — show all the options
keys(600, "r")
step(2500, function() end)
keys(600, "q")
step(300, function() end)

-- Close log view
keys(600, "q")
step(300, function() end)

-- Phase 10: Git command history
keys(800, "$")
step(2000, function() end)
keys(600, "q")

-- Phase 11: Final pause on status
step(1500, function() end)

-- ============================================================================
-- Start the demo
-- ============================================================================
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(run_next, 500)
  end,
})
