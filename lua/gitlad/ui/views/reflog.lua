---@mod gitlad.ui.views.reflog Git reflog view
---@brief [[
--- Buffer showing git reflog history with navigation and actions.
--- Opened via log popup (l then r/O/H keybindings).
---@brief ]]

local M = {}

local reflog_list = require("gitlad.ui.components.reflog_list")
local keymap = require("gitlad.utils.keymap")
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")
local git = require("gitlad.git")

---@class ReflogBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field ref string The ref being viewed (e.g., "HEAD", "main")
---@field entries ReflogEntry[] Current reflog entries
---@field line_map table<number, ReflogLineInfo> Map of line numbers to entry info
---@field entry_ranges table<string, {start: number, end_line: number}> Selector → line range
local ReflogBuffer = {}
ReflogBuffer.__index = ReflogBuffer

-- Reflog buffers by repo root (one per repo for multi-project support)
local reflog_buffers = {}

--- Create or get the reflog buffer for a repository
---@param repo_state RepoState
---@return ReflogBuffer
local function get_or_create_buffer(repo_state)
  local key = repo_state.repo_root

  if reflog_buffers[key] and vim.api.nvim_buf_is_valid(reflog_buffers[key].bufnr) then
    return reflog_buffers[key]
  end

  local self = setmetatable({}, ReflogBuffer)
  self.repo_state = repo_state
  self.ref = "HEAD"
  self.entries = {}
  self.line_map = {}
  self.entry_ranges = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options (include repo path for multi-project support)
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://reflog[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-reflog"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Clean up when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      reflog_buffers[key] = nil
    end,
  })

  reflog_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function ReflogBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Navigation (evil-collection-magit style: gj/gk for entries, j/k for normal line movement)
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_entry()
  end, "Next entry")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_entry()
  end, "Previous entry")

  -- Show commit diff (shortcut)
  keymap.set(bufnr, "n", "<CR>", function()
    local diff_popup = require("gitlad.popups.diff")
    local entry = self:_get_current_entry()
    if entry then
      -- Create a minimal commit-like object for diff popup
      diff_popup._diff_commit(self.repo_state, { hash = entry.hash })
    end
  end, "Show commit diff")

  -- Diff popup
  keymap.set(bufnr, "n", "d", function()
    local diff_popup = require("gitlad.popups.diff")
    local entry = self:_get_current_entry()
    local commit = entry and { hash = entry.hash } or nil
    diff_popup.open(self.repo_state, { commit = commit })
  end, "Diff popup")

  -- Yank commit hash
  keymap.set(bufnr, "n", "y", function()
    self:_yank_hash()
  end, "Yank commit hash")

  -- Refresh
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh reflog")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close reflog")

  -- Branch popup
  keymap.set(bufnr, "n", "b", function()
    local branch_popup = require("gitlad.popups.branch")
    branch_popup.open(self.repo_state)
  end, "Branch popup")

  -- Commit popup (passes commit at point for instant fixup/squash)
  keymap.set(bufnr, "n", "c", function()
    local commit_popup = require("gitlad.popups.commit")
    local entry = self:_get_current_entry()
    local context = entry and { commit = entry.hash } or nil
    commit_popup.open(self.repo_state, context)
  end, "Commit popup")

  -- Rebase popup
  keymap.set(bufnr, "n", "r", function()
    local rebase_popup = require("gitlad.popups.rebase")
    local entry = self:_get_current_entry()
    local context = entry and { commit = entry.hash } or nil
    rebase_popup.open(self.repo_state, context)
  end, "Rebase popup")

  -- Cherry-pick popup
  keymap.set(bufnr, "n", "A", function()
    local cherrypick_popup = require("gitlad.popups.cherrypick")
    local entry = self:_get_current_entry()
    local context = entry and { commit = entry.hash } or nil
    cherrypick_popup.open(self.repo_state, context)
  end, "Cherry-pick popup")

  -- Revert popup
  keymap.set(bufnr, "n", "_", function()
    local revert_popup = require("gitlad.popups.revert")
    local entry = self:_get_current_entry()
    local context = entry and { commit = entry.hash } or nil
    revert_popup.open(self.repo_state, context)
  end, "Revert popup")

  -- Reset popup
  keymap.set(bufnr, "n", "X", function()
    local reset_popup = require("gitlad.popups.reset")
    local entry = self:_get_current_entry()
    local context = entry and { commit = entry.hash } or nil
    reset_popup.open(self.repo_state, context)
  end, "Reset popup")
end

--- Get current entry under cursor
---@return ReflogEntry|nil
function ReflogBuffer:_get_current_entry()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local info = self.line_map[line]
  if info and info.type == "reflog" then
    return info.entry
  end
  return nil
end

--- Navigate to next entry
function ReflogBuffer:_goto_next_entry()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find next line with an entry
  for line = current_line + 1, vim.api.nvim_buf_line_count(self.bufnr) do
    local info = self.line_map[line]
    if info and info.type == "reflog" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous entry
function ReflogBuffer:_goto_prev_entry()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find previous line with an entry
  for line = current_line - 1, 1, -1 do
    local info = self.line_map[line]
    if info and info.type == "reflog" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Yank commit hash to clipboard
function ReflogBuffer:_yank_hash()
  local entry = self:_get_current_entry()
  if not entry then
    return
  end

  vim.fn.setreg("+", entry.hash)
  vim.fn.setreg('"', entry.hash)
  vim.notify("[gitlad] Yanked: " .. entry.hash, vim.log.levels.INFO)
end

--- Refresh reflog with current ref
function ReflogBuffer:refresh()
  vim.notify("[gitlad] Refreshing reflog...", vim.log.levels.INFO)

  git.reflog(self.ref, { cwd = self.repo_state.repo_root }, function(entries, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Reflog failed: " .. err, vim.log.levels.ERROR)
        return
      end

      self.entries = entries or {}
      self:render()
    end)
  end)
end

--- Render the reflog buffer
function ReflogBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local lines = {}
  self.line_map = {}
  self.entry_ranges = {}

  -- Header
  local header = "Reflog for " .. self.ref
  table.insert(lines, header)
  table.insert(lines, string.format("%d entries", #self.entries))
  table.insert(lines, "")
  table.insert(lines, "Press <CR> diff, y yank, gr refresh, q close")
  table.insert(lines, "")

  local header_lines = #lines

  if #self.entries == 0 then
    table.insert(lines, "No reflog entries found.")
  else
    -- Use reflog_list component to render entries
    local result = reflog_list.render(self.entries, {
      indent = 0,
      section = "reflog",
    })

    -- Add rendered lines and update line_map with correct offsets
    for i, line in ipairs(result.lines) do
      table.insert(lines, line)
      local info = result.line_info[i]
      if info then
        self.line_map[#lines] = info
      end
    end

    -- Update entry_ranges with correct offsets
    for selector, range in pairs(result.entry_ranges) do
      self.entry_ranges[selector] = {
        start = range.start + header_lines,
        end_line = range.end_line + header_lines,
      }
    end
  end

  -- Allow modification while updating buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply syntax highlighting
  self:_apply_highlights(header_lines)

  -- Make buffer non-modifiable to prevent accidental edits
  vim.bo[self.bufnr].modifiable = false
end

--- Apply syntax highlighting
---@param header_lines number Number of header lines before entries
function ReflogBuffer:_apply_highlights(header_lines)
  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  -- Header highlighting
  hl.set_line(self.bufnr, ns, 0, "GitladSectionHeader")

  -- Use reflog_list's highlight function for entry lines
  if #self.entries > 0 then
    local result = reflog_list.render(self.entries, {
      indent = 0,
      section = "reflog",
    })
    reflog_list.apply_highlights(self.bufnr, header_lines, result)
  end
end

--- Open the reflog buffer in a window
---@param repo_state RepoState
---@param ref string The ref to show reflog for
---@param entries ReflogEntry[]
function ReflogBuffer:open_with_entries(repo_state, ref, entries)
  self.repo_state = repo_state
  self.ref = ref
  self.entries = entries

  -- Check if already open
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    self:render()
    return
  end

  -- Open in current window (like status buffer)
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window-local options for clean display
  utils.setup_view_window_options(self.winnr)

  self:render()

  -- Position cursor on first entry
  local first_entry_line = 6 -- After header
  if self.line_map[first_entry_line] then
    vim.api.nvim_win_set_cursor(self.winnr, { first_entry_line, 0 })
  end
end

--- Close the reflog buffer
function ReflogBuffer:close()
  utils.close_view_buffer(self)
end

--- Open reflog view (module-level entry point)
---@param repo_state RepoState
---@param ref string The ref to show reflog for
---@param entries ReflogEntry[]
function M.open(repo_state, ref, entries)
  local buf = get_or_create_buffer(repo_state)
  buf:open_with_entries(repo_state, ref, entries)
end

--- Close reflog view for a repo
---@param repo_state? RepoState
function M.close(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    if reflog_buffers[key] then
      reflog_buffers[key]:close()
    end
  else
    -- Close all if no repo specified
    for _, buf in pairs(reflog_buffers) do
      buf:close()
    end
  end
end

--- Get the reflog buffer for a repo if it exists
---@param repo_state? RepoState
---@return ReflogBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    local buf = reflog_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end
  -- If no repo_state, return first valid buffer (for backwards compat/testing)
  for _, buf in pairs(reflog_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

--- Clear all reflog buffers (for testing)
function M.clear_all()
  for _, buf in pairs(reflog_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  reflog_buffers = {}
end

return M
