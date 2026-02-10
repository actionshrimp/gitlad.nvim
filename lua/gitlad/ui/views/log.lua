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

local DEFAULT_LIMIT = 256

--- Parse a -N limit argument from an args list
--- Returns the numeric limit, or nil if no limit arg is found.
--- Only matches bare -N (not --all, --author=foo, etc.)
---@param args string[]
---@return number|nil
function M._parse_limit(args)
  for _, arg in ipairs(args) do
    local n = arg:match("^%-(%d+)$")
    if n then
      return tonumber(n)
    end
  end
  return nil
end

--- Return a new args list with the limit replaced, added, or removed.
--- If new_limit is nil, the limit arg is removed.
--- If no existing limit arg exists, -N is appended.
---@param args string[]
---@param new_limit number|nil
---@return string[]
function M._update_limit(args, new_limit)
  local result = {}
  local replaced = false
  for _, arg in ipairs(args) do
    if arg:match("^%-(%d+)$") then
      if new_limit then
        table.insert(result, "-" .. new_limit)
        replaced = true
      end
      -- else: skip (remove limit)
    else
      table.insert(result, arg)
    end
  end
  if new_limit and not replaced then
    table.insert(result, "-" .. new_limit)
  end
  return result
end

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

-- Log buffers by repo root (one per repo for multi-project support)
local log_buffers = {}

--- Create or get the log buffer for a repository
---@param repo_state RepoState
---@return LogBuffer
local function get_or_create_buffer(repo_state)
  local key = repo_state.repo_root

  if log_buffers[key] and vim.api.nvim_buf_is_valid(log_buffers[key].bufnr) then
    return log_buffers[key]
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

  -- Set buffer options (include repo path for multi-project support)
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://log[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-log"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Clean up when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      log_buffers[key] = nil
    end,
  })

  log_buffers[key] = self
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

  -- Show commit diff (shortcut for d d)
  keymap.set(bufnr, "n", "<CR>", function()
    local diff_popup = require("gitlad.popups.diff")
    local commit = self:_get_current_commit()
    if commit then
      diff_popup._diff_commit(self.repo_state, commit)
    end
  end, "Show commit diff")
  -- Expand/collapse commit details
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

  -- Commit popup (passes commit at point for instant fixup/squash)
  keymap.set(bufnr, "n", "c", function()
    local commit_popup = require("gitlad.popups.commit")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    commit_popup.open(self.repo_state, context)
  end, "Commit popup")

  -- Rebase popup
  keymap.set(bufnr, "n", "r", function()
    local rebase_popup = require("gitlad.popups.rebase")
    local commit = self:_get_current_commit()
    local context = commit and { commit = commit.hash } or nil
    rebase_popup.open(self.repo_state, context)
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

  -- Limit controls
  keymap.set(bufnr, "n", "+", function()
    local limit = self:_get_current_limit() or DEFAULT_LIMIT
    self:_set_limit(limit * 2)
  end, "Double commit limit")

  keymap.set(bufnr, "n", "-", function()
    local limit = self:_get_current_limit() or DEFAULT_LIMIT
    self:_set_limit(math.max(1, math.floor(limit / 2)))
  end, "Halve commit limit")

  keymap.set(bufnr, "n", "=", function()
    local limit = self:_get_current_limit()
    if limit then
      self:_set_limit(nil)
    else
      self:_set_limit(DEFAULT_LIMIT)
    end
  end, "Toggle commit limit")
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

--- Get current limit from args
---@return number|nil
function LogBuffer:_get_current_limit()
  return M._parse_limit(self.args)
end

--- Set a new limit, updating args and refreshing
---@param new_limit number|nil nil to remove limit
function LogBuffer:_set_limit(new_limit)
  self.args = M._update_limit(self.args, new_limit)
  self:refresh()
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

--- Update the winbar with log info
function LogBuffer:_update_winbar()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local status = self.repo_state.status
  local branch = (status and status.branch ~= "") and status.branch or "HEAD"

  local winbar = "%#GitladSectionHeader#Commits in " .. branch:gsub("%%", "%%%%")

  if #self.args > 0 then
    local args_str = table.concat(self.args, " "):gsub("%%", "%%%%")
    winbar = winbar .. " (" .. args_str .. ")"
  end

  winbar = winbar .. " (" .. #self.commits .. ")"

  vim.api.nvim_set_option_value("winbar", winbar, { win = self.winnr, scope = "local" })
end

--- Render the log buffer
function LogBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local show_tags =
    git.config_get_bool("gitlad.showTagsInRefs", { cwd = self.repo_state.repo_root })
  local lines = {}
  self.line_map = {}
  self.commit_ranges = {}
  self.sign_lines = {}

  local header_lines = 0

  self:_update_winbar()

  if #self.commits == 0 then
    table.insert(lines, "No commits found.")
  else
    -- Use log_list component to render commits
    local result = log_list.render(self.commits, self.expanded_commits, {
      indent = 0,
      section = "log",
      show_author = true,
      show_date = true,
      show_tags = show_tags,
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
  self:_apply_highlights(header_lines, show_tags)

  -- Place expand/collapse signs
  self:_place_signs()

  -- Make buffer non-modifiable to prevent accidental edits
  vim.bo[self.bufnr].modifiable = false
end

--- Apply syntax highlighting
---@param header_lines number Number of header lines before commits
---@param show_tags boolean Whether to show tags in refs
function LogBuffer:_apply_highlights(header_lines, show_tags)
  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  -- Use log_list's highlight function for commit lines
  if #self.commits > 0 then
    local result = log_list.render(self.commits, self.expanded_commits, {
      indent = 0,
      section = "log",
      show_author = true,
      show_date = true,
      show_tags = show_tags,
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
  local first_commit_line = 1
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

--- Get the log buffer for a repo if it exists
---@param repo_state? RepoState
---@return LogBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    local buf = log_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end
  -- If no repo_state, return first valid buffer (for backwards compat/testing)
  for _, buf in pairs(log_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

--- Clear all log buffers (for testing)
function M.clear_all()
  for _, buf in pairs(log_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  log_buffers = {}
end

return M
