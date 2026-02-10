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
-- Demo sequence
-- ============================================================================

-- Open gitlad status
keys(1200, ":Gitlad<CR>")
step(2000, function() end)

-- Show help first - give an overview of what's available
keys(1000, "?")
step(3000, function() end)
keys(800, "q")
step(600, function() end)

-- Navigate to an unstaged file with a nice diff (Button.js)
-- Layout: 4 untracked files, then unstaged: README.md, lib (submodule), Button.js
keys(300, "gj")
keys(150, "gj")
keys(150, "gj")
keys(150, "gj")
keys(150, "gj")
keys(150, "gj")

-- Expand inline diff - Button.js has a great mix of added/removed lines
keys(800, "<Tab>")
step(1800, function() end)

-- Scroll through the diff to see the changes
keys(250, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")
step(800, function() end)

-- Collapse diff
keys(800, "<Tab>")
step(400, function() end)

-- Stage the file
keys(600, "s")
step(600, function() end)

-- Next file - expand for hunk staging
keys(300, "gj")
keys(600, "<Tab>")
step(1000, function() end)

-- Move into the diff hunk
keys(150, "j")
keys(150, "j")
keys(150, "j")
keys(150, "j")

-- Stage just this hunk
keys(600, "s")
step(600, function() end)

-- Collapse
keys(500, "<Tab>")
step(300, function() end)

-- Show commit popup
keys(1000, "c")
step(2000, function() end)
keys(800, "q")

-- Show branch popup - test repo has feature/clean-merge and feature/conflict-merge
keys(1000, "b")
step(1500, function() end)
keys(800, "q")

-- Show refs popup and open refs view for current branch
keys(1000, "yr")
step(1200, function() end)
keys(600, "r")
step(2500, function() end)

-- Close refs view
keys(800, "q")

-- Log popup and open log view
keys(1000, "l")
step(1200, function() end)
keys(600, "l")
step(1800, function() end)

-- Expand commit details (cursor starts on first commit)
keys(800, "<Tab>")
step(1500, function() end)

-- Collapse and show limit controls: double with +
keys(600, "<Tab>")
keys(800, "+")
step(1200, function() end)

-- Halve with -
keys(800, "-")
step(1200, function() end)

-- Close log view
keys(1000, "q")

-- Show git command history
keys(1000, "$")
step(2500, function() end)

-- Close history
keys(800, "q")

-- Final pause on status view
step(1500, function() end)

-- ============================================================================
-- Start the demo
-- ============================================================================
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(run_next, 500)
  end,
})
