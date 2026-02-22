---@mod gitlad.ui.views.pr_list PR list view
---@brief [[
--- Buffer showing pull request list from forge provider.
--- Opened via forge popup (N l in status buffer).
---@brief ]]

local M = {}

local pr_list_component = require("gitlad.ui.components.pr_list")
local keymap = require("gitlad.utils.keymap")
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")

---@class PRListBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field provider ForgeProvider Forge provider
---@field prs ForgePullRequest[] Current PRs
---@field opts ForgeListPRsOpts List options
---@field line_map table<number, PRLineInfo> Map of line numbers to PR info
local PRListBuffer = {}
PRListBuffer.__index = PRListBuffer

-- PR list buffers by repo root (singleton per repo)
local pr_list_buffers = {}

--- Create or get the PR list buffer for a repository
---@param repo_state RepoState
---@param provider ForgeProvider
---@return PRListBuffer
local function get_or_create_buffer(repo_state, provider)
  local key = repo_state.repo_root

  if pr_list_buffers[key] and vim.api.nvim_buf_is_valid(pr_list_buffers[key].bufnr) then
    local buf = pr_list_buffers[key]
    buf.provider = provider
    return buf
  end

  local self = setmetatable({}, PRListBuffer)
  self.repo_state = repo_state
  self.provider = provider
  self.prs = {}
  self.opts = {}
  self.line_map = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://pr-list[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-pr-list"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Clean up when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      pr_list_buffers[key] = nil
    end,
  })

  pr_list_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function PRListBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Navigation
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_pr()
  end, "Next PR")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_pr()
  end, "Previous PR")

  -- View PR detail
  keymap.set(bufnr, "n", "<CR>", function()
    local pr = self:_get_current_pr()
    if pr then
      local pr_detail_view = require("gitlad.ui.views.pr_detail")
      pr_detail_view.open(self.repo_state, self.provider, pr.number)
    end
  end, "View PR")

  -- Yank PR number
  keymap.set(bufnr, "n", "y", function()
    self:_yank_pr_number()
  end, "Yank PR number")

  -- Open in browser
  keymap.set(bufnr, "n", "o", function()
    local pr = self:_get_current_pr()
    if pr and pr.url ~= "" then
      vim.ui.open(pr.url)
    end
  end, "Open in browser")

  -- Refresh
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh PR list")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close PR list")
end

--- Get current PR under cursor
---@return ForgePullRequest|nil
function PRListBuffer:_get_current_pr()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local info = self.line_map[line]
  if info and info.type == "pr" then
    return info.pr
  end
  return nil
end

--- Navigate to next PR
function PRListBuffer:_goto_next_pr()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line + 1, vim.api.nvim_buf_line_count(self.bufnr) do
    local info = self.line_map[line]
    if info and info.type == "pr" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous PR
function PRListBuffer:_goto_prev_pr()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    local info = self.line_map[line]
    if info and info.type == "pr" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Yank PR number to clipboard
function PRListBuffer:_yank_pr_number()
  local pr = self:_get_current_pr()
  if not pr then
    return
  end

  local text = "#" .. pr.number
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify("[gitlad] Yanked: " .. text, vim.log.levels.INFO)
end

--- Refresh PR list from provider
function PRListBuffer:refresh()
  vim.notify("[gitlad] Refreshing PR list...", vim.log.levels.INFO)

  self.provider:list_prs(self.opts, function(prs, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] PR list failed: " .. err, vim.log.levels.ERROR)
        return
      end

      self.prs = prs or {}
      self:render()
      vim.notify("[gitlad] PR list refreshed (" .. #self.prs .. " PRs)", vim.log.levels.INFO)
    end)
  end)
end

--- Update the winbar with PR list info
function PRListBuffer:_update_winbar()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local winbar = "%#GitladSectionHeader#Pull Requests"
  winbar = winbar .. " (" .. self.provider.owner .. "/" .. self.provider.repo .. ")"
  winbar = winbar .. " (" .. #self.prs .. ")"

  vim.api.nvim_set_option_value("winbar", winbar, { win = self.winnr, scope = "local" })
end

--- Render the PR list buffer
function PRListBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local lines = {}
  self.line_map = {}

  self:_update_winbar()

  if #self.prs == 0 then
    table.insert(lines, "No pull requests found.")
  else
    local result = pr_list_component.render(self.prs, {
      indent = 0,
      max_title_len = 60,
    })

    for i, line in ipairs(result.lines) do
      table.insert(lines, line)
      local info = result.line_info[i]
      if info then
        self.line_map[#lines] = info
      end
    end
  end

  -- Allow modification while updating buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply syntax highlighting
  self:_apply_highlights()

  -- Make buffer non-modifiable
  vim.bo[self.bufnr].modifiable = false
end

--- Apply syntax highlighting
function PRListBuffer:_apply_highlights()
  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  if #self.prs > 0 then
    local result = pr_list_component.render(self.prs, {
      indent = 0,
      max_title_len = 60,
    })
    pr_list_component.apply_highlights(self.bufnr, ns, 0, result)
  end
end

--- Open the PR list buffer with data from provider
---@param repo_state RepoState
---@param provider ForgeProvider
---@param opts ForgeListPRsOpts|nil
function PRListBuffer:open_with_provider(repo_state, provider, opts)
  self.repo_state = repo_state
  self.provider = provider
  self.opts = opts or {}

  -- Check if already open
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    self:refresh()
    return
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window-local options
  utils.setup_view_window_options(self.winnr)

  -- Show loading state
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "Loading pull requests..." })
  vim.bo[self.bufnr].modifiable = false

  -- Fetch PRs
  self:refresh()
end

--- Close the PR list buffer
function PRListBuffer:close()
  utils.close_view_buffer(self)
end

-- =============================================================================
-- Module-level API
-- =============================================================================

--- Open PR list view (module-level entry point)
---@param repo_state RepoState
---@param provider ForgeProvider
---@param opts? ForgeListPRsOpts
function M.open(repo_state, provider, opts)
  local buf = get_or_create_buffer(repo_state, provider)
  buf:open_with_provider(repo_state, provider, opts)
end

--- Close PR list view for a specific repo
---@param repo_state? RepoState
function M.close(repo_state)
  local key = repo_state and repo_state.repo_root or "default"
  local buf = pr_list_buffers[key]
  if buf then
    buf:close()
  end
end

--- Get the PR list buffer for a repo if it exists
---@param repo_state? RepoState
---@return PRListBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    local buf = pr_list_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end
  for _, buf in pairs(pr_list_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

--- Clear all PR list buffers (for testing)
function M.clear_all()
  for _, buf in pairs(pr_list_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  pr_list_buffers = {}
end

return M
