---@mod gitlad.ui.views.status Status buffer view
---@brief [[
--- Main status buffer showing staged, unstaged, and untracked files.
---@brief ]]

local M = {}

local state = require("gitlad.state")
local config = require("gitlad.config")

---@class LineInfo
---@field path string File path
---@field section "staged"|"unstaged"|"untracked"|"conflicted" Section type

---@class StatusBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field line_map table<number, LineInfo> Map of line numbers to file info
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

-- Active status buffers by repo root
local status_buffers = {}

--- Create or get a status buffer for a repository
---@param repo_state RepoState
---@return StatusBuffer
local function get_or_create_buffer(repo_state)
  local key = repo_state.repo_root

  if status_buffers[key] and vim.api.nvim_buf_is_valid(status_buffers[key].bufnr) then
    return status_buffers[key]
  end

  local self = setmetatable({}, StatusBuffer)
  self.repo_state = repo_state
  self.line_map = {} -- Maps line numbers to file info

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://status")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Listen for status updates
  repo_state:on("status", function()
    vim.schedule(function()
      self:render()
    end)
  end)

  status_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function StatusBuffer:_setup_keymaps()
  local opts = { buffer = self.bufnr, silent = true }

  -- Staging
  vim.keymap.set("n", "s", function()
    self:_stage_current()
  end, vim.tbl_extend("force", opts, { desc = "Stage file" }))

  vim.keymap.set("n", "u", function()
    self:_unstage_current()
  end, vim.tbl_extend("force", opts, { desc = "Unstage file" }))

  -- Refresh
  vim.keymap.set("n", "g", function()
    self.repo_state:refresh_status(true)
  end, vim.tbl_extend("force", opts, { desc = "Refresh status" }))

  -- Close
  vim.keymap.set("n", "q", function()
    self:close()
  end, vim.tbl_extend("force", opts, { desc = "Close status" }))

  -- Navigation (future: expand/collapse, etc.)
  vim.keymap.set("n", "<Tab>", function()
    self:_toggle_diff()
  end, vim.tbl_extend("force", opts, { desc = "Toggle diff" }))
end

--- Get the file path at the current cursor position
---@return string|nil path
---@return string|nil section "staged"|"unstaged"|"untracked"|"conflicted"
function StatusBuffer:_get_current_file()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info then
    return info.path, info.section
  end

  return nil, nil
end

--- Stage the file under cursor
function StatusBuffer:_stage_current()
  local path, section = self:_get_current_file()
  if not path then return end

  if section == "unstaged" or section == "untracked" then
    self.repo_state:stage(path)
  end
end

--- Unstage the file under cursor
function StatusBuffer:_unstage_current()
  local path, section = self:_get_current_file()
  if not path then return end

  if section == "staged" then
    self.repo_state:unstage(path)
  end
end

--- Toggle diff view for current file
function StatusBuffer:_toggle_diff()
  -- TODO: Implement inline diff expansion
  vim.notify("[gitlad] Diff toggle not yet implemented", vim.log.levels.INFO)
end

--- Render the status buffer
function StatusBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local status = self.repo_state.status
  if not status then
    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "Loading..." })
    return
  end

  local cfg = config.get()
  local lines = {}
  self.line_map = {} -- Reset line map

  -- Helper to add a file entry and track its line number
  local function add_file_line(entry, section, sign, status_char, use_display)
    local display = use_display and entry.orig_path
      and string.format("%s -> %s", entry.orig_path, entry.path)
      or entry.path
    local line_text = status_char
      and string.format("  %s %s  %s", sign, status_char, display)
      or string.format("  %s    %s", sign, display)
    table.insert(lines, line_text)
    self.line_map[#lines] = { path = entry.path, section = section }
  end

  -- Header
  table.insert(lines, string.format("Head:     %s", status.branch))
  if status.upstream then
    local ahead_behind = ""
    if status.ahead > 0 or status.behind > 0 then
      ahead_behind = string.format(" [+%d/-%d]", status.ahead, status.behind)
    end
    table.insert(lines, string.format("Upstream: %s%s", status.upstream, ahead_behind))
  end
  table.insert(lines, "")

  -- Staged changes
  if #status.staged > 0 then
    table.insert(lines, string.format("Staged (%d)", #status.staged))
    for _, entry in ipairs(status.staged) do
      add_file_line(entry, "staged", cfg.signs.staged, entry.index_status, true)
    end
    table.insert(lines, "")
  end

  -- Unstaged changes
  if #status.unstaged > 0 then
    table.insert(lines, string.format("Unstaged (%d)", #status.unstaged))
    for _, entry in ipairs(status.unstaged) do
      add_file_line(entry, "unstaged", cfg.signs.unstaged, entry.worktree_status, false)
    end
    table.insert(lines, "")
  end

  -- Untracked files
  if #status.untracked > 0 then
    table.insert(lines, string.format("Untracked (%d)", #status.untracked))
    for _, entry in ipairs(status.untracked) do
      add_file_line(entry, "untracked", cfg.signs.untracked, nil, false)
    end
    table.insert(lines, "")
  end

  -- Conflicted files
  if #status.conflicted > 0 then
    table.insert(lines, string.format("Conflicted (%d)", #status.conflicted))
    for _, entry in ipairs(status.conflicted) do
      add_file_line(entry, "conflicted", cfg.signs.conflict, nil, false)
    end
    table.insert(lines, "")
  end

  -- Clean working tree message
  if #status.staged == 0 and #status.unstaged == 0 and #status.untracked == 0 and #status.conflicted == 0 then
    table.insert(lines, "Nothing to commit, working tree clean")
  end

  -- Help line
  table.insert(lines, "")
  table.insert(lines, "s=stage  u=unstage  g=refresh  q=close")

  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
end

--- Open the status buffer in a window
function StatusBuffer:open()
  -- Check if already open in a window
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    return
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Initial render
  self:render()

  -- Trigger refresh
  self.repo_state:refresh_status()
end

--- Close the status buffer
function StatusBuffer:close()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = nil
    return
  end

  -- Check if this is the last window
  local windows = vim.api.nvim_list_wins()
  if #windows == 1 then
    -- Can't close last window, switch to an empty buffer instead
    local empty_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(self.winnr, empty_buf)
  else
    vim.api.nvim_win_close(self.winnr, false)
  end

  self.winnr = nil
end

--- Open status view for current repository
function M.open()
  local repo_state = state.get()
  if not repo_state then
    vim.notify("[gitlad] Not in a git repository", vim.log.levels.WARN)
    return
  end

  local buf = get_or_create_buffer(repo_state)
  buf:open()
end

--- Close status view
function M.close()
  local repo_state = state.get()
  if not repo_state then return end

  local key = repo_state.repo_root
  local buf = status_buffers[key]
  if buf then
    buf:close()
  end
end

--- Clear all status buffers (useful for testing)
function M.clear_all()
  for _, buf in pairs(status_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  status_buffers = {}
end

return M
