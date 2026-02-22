---@mod gitlad.ui.views.pr_detail PR detail view
---@brief [[
--- Buffer showing PR detail with comments and reviews.
--- Opened via <CR> in PR list or N v in status buffer.
---@brief ]]

local M = {}

local comment_component = require("gitlad.ui.components.comment")
local keymap = require("gitlad.utils.keymap")
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")

---@class PRDetailBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field provider ForgeProvider Forge provider
---@field pr ForgePullRequest|nil Current PR data
---@field pr_number number PR number being viewed
---@field line_map table<number, CommentLineInfo> Map of line numbers to line info
---@field ranges table<string, {start: number, end_line: number}> Named ranges
local PRDetailBuffer = {}
PRDetailBuffer.__index = PRDetailBuffer

-- PR detail buffers by repo root (singleton per repo)
local pr_detail_buffers = {}

--- Create or get the PR detail buffer for a repository
---@param repo_state RepoState
---@param provider ForgeProvider
---@return PRDetailBuffer
local function get_or_create_buffer(repo_state, provider)
  local key = repo_state.repo_root

  if pr_detail_buffers[key] and vim.api.nvim_buf_is_valid(pr_detail_buffers[key].bufnr) then
    local buf = pr_detail_buffers[key]
    buf.provider = provider
    return buf
  end

  local self = setmetatable({}, PRDetailBuffer)
  self.repo_state = repo_state
  self.provider = provider
  self.pr = nil
  self.pr_number = 0
  self.line_map = {}
  self.ranges = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://pr-detail[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-pr-detail"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Clean up when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      pr_detail_buffers[key] = nil
    end,
  })

  pr_detail_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function PRDetailBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Navigation between comments/reviews
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_item()
  end, "Next comment/review")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_item()
  end, "Previous comment/review")

  -- Open in browser
  keymap.set(bufnr, "n", "o", function()
    if self.pr and self.pr.url ~= "" then
      vim.ui.open(self.pr.url)
    end
  end, "Open in browser")

  -- Yank PR number
  keymap.set(bufnr, "n", "y", function()
    if self.pr then
      local text = "#" .. self.pr.number
      vim.fn.setreg("+", text)
      vim.fn.setreg('"', text)
      vim.notify("[gitlad] Yanked: " .. text, vim.log.levels.INFO)
    end
  end, "Yank PR number")

  -- Add comment
  keymap.set(bufnr, "n", "c", function()
    self:_add_comment()
  end, "Add comment")

  -- Edit comment at cursor
  keymap.set(bufnr, "n", "e", function()
    self:_edit_comment()
  end, "Edit comment")

  -- Refresh
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh PR detail")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close PR detail")

  -- Diff (placeholder for Milestone 3)
  keymap.set(bufnr, "n", "d", function()
    vim.notify("[gitlad] Native diff viewer coming in Milestone 3", vim.log.levels.INFO)
  end, "View diff (coming soon)")

  -- Help
  keymap.set(bufnr, "n", "?", function()
    self:_show_help()
  end, "Show help")
end

--- Show help popup with PR detail keybindings
function PRDetailBuffer:_show_help()
  local HelpView = require("gitlad.popups.help").HelpView

  local sections = {
    {
      name = "Actions",
      columns = 3,
      items = {
        { key = "c", desc = "Add comment" },
        { key = "e", desc = "Edit comment" },
        { key = "d", desc = "View diff" },
        { key = "o", desc = "Open in browser" },
        { key = "y", desc = "Yank PR number" },
      },
    },
    {
      name = "Navigation",
      columns = 3,
      items = {
        { key = "gj", desc = "Next comment" },
        { key = "gk", desc = "Previous comment" },
      },
    },
    {
      name = "Essential commands",
      columns = 2,
      items = {
        {
          key = "gr",
          desc = "Refresh",
          action = function()
            self:refresh()
          end,
        },
        { key = "q", desc = "Close buffer" },
        { key = "?", desc = "This help" },
      },
    },
  }

  local help_view = HelpView.new(sections)
  help_view:show()
end

--- Get the line info at the cursor position
---@return CommentLineInfo|nil
function PRDetailBuffer:_get_current_info()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return self.line_map[line]
end

--- Navigate to next comment or review
function PRDetailBuffer:_goto_next_item()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line + 1, vim.api.nvim_buf_line_count(self.bufnr) do
    local info = self.line_map[line]
    if info and (info.type == "comment" or info.type == "review") then
      -- Check it's the start of a new item (author line has @)
      local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line - 1, line, false)[1]
      if line_text and line_text:match("@%S+") then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        return
      end
    end
  end
end

--- Navigate to previous comment or review
function PRDetailBuffer:_goto_prev_item()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- First, find the start of the current item (walk backwards to find @author line)
  local current_item_start = nil
  for line = current_line, 1, -1 do
    local info = self.line_map[line]
    if info and (info.type == "comment" or info.type == "review") then
      local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line - 1, line, false)[1]
      if line_text and line_text:match("@%S+") then
        current_item_start = line
        break
      end
    else
      break
    end
  end

  -- Now find the previous item before current_item_start
  local search_from = (current_item_start or current_line) - 1
  for line = search_from, 1, -1 do
    local info = self.line_map[line]
    if info and (info.type == "comment" or info.type == "review") then
      local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line - 1, line, false)[1]
      if line_text and line_text:match("@%S+") then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        return
      end
    end
  end
end

--- Add a new comment to the PR
function PRDetailBuffer:_add_comment()
  if not self.pr then
    return
  end

  local comment_editor = require("gitlad.ui.views.comment_editor")
  local pr_number = self.pr_number
  local provider = self.provider

  comment_editor.open({
    title = "Comment on PR #" .. pr_number,
    on_submit = function(body)
      vim.notify("[gitlad] Submitting comment...", vim.log.levels.INFO)
      provider:add_comment(pr_number, body, function(result, err)
        vim.schedule(function()
          if err then
            vim.notify("[gitlad] Failed to add comment: " .. err, vim.log.levels.ERROR)
            return
          end
          vim.notify("[gitlad] Comment added to PR #" .. pr_number, vim.log.levels.INFO)
          self:refresh()
        end)
      end)
    end,
  })
end

--- Edit the comment at cursor
function PRDetailBuffer:_edit_comment()
  if not self.pr then
    return
  end

  local info = self:_get_current_info()
  if not info or info.type ~= "comment" or not info.comment then
    vim.notify("[gitlad] No comment at cursor", vim.log.levels.WARN)
    return
  end

  local comment = info.comment
  if not comment.database_id then
    vim.notify("[gitlad] Comment cannot be edited (no database ID)", vim.log.levels.WARN)
    return
  end

  local comment_editor = require("gitlad.ui.views.comment_editor")
  local provider = self.provider

  comment_editor.open({
    title = "Edit comment by @" .. comment.author.login,
    initial_body = comment.body,
    on_submit = function(body)
      vim.notify("[gitlad] Updating comment...", vim.log.levels.INFO)
      provider:edit_comment(comment.database_id, body, function(result, err)
        vim.schedule(function()
          if err then
            vim.notify("[gitlad] Failed to edit comment: " .. err, vim.log.levels.ERROR)
            return
          end
          vim.notify("[gitlad] Comment updated", vim.log.levels.INFO)
          self:refresh()
        end)
      end)
    end,
  })
end

--- Refresh PR detail from provider
function PRDetailBuffer:refresh()
  if self.pr_number == 0 then
    return
  end

  vim.notify("[gitlad] Refreshing PR #" .. self.pr_number .. "...", vim.log.levels.INFO)

  self.provider:get_pr(self.pr_number, function(pr, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] PR detail failed: " .. err, vim.log.levels.ERROR)
        return
      end

      self.pr = pr
      self:render()
      vim.notify("[gitlad] PR #" .. self.pr_number .. " refreshed", vim.log.levels.INFO)
    end)
  end)
end

--- Update winbar
function PRDetailBuffer:_update_winbar()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local winbar = "%#GitladSectionHeader#PR"
  if self.pr then
    winbar = winbar .. " #" .. self.pr.number .. ": " .. self.pr.title
  end

  vim.api.nvim_set_option_value("winbar", winbar, { win = self.winnr, scope = "local" })
end

--- Render the PR detail buffer
function PRDetailBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  self:_update_winbar()

  if not self.pr then
    return
  end

  local result = comment_component.render(self.pr)
  local lines = result.lines
  self.line_map = result.line_info
  self.ranges = result.ranges

  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply highlights
  local ns = hl.get_namespaces().status
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
  comment_component.apply_highlights(self.bufnr, ns, 0, result)

  vim.bo[self.bufnr].modifiable = false
end

--- Open the PR detail buffer for a specific PR
---@param repo_state RepoState
---@param provider ForgeProvider
---@param pr_number number PR number to view
function PRDetailBuffer:open_with_pr(repo_state, provider, pr_number)
  self.repo_state = repo_state
  self.provider = provider
  self.pr_number = pr_number

  -- Check if already open in a window
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
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "Loading PR #" .. pr_number .. "..." })
  vim.bo[self.bufnr].modifiable = false

  -- Fetch PR detail
  self:refresh()
end

--- Close the PR detail buffer
function PRDetailBuffer:close()
  utils.close_view_buffer(self)
end

-- =============================================================================
-- Module-level API
-- =============================================================================

--- Open PR detail view (module-level entry point)
---@param repo_state RepoState
---@param provider ForgeProvider
---@param pr_number number
function M.open(repo_state, provider, pr_number)
  local buf = get_or_create_buffer(repo_state, provider)
  buf:open_with_pr(repo_state, provider, pr_number)
end

--- Close PR detail view for a specific repo
---@param repo_state? RepoState
function M.close(repo_state)
  local key = repo_state and repo_state.repo_root or "default"
  local buf = pr_detail_buffers[key]
  if buf then
    buf:close()
  end
end

--- Get the PR detail buffer for a repo if it exists
---@param repo_state? RepoState
---@return PRDetailBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    local buf = pr_detail_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end
  for _, buf in pairs(pr_detail_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

--- Clear all PR detail buffers (for testing)
function M.clear_all()
  for _, buf in pairs(pr_detail_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  pr_detail_buffers = {}
end

return M
