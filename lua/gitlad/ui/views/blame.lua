---@mod gitlad.ui.views.blame Git blame view
---@brief [[
--- Fugitive-style side-by-side blame view.
--- Left pane: blame annotations (nofile scratch buffer).
--- Right pane: file content with syntax highlighting.
--- Both synchronized via scrollbind/cursorbind.
---@brief ]]

local M = {}

local keymap = require("gitlad.utils.keymap")
local hl = require("gitlad.ui.hl")
local git = require("gitlad.git")

---@class BlameBuffer
---@field annotation_bufnr number Annotation buffer number
---@field file_bufnr number File content buffer number
---@field annotation_winnr number|nil Annotation window number
---@field file_winnr number|nil File content window number
---@field repo_state RepoState Repository state
---@field blame_result BlameResult|nil Current blame data
---@field file string File path (relative to repo root)
---@field revision string|nil Revision being blamed at (nil for working tree)
---@field extra_args string[] Extra blame args (e.g., {"-w", "-M"})
---@field line_map table<number, BlameLineInfo> Map of line numbers to blame info
---@field chunk_boundaries number[] Line numbers where chunks change (1-indexed)
---@field revision_stack string[] Stack of revisions for blame-on-blame navigation
local BlameBuffer = {}
BlameBuffer.__index = BlameBuffer

---@class BlameLineInfo
---@field type string Always "blame"
---@field hash string Commit hash
---@field commit BlameCommitInfo Commit info

-- Active blame buffers by repo root
local blame_buffers = {}

-- Annotation column width
local ANNOTATION_WIDTH = 45

--- Format a timestamp as a short date string
---@param timestamp number Epoch seconds
---@return string
local function format_date(timestamp)
  if timestamp == 0 then
    return ""
  end
  return os.date("%b %d", timestamp) --[[@as string]]
end

--- Truncate a string to a maximum display width
---@param str string
---@param max_width number
---@return string
local function truncate(str, max_width)
  if #str <= max_width then
    return str
  end
  return str:sub(1, max_width - 1) .. "…"
end

--- Check if a hash represents uncommitted changes
---@param hash string
---@return boolean
local function is_uncommitted(hash)
  return hash:match("^0+$") ~= nil
end

--- Format a single annotation line
---@param blame_line BlameLine
---@param commit BlameCommitInfo
---@return string
local function format_annotation_line(blame_line, commit)
  local hash_short = blame_line.hash:sub(1, 7)
  local author = truncate(commit.author, 10)
  local date = format_date(commit.author_time)
  local summary = truncate(commit.summary, 20)

  if is_uncommitted(blame_line.hash) then
    return string.format("%-7s %-10s  %-6s  %s", "", "Not Yet", "", "Committed")
  end

  return string.format("%-7s %-10s  %-6s  %s", hash_short, author, date, summary)
end

--- Get or create a blame buffer for a repository
---@param repo_state RepoState
---@return BlameBuffer
local function create_blame_buffer(repo_state)
  local self = setmetatable({}, BlameBuffer)
  self.repo_state = repo_state
  self.file = ""
  self.revision = nil
  self.extra_args = {}
  self.blame_result = nil
  self.line_map = {}
  self.chunk_boundaries = {}
  self.revision_stack = {}

  return self
end

--- Set up keymaps on the annotation buffer
function BlameBuffer:_setup_keymaps()
  local bufnr = self.annotation_bufnr

  -- Navigate blame chunks
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_chunk()
  end, "Next blame chunk")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_chunk()
  end, "Previous blame chunk")

  -- Show commit diff
  keymap.set(bufnr, "n", "<CR>", function()
    local info = self:_get_current_info()
    if info and not is_uncommitted(info.hash) then
      local diff_popup = require("gitlad.popups.diff")
      diff_popup._diff_commit(self.repo_state, { hash = info.hash })
    end
  end, "Show commit diff")

  -- Yank commit hash
  keymap.set(bufnr, "n", "y", function()
    self:_yank_hash()
  end, "Yank commit hash")

  -- Refresh
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh blame")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close blame")

  -- Blame popup (for switches)
  keymap.set(bufnr, "n", "B", function()
    local blame_popup = require("gitlad.popups.blame")
    blame_popup.open(self.repo_state, { blame_buffer = self })
  end, "Blame popup")

  -- Blame-on-blame
  keymap.set(bufnr, "n", "b", function()
    self:_blame_on_blame()
  end, "Blame parent revision")

  -- Navigate same-commit chunks
  keymap.set(bufnr, "n", "gJ", function()
    self:_goto_next_same_commit_chunk()
  end, "Next chunk from same commit")
  keymap.set(bufnr, "n", "gK", function()
    self:_goto_prev_same_commit_chunk()
  end, "Previous chunk from same commit")
end

--- Get blame info at current cursor
---@return BlameLineInfo|nil
function BlameBuffer:_get_current_info()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return self.line_map[line]
end

--- Navigate to next chunk boundary
function BlameBuffer:_goto_next_chunk()
  local current = vim.api.nvim_win_get_cursor(0)[1]
  for _, boundary in ipairs(self.chunk_boundaries) do
    if boundary > current then
      vim.api.nvim_win_set_cursor(0, { boundary, 0 })
      return
    end
  end
end

--- Navigate to previous chunk boundary
function BlameBuffer:_goto_prev_chunk()
  local current = vim.api.nvim_win_get_cursor(0)[1]
  for i = #self.chunk_boundaries, 1, -1 do
    if self.chunk_boundaries[i] < current then
      vim.api.nvim_win_set_cursor(0, { self.chunk_boundaries[i], 0 })
      return
    end
  end
end

--- Navigate to next chunk from the same commit
function BlameBuffer:_goto_next_same_commit_chunk()
  local info = self:_get_current_info()
  if not info then
    return
  end
  local current_hash = info.hash
  local current = vim.api.nvim_win_get_cursor(0)[1]

  -- Find next chunk boundary that matches this commit
  for _, boundary in ipairs(self.chunk_boundaries) do
    if boundary > current then
      local boundary_info = self.line_map[boundary]
      if boundary_info and boundary_info.hash == current_hash then
        vim.api.nvim_win_set_cursor(0, { boundary, 0 })
        return
      end
    end
  end
end

--- Navigate to previous chunk from the same commit
function BlameBuffer:_goto_prev_same_commit_chunk()
  local info = self:_get_current_info()
  if not info then
    return
  end
  local current_hash = info.hash
  local current = vim.api.nvim_win_get_cursor(0)[1]

  for i = #self.chunk_boundaries, 1, -1 do
    if self.chunk_boundaries[i] < current then
      local boundary_info = self.line_map[self.chunk_boundaries[i]]
      if boundary_info and boundary_info.hash == current_hash then
        vim.api.nvim_win_set_cursor(0, { self.chunk_boundaries[i], 0 })
        return
      end
    end
  end
end

--- Yank commit hash to clipboard
function BlameBuffer:_yank_hash()
  local info = self:_get_current_info()
  if not info or is_uncommitted(info.hash) then
    return
  end
  local short_hash = info.hash:sub(1, 7)
  vim.fn.setreg("+", short_hash)
  vim.fn.setreg('"', short_hash)
  vim.notify("[gitlad] Yanked: " .. short_hash, vim.log.levels.INFO)
end

--- Blame the parent revision of the commit at cursor
function BlameBuffer:_blame_on_blame()
  local info = self:_get_current_info()
  if not info then
    return
  end

  if is_uncommitted(info.hash) then
    vim.notify("[gitlad] Cannot blame parent of uncommitted changes", vim.log.levels.WARN)
    return
  end

  local commit = info.commit
  if commit.boundary then
    vim.notify("[gitlad] This is a boundary commit (root of history)", vim.log.levels.WARN)
    return
  end

  if not commit.previous_hash then
    vim.notify("[gitlad] No parent revision available", vim.log.levels.WARN)
    return
  end

  -- Push current revision onto stack for back-navigation
  table.insert(self.revision_stack, self.revision or "HEAD")

  local prev_file = commit.previous_filename or self.file
  self.revision = commit.previous_hash
  self.file = prev_file

  self:refresh()
end

--- Refresh the blame
function BlameBuffer:refresh()
  vim.notify("[gitlad] Blaming...", vim.log.levels.INFO)

  git.blame(
    self.file,
    self.revision,
    self.extra_args,
    { cwd = self.repo_state.repo_root },
    function(result, err)
      vim.schedule(function()
        if err then
          vim.notify("[gitlad] Blame failed: " .. err, vim.log.levels.ERROR)
          return
        end

        self.blame_result = result
        self:render()
      end)
    end
  )
end

--- Render the blame view (both annotation and file buffers)
function BlameBuffer:render()
  if not self.blame_result then
    return
  end

  local blame = self.blame_result
  local annotation_lines = {}
  local file_lines = {}
  self.line_map = {}
  self.chunk_boundaries = {}

  local prev_hash = nil
  local chunk_index = 0

  for i, bl in ipairs(blame.lines) do
    local commit = blame.commits[bl.hash]
    if commit then
      -- Track chunk boundaries
      if bl.hash ~= prev_hash then
        chunk_index = chunk_index + 1
        table.insert(self.chunk_boundaries, i)
        prev_hash = bl.hash
      end

      table.insert(annotation_lines, format_annotation_line(bl, commit))
      table.insert(file_lines, bl.content)

      self.line_map[i] = {
        type = "blame",
        hash = bl.hash,
        commit = commit,
      }
    end
  end

  -- Populate annotation buffer
  if vim.api.nvim_buf_is_valid(self.annotation_bufnr) then
    vim.bo[self.annotation_bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(self.annotation_bufnr, 0, -1, false, annotation_lines)
    vim.bo[self.annotation_bufnr].modifiable = false
  end

  -- Populate file buffer
  if vim.api.nvim_buf_is_valid(self.file_bufnr) then
    vim.bo[self.file_bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(self.file_bufnr, 0, -1, false, file_lines)
    vim.bo[self.file_bufnr].modifiable = false
  end

  -- Apply highlights
  self:_apply_highlights()

  -- Update buffer name with revision info
  self:_update_buffer_names()
end

--- Update buffer names with revision info
function BlameBuffer:_update_buffer_names()
  local key = self.repo_state.repo_root
  local rev_suffix = self.revision and (" @ " .. self.revision:sub(1, 7)) or ""
  local name = "gitlad://blame[" .. key .. "]:" .. self.file .. rev_suffix

  if vim.api.nvim_buf_is_valid(self.annotation_bufnr) then
    pcall(vim.api.nvim_buf_set_name, self.annotation_bufnr, name)
  end
  if vim.api.nvim_buf_is_valid(self.file_bufnr) then
    pcall(vim.api.nvim_buf_set_name, self.file_bufnr, name .. ":content")
  end
end

--- Apply highlights to the annotation buffer
function BlameBuffer:_apply_highlights()
  if not vim.api.nvim_buf_is_valid(self.annotation_bufnr) then
    return
  end

  local ns = hl.get_namespaces().status
  vim.api.nvim_buf_clear_namespace(self.annotation_bufnr, ns, 0, -1)

  local blame = self.blame_result
  if not blame then
    return
  end

  local prev_hash = nil
  local chunk_index = 0

  for i, bl in ipairs(blame.lines) do
    local commit = blame.commits[bl.hash]
    if commit then
      local line_idx = i - 1 -- 0-indexed

      -- Track chunks for alternating backgrounds
      if bl.hash ~= prev_hash then
        chunk_index = chunk_index + 1
        prev_hash = bl.hash
      end

      -- Alternating chunk backgrounds
      local chunk_hl = (chunk_index % 2 == 0) and "GitladBlameChunkEven" or "GitladBlameChunkOdd"
      hl.set_line(self.annotation_bufnr, ns, line_idx, chunk_hl)

      -- Get the annotation line text for positioning highlights
      local ann_lines =
        vim.api.nvim_buf_get_lines(self.annotation_bufnr, line_idx, line_idx + 1, false)
      if #ann_lines > 0 then
        if is_uncommitted(bl.hash) then
          -- Highlight entire line as uncommitted
          hl.set(self.annotation_bufnr, ns, line_idx, 0, #ann_lines[1], "GitladBlameUncommitted")
        else
          -- Hash (first 7 chars)
          hl.set(self.annotation_bufnr, ns, line_idx, 0, 7, "GitladBlameHash")

          -- Author (cols 8-17)
          local author_start = 8
          local author_text = truncate(commit.author, 10)
          hl.set(
            self.annotation_bufnr,
            ns,
            line_idx,
            author_start,
            author_start + #author_text,
            "GitladBlameAuthor"
          )

          -- Date (cols 20-25)
          local date_text = format_date(commit.author_time)
          if date_text ~= "" then
            local date_start = 20
            hl.set(
              self.annotation_bufnr,
              ns,
              line_idx,
              date_start,
              date_start + #date_text,
              "GitladBlameDate"
            )
          end

          -- Summary (cols 28+)
          local summary_start = 28
          local summary_text = truncate(commit.summary, 20)
          if #ann_lines[1] > summary_start then
            hl.set(
              self.annotation_bufnr,
              ns,
              line_idx,
              summary_start,
              math.min(summary_start + #summary_text, #ann_lines[1]),
              "GitladBlameSummary"
            )
          end

          -- Boundary indicator
          if commit.boundary then
            hl.set(self.annotation_bufnr, ns, line_idx, 0, 7, "GitladBlameBoundary")
          end
        end
      end
    end
  end
end

--- Open the blame view as a side-by-side split
---@param repo_state RepoState
---@param file string File path relative to repo root
---@param revision? string Revision to blame at
---@param extra_args? string[] Extra blame args
function BlameBuffer:open(repo_state, file, revision, extra_args)
  self.repo_state = repo_state
  self.file = file
  self.revision = revision
  self.extra_args = extra_args or {}
  self.revision_stack = {}

  -- Create annotation buffer (left)
  self.annotation_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self.annotation_bufnr].buftype = "nofile"
  vim.bo[self.annotation_bufnr].bufhidden = "wipe"
  vim.bo[self.annotation_bufnr].swapfile = false
  vim.bo[self.annotation_bufnr].filetype = "gitlad-blame"

  -- Create file buffer (right)
  self.file_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self.file_bufnr].buftype = "nofile"
  vim.bo[self.file_bufnr].bufhidden = "wipe"
  vim.bo[self.file_bufnr].swapfile = false

  -- Detect filetype for syntax highlighting
  local ft = vim.filetype.match({ filename = file })
  if ft then
    vim.bo[self.file_bufnr].filetype = ft
  end

  self:_update_buffer_names()

  -- Set up keymaps on annotation buffer
  self:_setup_keymaps()

  -- Create the split layout:
  -- 1. Open annotation buffer in a vertical split (left)
  vim.cmd("vsplit")
  self.annotation_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.annotation_winnr, self.annotation_bufnr)
  vim.api.nvim_win_set_width(self.annotation_winnr, ANNOTATION_WIDTH)

  -- 2. Open file buffer in the right window
  vim.cmd("wincmd l")
  self.file_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.file_winnr, self.file_bufnr)

  -- Set up synchronized scrolling on both windows
  for _, winnr in ipairs({ self.annotation_winnr, self.file_winnr }) do
    local opts = { win = winnr, scope = "local" }
    vim.api.nvim_set_option_value("scrollbind", true, opts)
    vim.api.nvim_set_option_value("cursorbind", true, opts)
    vim.api.nvim_set_option_value("wrap", false, opts)
    vim.api.nvim_set_option_value("number", false, opts)
    vim.api.nvim_set_option_value("relativenumber", false, opts)
    vim.api.nvim_set_option_value("signcolumn", "no", opts)
    vim.api.nvim_set_option_value("foldcolumn", "0", opts)
  end

  -- Focus the annotation (left) window for navigation
  vim.api.nvim_set_current_win(self.annotation_winnr)

  -- Set up WinClosed autocmd to clean up when either window is closed
  local key = repo_state.repo_root
  self._autocmd_id = vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      if closed_win == self.annotation_winnr or closed_win == self.file_winnr then
        -- Defer cleanup to avoid E855 (closing a window inside WinClosed autocmd)
        vim.schedule(function()
          self:_cleanup(closed_win)
          blame_buffers[key] = nil
        end)
        return true -- remove this autocmd
      end
    end,
  })

  -- Register in module table
  blame_buffers[key] = self

  -- Run blame
  self:refresh()
end

--- Clean up when a window is closed
---@param closed_winnr number The window that was closed
function BlameBuffer:_cleanup(closed_winnr)
  -- Close the other window if still valid
  local other_winnr = closed_winnr == self.annotation_winnr and self.file_winnr
    or self.annotation_winnr
  if other_winnr and vim.api.nvim_win_is_valid(other_winnr) then
    vim.api.nvim_win_close(other_winnr, true)
  end

  self.annotation_winnr = nil
  self.file_winnr = nil
end

--- Close the blame view
function BlameBuffer:close()
  local key = self.repo_state.repo_root

  -- Remove autocmd to prevent re-entrant close
  if self._autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self._autocmd_id)
    self._autocmd_id = nil
  end

  -- Close one window, switch the other to previous buffer to avoid E444
  local win_count = #vim.api.nvim_list_wins()

  if win_count <= 2 then
    -- Only 2 windows: close annotation, switch file window to previous buffer
    if self.annotation_winnr and vim.api.nvim_win_is_valid(self.annotation_winnr) then
      vim.api.nvim_win_close(self.annotation_winnr, true)
    end
    -- The remaining window should show the previous buffer
    local remaining_win = vim.api.nvim_get_current_win()
    local prev_buf = vim.fn.bufnr("#")
    if prev_buf ~= -1 and vim.api.nvim_buf_is_valid(prev_buf) then
      vim.api.nvim_win_set_buf(remaining_win, prev_buf)
    else
      -- Create a new empty buffer if no previous buffer
      vim.api.nvim_win_set_buf(remaining_win, vim.api.nvim_create_buf(true, false))
    end
  else
    -- More than 2 windows: safe to close both
    if self.annotation_winnr and vim.api.nvim_win_is_valid(self.annotation_winnr) then
      vim.api.nvim_win_close(self.annotation_winnr, true)
    end
    if self.file_winnr and vim.api.nvim_win_is_valid(self.file_winnr) then
      vim.api.nvim_win_close(self.file_winnr, true)
    end
  end

  self.annotation_winnr = nil
  self.file_winnr = nil
  blame_buffers[key] = nil
end

-- =============================================================================
-- Module-level API
-- =============================================================================

--- Open blame view for a file
---@param repo_state RepoState
---@param file string File path relative to repo root
---@param revision? string Optional revision
---@param extra_args? string[] Extra blame args
function M.open_file(repo_state, file, revision, extra_args)
  -- Close existing blame if open
  local key = repo_state.repo_root
  if blame_buffers[key] then
    blame_buffers[key]:close()
  end

  local buf = create_blame_buffer(repo_state)
  buf:open(repo_state, file, revision, extra_args)
end

--- Close blame view for a repo
---@param repo_state? RepoState
function M.close(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    if blame_buffers[key] then
      blame_buffers[key]:close()
    end
  else
    for _, buf in pairs(blame_buffers) do
      buf:close()
    end
  end
end

--- Get the blame buffer for a repo if it exists
---@param repo_state? RepoState
---@return BlameBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    return blame_buffers[repo_state.repo_root]
  end
  for _, buf in pairs(blame_buffers) do
    return buf
  end
  return nil
end

--- Clear all blame buffers (for testing)
function M.clear_all()
  for key, buf in pairs(blame_buffers) do
    buf:close()
    blame_buffers[key] = nil
  end
end

return M
