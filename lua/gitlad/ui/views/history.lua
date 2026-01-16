---@mod gitlad.ui.views.history Git command history view
---@brief [[
--- Buffer showing git command history for transparency and debugging.
--- Accessible via `$` keybinding in status buffer.
---@brief ]]

local M = {}

local history = require("gitlad.git.history")

---@class HistoryLineInfo
---@field entry_index number Index into history entries
---@field expanded boolean Whether this entry is expanded

---@class HistoryBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field entries GitHistoryEntry[] Cached entries
---@field expanded table<number, boolean> Map of entry index to expanded state
---@field line_map table<number, HistoryLineInfo> Map of line numbers to entry info
local HistoryBuffer = {}
HistoryBuffer.__index = HistoryBuffer

-- Singleton buffer
local history_buffer = nil

--- Create or get the history buffer
---@return HistoryBuffer
local function get_or_create_buffer()
  if history_buffer and vim.api.nvim_buf_is_valid(history_buffer.bufnr) then
    return history_buffer
  end

  local self = setmetatable({}, HistoryBuffer)
  self.entries = {}
  self.expanded = {}
  self.line_map = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://history")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-history"

  -- Set up keymaps
  self:_setup_keymaps()

  history_buffer = self
  return self
end

--- Set up buffer keymaps
function HistoryBuffer:_setup_keymaps()
  local opts = { buffer = self.bufnr, silent = true }

  -- Toggle expand
  vim.keymap.set("n", "<CR>", function()
    self:_toggle_expand()
  end, vim.tbl_extend("force", opts, { desc = "Toggle expand entry" }))

  vim.keymap.set("n", "<Tab>", function()
    self:_toggle_expand()
  end, vim.tbl_extend("force", opts, { desc = "Toggle expand entry" }))

  -- Refresh
  vim.keymap.set("n", "g", function()
    self:refresh()
  end, vim.tbl_extend("force", opts, { desc = "Refresh history" }))

  -- Close
  vim.keymap.set("n", "q", function()
    self:close()
  end, vim.tbl_extend("force", opts, { desc = "Close history" }))

  vim.keymap.set("n", "$", function()
    self:close()
  end, vim.tbl_extend("force", opts, { desc = "Close history" }))
end

--- Get entry index at current cursor
---@return number|nil
function HistoryBuffer:_get_current_entry_index()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local info = self.line_map[line]
  if info then
    return info.entry_index
  end
  return nil
end

--- Toggle expand state of current entry
function HistoryBuffer:_toggle_expand()
  local idx = self:_get_current_entry_index()
  if not idx then
    return
  end
  self.expanded[idx] = not self.expanded[idx]
  self:render()
end

--- Refresh entries from history
function HistoryBuffer:refresh()
  self.entries = history.get_all()
  self:render()
end

--- Render the history buffer
function HistoryBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local lines = {}
  self.line_map = {}

  -- Header
  table.insert(lines, "Git Command History")
  table.insert(lines, string.format("(%d commands)", #self.entries))
  table.insert(lines, "")
  table.insert(lines, "Press <CR> or <Tab> to expand, q to close")
  table.insert(lines, "")

  if #self.entries == 0 then
    table.insert(lines, "No commands recorded yet.")
  else
    for idx, entry in ipairs(self.entries) do
      local is_expanded = self.expanded[idx]

      if is_expanded then
        -- Full details
        local full_lines = history.format_entry_full(entry)
        for i, line in ipairs(full_lines) do
          table.insert(lines, line)
          if i == 1 then
            -- Only the header line maps to this entry
            self.line_map[#lines] = { entry_index = idx, expanded = true }
          end
        end
      else
        -- Collapsed single line
        local summary_lines = history.format_entry(entry)
        table.insert(lines, summary_lines[1])
        self.line_map[#lines] = { entry_index = idx, expanded = false }
      end
    end
  end

  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
end

--- Open the history buffer in a window
function HistoryBuffer:open()
  -- Check if already open
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    self:refresh()
    return
  end

  -- Open in a split
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window height
  vim.api.nvim_win_set_height(self.winnr, 15)

  -- Refresh and render
  self:refresh()
end

--- Close the history buffer
function HistoryBuffer:close()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = nil
    return
  end

  vim.api.nvim_win_close(self.winnr, false)
  self.winnr = nil
end

--- Open history view
function M.open()
  local buf = get_or_create_buffer()
  buf:open()
end

--- Close history view
function M.close()
  if history_buffer then
    history_buffer:close()
  end
end

--- Toggle history view
function M.toggle()
  if history_buffer and history_buffer.winnr and vim.api.nvim_win_is_valid(history_buffer.winnr) then
    M.close()
  else
    M.open()
  end
end

--- Clear the buffer singleton (useful for testing)
function M.clear()
  if history_buffer then
    if vim.api.nvim_buf_is_valid(history_buffer.bufnr) then
      vim.api.nvim_buf_delete(history_buffer.bufnr, { force = true })
    end
    history_buffer = nil
  end
end

return M
