---@mod gitlad.ui.views.log Git log view
---@brief [[
--- Buffer showing git commit log with navigation and actions.
--- Opened via log popup (l keymap in status buffer).
---@brief ]]

local M = {}

local log_list = require("gitlad.ui.components.log_list")
local keymap = require("gitlad.utils.keymap")
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")
local git = require("gitlad.git")
local signs_util = require("gitlad.ui.utils.signs")

-- Namespace for sign column indicators
local ns_signs = vim.api.nvim_create_namespace("gitlad_log_signs")

---@class LogSignInfo
---@field expanded boolean Whether the commit is expanded

---@class LogBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field commits GitCommitInfo[] Current commits
---@field args string[] Git log arguments used to fetch commits
---@field line_map table<number, CommitLineInfo> Map of line numbers to commit info
---@field expanded_commits table<string, boolean> Map of commit hash to expanded state
---@field commit_ranges table<string, {start: number, end_line: number}> Hash → line range
---@field sign_lines table<number, LogSignInfo> Map of line numbers to sign info
local LogBuffer = {}
LogBuffer.__index = LogBuffer

-- Singleton buffer (one log view at a time)
local log_buffer = nil

--- Create or get the log buffer
---@param repo_state RepoState
---@return LogBuffer
local function get_or_create_buffer(repo_state)
  if log_buffer and vim.api.nvim_buf_is_valid(log_buffer.bufnr) then
    log_buffer.repo_state = repo_state
    return log_buffer
  end

  local self = setmetatable({}, LogBuffer)
  self.repo_state = repo_state
  self.commits = {}
  self.args = {}
  self.line_map = {}
  self.expanded_commits = {}
  self.commit_ranges = {}
  self.sign_lines = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://log")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-log"

  -- Set up keymaps
  self:_setup_keymaps()

  log_buffer = self
  return self
end

--- Set up buffer keymaps
function LogBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Navigation (evil-collection-magit style: gj/gk for commits, j/k for normal line movement)
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_commit()
  end, "Next commit")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_commit()
  end, "Previous commit")

  -- Expand/collapse commit details
  keymap.set(bufnr, "n", "<CR>", function()
    self:_toggle_expand()
  end, "Toggle commit details")
  keymap.set(bufnr, "n", "<Tab>", function()
    self:_toggle_expand()
  end, "Toggle commit details")

  -- Diff popup
  keymap.set(bufnr, "n", "d", function()
    local diff_popup = require("gitlad.popups.diff")
    local commit = self:_get_current_commit()
    diff_popup.open(self.repo_state, { commit = commit })
  end, "Diff popup")

  -- Yank commit hash
  keymap.set(bufnr, "n", "y", function()
    self:_yank_hash()
  end, "Yank commit hash")

  -- Refresh (gr to free up g prefix for vim motions like gg)
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh log")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close log")

  -- Branch popup
  keymap.set(bufnr, "n", "b", function()
    local branch_popup = require("gitlad.popups.branch")
    branch_popup.open(self.repo_state)
  end, "Branch popup")

  -- Rebase popup
  keymap.set(bufnr, "n", "r", function()
    local rebase_popup = require("gitlad.popups.rebase")
    rebase_popup.open(self.repo_state)
  end, "Rebase popup")

  -- Cherry-pick popup
  keymap.set(bufnr, "n", "A", function()
    local cherrypick_popup = require("gitlad.popups.cherrypick")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    cherrypick_popup.open(self.repo_state, context)
  end, "Cherry-pick popup")

  -- Revert popup
  keymap.set(bufnr, "n", "_", function()
    local revert_popup = require("gitlad.popups.revert")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    revert_popup.open(self.repo_state, context)
  end, "Revert popup")

  -- Reset popup
  keymap.set(bufnr, "n", "X", function()
    local reset_popup = require("gitlad.popups.reset")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    reset_popup.open(self.repo_state, context)
  end, "Reset popup")
end

--- Get current commit under cursor
---@return GitCommitInfo|nil, string|nil commit, section
function LogBuffer:_get_current_commit()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local info = self.line_map[line]
  if info and info.type == "commit" then
    return info.commit, info.section
  end
  return nil, nil
end

--- Get selected commits (normal or visual mode)
---@return GitCommitInfo[]
function LogBuffer:_get_selected_commits()
  local mode = vim.fn.mode()
  if mode:match("[vV]") then
    -- Exit visual mode to set marks
    vim.cmd("normal! ")
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    return log_list.get_commits_in_range(self.line_map, start_line, end_line)
  else
    local commit = self:_get_current_commit()
    if commit then
      return { commit }
    end
  end
  return {}
end

--- Navigate to next commit
function LogBuffer:_goto_next_commit()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find next line with a commit
  for line = current_line + 1, vim.api.nvim_buf_line_count(self.bufnr) do
    local info = self.line_map[line]
    if info and info.type == "commit" then
      -- Check if this is a new commit (not expanded body line of same commit)
      local current_info = self.line_map[current_line]
      if not current_info or info.hash ~= current_info.hash then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        return
      end
    end
  end
end

--- Navigate to previous commit
function LogBuffer:_goto_prev_commit()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  local current_hash = nil

  local info = self.line_map[current_line]
  if info and info.type == "commit" then
    current_hash = info.hash
  end

  -- Find previous line with a different commit
  for line = current_line - 1, 1, -1 do
    local prev_info = self.line_map[line]
    if prev_info and prev_info.type == "commit" then
      if prev_info.hash ~= current_hash then
        -- Go to the first line of this commit
        local range = self.commit_ranges[prev_info.hash]
        if range then
          vim.api.nvim_win_set_cursor(0, { range.start, 0 })
        else
          vim.api.nvim_win_set_cursor(0, { line, 0 })
        end
        return
      end
    end
  end
end

--- Toggle expand/collapse of current commit
function LogBuffer:_toggle_expand()
  local commit = self:_get_current_commit()
  if not commit then
    return
  end

  local hash = commit.hash
  local is_expanded = self.expanded_commits[hash]

  if is_expanded then
    -- Collapse
    self.expanded_commits[hash] = nil
    self:render()
  else
    -- Need to fetch body if not available
    if commit.body then
      self.expanded_commits[hash] = true
      self:render()
    else
      -- Fetch full commit message
      git.show_commit(hash, { cwd = self.repo_state.repo_root }, function(body, err)
        vim.schedule(function()
          if err then
            vim.notify("[gitlad] Failed to get commit: " .. err, vim.log.levels.ERROR)
            return
          end
          -- Update commit in place
          commit.body = body
          self.expanded_commits[hash] = true
          self:render()
        end)
      end)
    end
  end
end

--- Yank commit hash to clipboard
function LogBuffer:_yank_hash()
  local commit = self:_get_current_commit()
  if not commit then
    return
  end

  vim.fn.setreg("+", commit.hash)
  vim.fn.setreg('"', commit.hash)
  vim.notify("[gitlad] Yanked: " .. commit.hash, vim.log.levels.INFO)
end

--- Refresh log with current arguments
function LogBuffer:refresh()
  vim.notify("[gitlad] Refreshing log...", vim.log.levels.INFO)

  git.log_detailed(self.args, { cwd = self.repo_state.repo_root }, function(commits, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Log failed: " .. err, vim.log.levels.ERROR)
        return
      end

      self.commits = commits or {}
      -- Keep expansion state, but clear body cache on commits that may have changed
      self:render()
    end)
  end)
end

--- Render the log buffer
function LogBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local lines = {}
  self.line_map = {}
  self.commit_ranges = {}
  self.sign_lines = {}

  -- Header
  local header = "Commits"
  if #self.args > 0 then
    header = header .. " (" .. table.concat(self.args, " ") .. ")"
  end
  table.insert(lines, header)
  table.insert(lines, string.format("%d commits", #self.commits))
  table.insert(lines, "")
  table.insert(lines, "Press <CR>/<Tab> expand, d diff, y yank hash, g refresh, q close")
  table.insert(lines, "")

  local header_lines = #lines

  if #self.commits == 0 then
    table.insert(lines, "No commits found.")
  else
    -- Use log_list component to render commits
    local result = log_list.render(self.commits, self.expanded_commits, {
      indent = 0,
      section = "log",
      show_author = true,
      show_date = true,
    })

    -- Add rendered lines and update line_map with correct offsets
    for i, line in ipairs(result.lines) do
      table.insert(lines, line)
      local info = result.line_info[i]
      if info then
        self.line_map[#lines] = info
      end
    end

    -- Update commit_ranges with correct offsets and track sign_lines
    for hash, range in pairs(result.commit_ranges) do
      local adjusted_start = range.start + header_lines
      self.commit_ranges[hash] = {
        start = adjusted_start,
        end_line = range.end_line + header_lines,
      }
      -- Add sign indicator for the first line of each commit
      self.sign_lines[adjusted_start] = {
        expanded = self.expanded_commits[hash] or false,
      }
    end
  end

  -- Allow modification while updating buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply syntax highlighting
  self:_apply_highlights(header_lines)

  -- Place expand/collapse signs
  self:_place_signs()

  -- Make buffer non-modifiable to prevent accidental edits
  vim.bo[self.bufnr].modifiable = false
end

--- Apply syntax highlighting
---@param header_lines number Number of header lines before commits
function LogBuffer:_apply_highlights(header_lines)
  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  -- Header highlighting (use set_line for entire line)
  hl.set_line(self.bufnr, ns, 0, "GitladSectionHeader")

  -- Use log_list's highlight function for commit lines
  if #self.commits > 0 then
    local result = log_list.render(self.commits, self.expanded_commits, {
      indent = 0,
      section = "log",
      show_author = true,
      show_date = true,
    })
    log_list.apply_highlights(self.bufnr, header_lines, result)
  end
end

--- Place expand/collapse signs in the sign column
function LogBuffer:_place_signs()
  signs_util.place_expand_signs(self.bufnr, self.sign_lines, ns_signs)
end

--- Open the log buffer in a window
---@param repo_state RepoState
---@param commits GitCommitInfo[]
---@param args string[]
function LogBuffer:open_with_commits(repo_state, commits, args)
  self.repo_state = repo_state
  self.commits = commits
  self.args = args
  self.expanded_commits = {}

  -- Check if already open
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    self:render()
    return
  end

  -- Open in current window (like status buffer)
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window-local options for clean log display
  utils.setup_view_window_options(self.winnr)

  self:render()

  -- Position cursor on first commit
  local first_commit_line = 6 -- After header
  if self.line_map[first_commit_line] then
    vim.api.nvim_win_set_cursor(self.winnr, { first_commit_line, 0 })
  end
end

--- Close the log buffer
function LogBuffer:close()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = nil
    return
  end

  -- Go back to previous buffer or close window
  local prev_buf = vim.fn.bufnr("#")
  if prev_buf ~= -1 and vim.api.nvim_buf_is_valid(prev_buf) then
    vim.api.nvim_set_current_buf(prev_buf)
  else
    vim.cmd("quit")
  end
  self.winnr = nil
end

--- Open log view (module-level entry point)
---@param repo_state RepoState
---@param commits GitCommitInfo[]
---@param args string[]
function M.open(repo_state, commits, args)
  local buf = get_or_create_buffer(repo_state)
  buf:open_with_commits(repo_state, commits, args)
end

--- Close log view
function M.close()
  if log_buffer then
    log_buffer:close()
  end
end

--- Get current log buffer (for testing)
---@return LogBuffer|nil
function M.get_buffer()
  return log_buffer
end

--- Clear the buffer singleton (for testing)
function M.clear()
  if log_buffer then
    if vim.api.nvim_buf_is_valid(log_buffer.bufnr) then
      vim.api.nvim_buf_delete(log_buffer.bufnr, { force = true })
    end
    log_buffer = nil
  end
end

return M
