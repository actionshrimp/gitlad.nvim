-- Demo driver: Advanced Diff (~50-60s)
-- Covers: native side-by-side diff viewer, file panel navigation,
-- hunk navigation, 3-way staging view, editing the index,
-- merge conflict 3-way resolution.
--
-- Usage: GITLAD_DEMO_DRIVER=demo-advanced-driver.lua nvim -u scripts/demo-init.lua

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
-- Part A: Native diff viewer (~20s)
-- ============================================================================

-- Open status view
keys(1200, ":Gitlad<CR>")
step(2000, function() end)

-- Navigate to staged section (past untracked + unstaged files)
-- Use M-n to jump by section: Untracked → Unstaged → Staged
keys(300, "<M-n>")
keys(200, "<M-n>")
keys(200, "<M-n>")
step(800, function() end)

-- Open diff popup and trigger staged diff action directly.
-- nvim_feedkeys can't reliably deliver keys to popup floating windows,
-- so we open the popup (for visual effect) then call the action via Lua.
keys(600, "d")
step(1200, function()
  -- Close the popup and open staged diff directly
  local popup_win = vim.api.nvim_get_current_win()
  local popup_config = vim.api.nvim_win_get_config(popup_win)
  if popup_config.relative and popup_config.relative ~= "" then
    vim.api.nvim_win_close(popup_win, true)
  end
  local diff_popup = require("gitlad.popups.diff")
  local state = require("gitlad.state")
  local repo_state = state.get(vim.fn.getcwd())
  diff_popup._diff_staged(repo_state)
end)
step(2500, function() end)

-- Navigate files in the panel
keys(500, "gj")
step(1000, function() end)
keys(400, "gj")
step(1000, function() end)

-- Navigate hunks
keys(400, "]c")
step(800, function() end)
keys(400, "]c")
step(800, function() end)

-- Close the diff viewer
keys(600, "q")
step(800, function() end)

-- ============================================================================
-- Part B: 3-way staging view (~15s)
-- ============================================================================

-- Navigate to a staged/unstaged file for 3-way view
-- We're back in status — go to staged section
keys(300, "<M-n>")
keys(200, "<M-n>")
keys(200, "<M-n>")
step(600, function() end)

-- Open diff popup and trigger 3-way action directly
keys(600, "d")
step(1200, function()
  local popup_win = vim.api.nvim_get_current_win()
  local popup_config = vim.api.nvim_win_get_config(popup_win)
  if popup_config.relative and popup_config.relative ~= "" then
    vim.api.nvim_win_close(popup_win, true)
  end
  local diff_popup = require("gitlad.popups.diff")
  local state = require("gitlad.state")
  local repo_state = state.get(vim.fn.getcwd())
  diff_popup._diff_3way(repo_state)
end)
step(2500, function() end)

-- Pause to show the 3-pane layout
step(3000, function() end)

-- Close the 3-way view
keys(600, "q")
step(800, function() end)

-- ============================================================================
-- Part C: Merge conflict resolution (~20s)
-- ============================================================================

-- Create a merge conflict by merging feature/conflict-merge
step(500, function()
  local repo = vim.fn.getcwd()
  -- Reset any leftover state from previous parts
  vim.fn.system("cd " .. vim.fn.shellescape(repo) .. " && git checkout -- . && git reset HEAD -- . 2>/dev/null")
  vim.fn.system("cd " .. vim.fn.shellescape(repo) .. " && git stash 2>/dev/null")
  -- Attempt merge (will conflict on App.js)
  vim.fn.system("cd " .. vim.fn.shellescape(repo) .. " && git merge feature/conflict-merge 2>/dev/null || true")
end)

-- Refresh status to show the conflicted section
keys(800, "gr")
step(2500, function() end)

-- Navigate to the conflicted section for visual effect
-- After merge: Untracked → Unstaged (lib) → Conflicted (App.js) → 3 M-n presses
keys(300, "gg")
step(200, function() end)
keys(300, "<M-n>")
keys(200, "<M-n>")
keys(200, "<M-n>")
step(800, function() end)

-- Navigate to the conflicted file entry
keys(300, "gj")
step(1000, function() end)

-- Open 3-way merge view directly via Lua (same approach as Parts A/B)
step(600, function()
  local diff_popup = require("gitlad.popups.diff")
  local state = require("gitlad.state")
  local repo_state = state.get(vim.fn.getcwd())
  diff_popup._diff_merge_3way(repo_state)
end)
step(3000, function() end)

-- Pause to show the 3-pane merge layout (OURS | WORKTREE | THEIRS)
step(1500, function() end)

-- Resolve all conflicts: delete marker lines, keep "ours" version.
-- Write resolved content directly to disk (bypasses diff view's BufWriteCmd
-- which has focus/timing issues when called from the demo driver).
step(400, function()
  local file_path = vim.fn.getcwd() .. "/src/components/App.js"
  local f = io.open(file_path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()

  -- Strip conflict markers, keeping "ours" version
  local resolved = {}
  local in_theirs = false
  for line in content:gmatch("([^\n]*)\n?") do
    if line:match("^<<<<<<<") then
      -- skip
    elseif line:match("^=======$") then
      in_theirs = true
    elseif line:match("^>>>>>>>") then
      in_theirs = false
    elseif not in_theirs then
      table.insert(resolved, line)
    end
  end

  -- Write resolved content to disk
  f = io.open(file_path, "w")
  f:write(table.concat(resolved, "\n"))
  f:close()

  -- Update the worktree buffer to match and mark it as saved
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("worktree") then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, resolved)
      vim.bo[buf].modified = false
      break
    end
  end
end)
step(2500, function() end)

-- Stage the resolved file
keys(500, "s")
step(1500, function() end)

-- Close the merge view
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
