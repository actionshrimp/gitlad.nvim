---@mod gitlad.ui.views.commit_select Commit selection buffer
---@brief [[
--- Floating window for selecting a commit from the log.
--- Used by instant fixup/squash to select target commit.
---@brief ]]

local M = {}

local git = require("gitlad.git")
local log_list = require("gitlad.ui.components.log_list")
local keymap = require("gitlad.utils.keymap")

---@class CommitSelectState
---@field bufnr number Buffer number
---@field winnr number Window number
---@field callback fun(commit: GitCommitInfo|nil) Callback when selection is made
---@field commits GitCommitInfo[] List of commits
---@field line_info table<number, CommitLineInfo> Line info from log_list

--- Active commit selector (only one at a time)
---@type CommitSelectState|nil
local active_selector = nil

--- Close the commit selector
function M.close()
  if active_selector then
    local selector = active_selector
    active_selector = nil
    if vim.api.nvim_win_is_valid(selector.winnr) then
      vim.api.nvim_win_close(selector.winnr, true)
    end
    if vim.api.nvim_buf_is_valid(selector.bufnr) then
      vim.api.nvim_buf_delete(selector.bufnr, { force = true })
    end
  end
end

--- Select the commit at the current cursor position
local function select_current()
  if not active_selector then
    return
  end

  local line = vim.api.nvim_win_get_cursor(active_selector.winnr)[1]
  local info = active_selector.line_info[line]

  local callback = active_selector.callback
  M.close()

  if info and info.commit then
    callback(info.commit)
  else
    callback(nil)
  end
end

--- Cancel the selection
local function cancel()
  if not active_selector then
    return
  end

  local callback = active_selector.callback
  M.close()
  callback(nil)
end

--- Set up keymaps for the commit selector
---@param bufnr number Buffer number
local function setup_keymaps(bufnr)
  local opts = { nowait = true }

  keymap.set(bufnr, "n", "<CR>", select_current, "Select commit", opts)
  keymap.set(bufnr, "n", "<2-LeftMouse>", select_current, "Select commit", opts)
  keymap.set(bufnr, "n", "q", cancel, "Cancel", opts)
  keymap.set(bufnr, "n", "<Esc>", cancel, "Cancel", opts)

  -- Navigation helpers
  keymap.set(bufnr, "n", "j", "j", "Next line", opts)
  keymap.set(bufnr, "n", "k", "k", "Previous line", opts)
  keymap.set(bufnr, "n", "gg", "gg", "First line", opts)
  keymap.set(bufnr, "n", "G", "G", "Last line", opts)
  keymap.set(bufnr, "n", "<C-d>", "<C-d>", "Page down", opts)
  keymap.set(bufnr, "n", "<C-u>", "<C-u>", "Page up", opts)
end

--- Open commit selector
---@param repo_state RepoState
---@param callback fun(commit: GitCommitInfo|nil) Called with selected commit or nil if cancelled
---@param opts? { prompt?: string, limit?: number }
function M.open(repo_state, callback, opts)
  opts = opts or {}
  local limit = opts.limit or 50
  local prompt = opts.prompt or "Select Commit"

  -- Close existing selector
  if active_selector then
    M.close()
  end

  -- Fetch recent commits
  git.log_detailed({ "-" .. limit }, { cwd = repo_state.repo_root }, function(commits, err)
    if err or not commits or #commits == 0 then
      vim.schedule(function()
        vim.notify("[gitlad] Failed to load commits: " .. (err or "no commits"), vim.log.levels.ERROR)
        callback(nil)
      end)
      return
    end

    vim.schedule(function()
      -- Create buffer
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].buftype = "nofile"
      vim.bo[bufnr].bufhidden = "wipe"
      vim.bo[bufnr].swapfile = false
      vim.bo[bufnr].filetype = "gitlad"

      -- Render commits using log_list
      local result = log_list.render(commits, {}, {
        section = "select",
        indent = 1,
        show_author = false,
        show_date = true,
        show_refs = true,
        hash_length = 7,
        max_subject_len = 60,
      })

      -- Add header line
      local header = " " .. prompt .. " (Enter to select, q to cancel)"
      local lines = { header, string.rep("─", #header) }
      vim.list_extend(lines, result.lines)

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modifiable = false

      -- Adjust line_info to account for header lines
      local adjusted_line_info = {}
      local header_offset = 2
      for line_num, info in pairs(result.line_info) do
        adjusted_line_info[line_num + header_offset] = info
      end

      -- Calculate window size
      local max_width = 0
      for _, line in ipairs(lines) do
        max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
      end
      local width = math.min(max_width + 4, vim.o.columns - 10)
      local height = math.min(#lines, vim.o.lines - 10)

      -- Open floating window
      local winnr = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = "minimal",
        border = "rounded",
      })

      -- Set window options
      vim.wo[winnr].cursorline = true
      vim.wo[winnr].wrap = false

      active_selector = {
        bufnr = bufnr,
        winnr = winnr,
        callback = callback,
        commits = commits,
        line_info = adjusted_line_info,
      }

      -- Set up keymaps
      setup_keymaps(bufnr)

      -- Apply highlights
      log_list.apply_highlights(bufnr, header_offset, result)

      -- Position cursor on first commit (after header)
      vim.api.nvim_win_set_cursor(winnr, { header_offset + 1, 0 })

      -- Close on buffer leave
      vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
        buffer = bufnr,
        once = true,
        callback = function()
          -- Small delay to handle intentional navigation
          vim.defer_fn(function()
            if active_selector and active_selector.bufnr == bufnr then
              cancel()
            end
          end, 100)
        end,
      })
    end)
  end)
end

--- Check if commit selector is active
---@return boolean
function M.is_active()
  return active_selector ~= nil
end

return M
