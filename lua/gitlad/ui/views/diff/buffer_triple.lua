---@mod gitlad.ui.views.diff.buffer_triple Diff buffer triple for 3-pane display
---@brief [[
--- Manages three synchronized scratch buffers for 3-way diff display.
--- Left buffer shows HEAD, middle shows INDEX, right shows WORKTREE.
--- All three windows are scrollbound and cursorbind for synchronized navigation.
---@brief ]]

local gutter = require("gitlad.ui.views.diff.gutter")

local M = {}

--- Highlight group mapping for 3-way diff.
--- Left pane: HEAD side of staged diff (left↔mid comparison)
--- Mid pane: INDEX - shows staged changes (compared to HEAD) and also serves as anchor
--- Right pane: WORKTREE side of unstaged diff (mid↔right comparison)
---@type table<string, table<string, string|nil>>
M._hl_for_type = {
  left = {
    context = nil,
    change = "GitladDiffChangeOld",
    delete = "GitladDiffDelete",
    add = nil,
    filler = "GitladDiffFiller",
  },
  mid = {
    context = nil,
    change = "GitladDiffChangeNew", -- INDEX gained content from HEAD
    delete = nil,
    add = "GitladDiffAdd",
    filler = "GitladDiffFiller",
  },
  right = {
    context = nil,
    change = "GitladDiffChangeNew",
    add = "GitladDiffAdd",
    delete = nil,
    filler = "GitladDiffFiller",
  },
}

---@class DiffBufferTriple
---@field left_bufnr number Left (HEAD) buffer number
---@field mid_bufnr number Middle (INDEX) buffer number
---@field right_bufnr number Right (WORKTREE) buffer number
---@field left_winnr number Left window number
---@field mid_winnr number Middle window number
---@field right_winnr number Right window number
---@field left_lines string[] Left buffer line content
---@field mid_lines string[] Middle buffer line content
---@field right_lines string[] Right buffer line content
---@field line_map ThreeWayLineInfo[] Maps buffer line to metadata
---@field file_path string Current file path (for treesitter)
---@field _ns number Namespace for diff highlights
---@field _filler_ns number Namespace for filler line extmarks (editable mode)
---@field _editable boolean Whether mid/right buffers are editable
local DiffBufferTriple = {}
DiffBufferTriple.__index = DiffBufferTriple

--- Create a new DiffBufferTriple. Creates three scratch buffers and assigns them to
--- the given windows. Configures all windows for synchronized scrolling.
---@param left_winnr number Left window number
---@param mid_winnr number Middle window number
---@param right_winnr number Right window number
---@param buf_opts? DiffBufferOpts Options (editable, etc.)
---@return DiffBufferTriple
function M.new(left_winnr, mid_winnr, right_winnr, buf_opts)
  buf_opts = buf_opts or {}
  local self = setmetatable({}, DiffBufferTriple)

  self.left_winnr = left_winnr
  self.mid_winnr = mid_winnr
  self.right_winnr = right_winnr
  self.left_lines = {}
  self.mid_lines = {}
  self.right_lines = {}
  self.line_map = {}
  self.file_path = ""
  self._ns = vim.api.nvim_create_namespace("gitlad_diff_three_way")
  self._filler_ns = vim.api.nvim_create_namespace("gitlad_diff_filler_triple")
  self._editable = buf_opts.editable or false

  -- Create left scratch buffer (always read-only)
  self.left_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self.left_bufnr].buftype = "nofile"
  vim.bo[self.left_bufnr].bufhidden = "wipe"
  vim.bo[self.left_bufnr].swapfile = false
  vim.bo[self.left_bufnr].modifiable = false

  -- Create mid buffer (INDEX — editable in three_way mode)
  self.mid_bufnr = vim.api.nvim_create_buf(false, true)
  if self._editable then
    vim.bo[self.mid_bufnr].buftype = "acwrite"
    vim.bo[self.mid_bufnr].swapfile = false
    vim.bo[self.mid_bufnr].modifiable = true
  else
    vim.bo[self.mid_bufnr].buftype = "nofile"
    vim.bo[self.mid_bufnr].bufhidden = "wipe"
    vim.bo[self.mid_bufnr].swapfile = false
    vim.bo[self.mid_bufnr].modifiable = false
  end

  -- Create right buffer (WORKTREE — editable in three_way mode)
  self.right_bufnr = vim.api.nvim_create_buf(false, true)
  if self._editable then
    vim.bo[self.right_bufnr].buftype = "acwrite"
    vim.bo[self.right_bufnr].swapfile = false
    vim.bo[self.right_bufnr].modifiable = true
  else
    vim.bo[self.right_bufnr].buftype = "nofile"
    vim.bo[self.right_bufnr].bufhidden = "wipe"
    vim.bo[self.right_bufnr].swapfile = false
    vim.bo[self.right_bufnr].modifiable = false
  end

  -- Assign buffers to windows
  vim.api.nvim_win_set_buf(left_winnr, self.left_bufnr)
  vim.api.nvim_win_set_buf(mid_winnr, self.mid_bufnr)
  vim.api.nvim_win_set_buf(right_winnr, self.right_bufnr)

  -- Configure window options for all three windows
  for _, winnr in ipairs({ left_winnr, mid_winnr, right_winnr }) do
    local win_opts = { win = winnr, scope = "local" }
    vim.api.nvim_set_option_value("scrollbind", true, win_opts)
    vim.api.nvim_set_option_value("cursorbind", true, win_opts)
    vim.api.nvim_set_option_value("wrap", false, win_opts)
    vim.api.nvim_set_option_value("number", true, win_opts)
    vim.api.nvim_set_option_value("numberwidth", 5, win_opts)
    vim.api.nvim_set_option_value(
      "statuscolumn",
      '%#GitladDiffLineNr#%{v:lua.require("gitlad.ui.views.diff.gutter").render()}',
      win_opts
    )
    vim.api.nvim_set_option_value("signcolumn", "no", win_opts)
    vim.api.nvim_set_option_value("foldcolumn", "0", win_opts)
    vim.api.nvim_set_option_value("foldmethod", "manual", win_opts)
    vim.api.nvim_set_option_value("foldenable", false, win_opts)
  end

  return self
end

--- Replace filler-line content with tilde characters.
---@param left_lines string[]
---@param mid_lines string[]
---@param right_lines string[]
---@param line_map ThreeWayLineInfo[]
function M._apply_filler_content(left_lines, mid_lines, right_lines, line_map)
  for i, info in ipairs(line_map) do
    if info.left_type == "filler" then
      left_lines[i] = "~"
    end
    if info.mid_type == "filler" then
      mid_lines[i] = "~"
    end
    if info.right_type == "filler" then
      right_lines[i] = "~"
    end
  end
end

--- Set the content of all three buffers from aligned 3-way data.
---@param aligned ThreeWayAlignedContent Aligned content from three_way.align_three_way()
---@param file_path string File path for filetype detection
function DiffBufferTriple:set_content(aligned, file_path)
  self.line_map = aligned.line_map
  self.left_lines = aligned.left_lines
  self.mid_lines = aligned.mid_lines
  self.right_lines = aligned.right_lines
  self.file_path = file_path

  -- Replace filler lines with ~ characters
  M._apply_filler_content(self.left_lines, self.mid_lines, self.right_lines, self.line_map)

  -- Unlock all buffers
  vim.bo[self.left_bufnr].modifiable = true
  vim.bo[self.mid_bufnr].modifiable = true
  vim.bo[self.right_bufnr].modifiable = true

  -- Set lines in all buffers
  vim.api.nvim_buf_set_lines(self.left_bufnr, 0, -1, false, self.left_lines)
  vim.api.nvim_buf_set_lines(self.mid_bufnr, 0, -1, false, self.mid_lines)
  vim.api.nvim_buf_set_lines(self.right_bufnr, 0, -1, false, self.right_lines)

  -- Set filetype from extension for treesitter highlighting
  local ft = vim.filetype.match({ filename = file_path }) or ""
  vim.bo[self.left_bufnr].filetype = ft
  vim.bo[self.mid_bufnr].filetype = ft
  vim.bo[self.right_bufnr].filetype = ft

  -- Apply diff highlights
  self:apply_diff_highlights()

  -- Populate gutter line numbers for statuscolumn
  local left_linenos = {}
  local mid_linenos = {}
  local right_linenos = {}
  for i, info in ipairs(self.line_map) do
    left_linenos[i] = info.left_lineno
    mid_linenos[i] = info.mid_lineno
    right_linenos[i] = info.right_lineno
  end
  gutter.set(self.left_bufnr, left_linenos)
  gutter.set(self.mid_bufnr, mid_linenos)
  gutter.set(self.right_bufnr, right_linenos)

  -- Re-lock left buffer (always read-only)
  vim.bo[self.left_bufnr].modifiable = false

  if self._editable then
    -- Track filler lines with extmarks on mid and right buffers
    vim.api.nvim_buf_clear_namespace(self.mid_bufnr, self._filler_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(self.right_bufnr, self._filler_ns, 0, -1)
    for i, info in ipairs(self.line_map) do
      if info.mid_type == "filler" then
        vim.api.nvim_buf_set_extmark(self.mid_bufnr, self._filler_ns, i - 1, 0, {})
      end
      if info.right_type == "filler" then
        vim.api.nvim_buf_set_extmark(self.right_bufnr, self._filler_ns, i - 1, 0, {})
      end
    end

    -- Set buffer names for acwrite
    vim.api.nvim_buf_set_name(self.mid_bufnr, "gitlad://diff/index/" .. file_path)
    vim.api.nvim_buf_set_name(self.right_bufnr, "gitlad://diff/worktree/" .. file_path)

    -- Mark as unmodified after loading content
    vim.bo[self.mid_bufnr].modified = false
    vim.bo[self.right_bufnr].modified = false
  else
    -- Re-lock mid and right buffers
    vim.bo[self.mid_bufnr].modifiable = false
    vim.bo[self.right_bufnr].modifiable = false
  end

  -- Sync scroll positions
  vim.cmd("syncbind")
end

--- Apply line-level highlights for all three panes.
--- Left↔mid shows staged changes, mid↔right shows unstaged changes.
--- Word-level inline diff computed for change pairs independently.
--- Line numbers are handled by gutter.lua via statuscolumn.
function DiffBufferTriple:apply_diff_highlights()
  local inline = require("gitlad.ui.views.diff.inline")

  -- Clear existing extmarks in all buffers
  vim.api.nvim_buf_clear_namespace(self.left_bufnr, self._ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.mid_bufnr, self._ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.right_bufnr, self._ns, 0, -1)

  for i, info in ipairs(self.line_map) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Left side highlights
    local left_hl = M._hl_for_type.left[info.left_type]
    if left_hl then
      vim.api.nvim_buf_set_extmark(self.left_bufnr, self._ns, line_idx, 0, {
        line_hl_group = left_hl,
      })
    end

    -- Mid side highlights
    local mid_hl = M._hl_for_type.mid[info.mid_type]
    if mid_hl then
      vim.api.nvim_buf_set_extmark(self.mid_bufnr, self._ns, line_idx, 0, {
        line_hl_group = mid_hl,
      })
    end

    -- Right side highlights
    local right_hl = M._hl_for_type.right[info.right_type]
    if right_hl then
      vim.api.nvim_buf_set_extmark(self.right_bufnr, self._ns, line_idx, 0, {
        line_hl_group = right_hl,
      })
    end

    -- Word-level inline diff: left↔mid (staged changes)
    if info.left_type == "change" and info.mid_type == "change" then
      local left_line = self.left_lines[i] or ""
      local mid_line = self.mid_lines[i] or ""
      local result = inline.compute_inline_diff(left_line, mid_line)

      for _, range in ipairs(result.old_ranges) do
        vim.api.nvim_buf_set_extmark(self.left_bufnr, self._ns, line_idx, range.col_start, {
          end_col = range.col_end,
          hl_group = "GitladDiffDeleteInline",
          priority = 200,
        })
      end
      for _, range in ipairs(result.new_ranges) do
        vim.api.nvim_buf_set_extmark(self.mid_bufnr, self._ns, line_idx, range.col_start, {
          end_col = range.col_end,
          hl_group = "GitladDiffAddInline",
          priority = 200,
        })
      end
    end

    -- Word-level inline diff: mid↔right (unstaged changes)
    if info.mid_type == "change" and info.right_type == "change" then
      local mid_line = self.mid_lines[i] or ""
      local right_line = self.right_lines[i] or ""
      local result = inline.compute_inline_diff(mid_line, right_line)

      for _, range in ipairs(result.old_ranges) do
        -- Don't re-highlight mid if already highlighted from left↔mid
        -- Only add if mid wasn't already a change with left
        if info.left_type ~= "change" then
          vim.api.nvim_buf_set_extmark(self.mid_bufnr, self._ns, line_idx, range.col_start, {
            end_col = range.col_end,
            hl_group = "GitladDiffDeleteInline",
            priority = 200,
          })
        end
      end
      for _, range in ipairs(result.new_ranges) do
        vim.api.nvim_buf_set_extmark(self.right_bufnr, self._ns, line_idx, range.col_start, {
          end_col = range.col_end,
          hl_group = "GitladDiffAddInline",
          priority = 200,
        })
      end
    end
  end
end

--- Apply folds to all three windows to hide large context regions between changes.
--- Uses three_way.compute_fold_ranges() to determine which regions to fold.
---@param line_map ThreeWayLineInfo[] Line metadata from alignment
---@param context_lines? number Lines of context around changes (default 3)
function DiffBufferTriple:apply_folds(line_map, context_lines)
  local three_way = require("gitlad.ui.views.diff.three_way")
  local fold_ranges = three_way.compute_fold_ranges(line_map, context_lines)

  if #fold_ranges == 0 then
    return
  end

  -- Apply folds in all three windows
  for _, winnr in ipairs({ self.left_winnr, self.mid_winnr, self.right_winnr }) do
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_call(winnr, function()
        -- Set foldtext before creating folds
        vim.wo[winnr].foldtext = 'v:lua.require("gitlad.ui.views.diff.gutter").foldtext()'
        vim.wo[winnr].foldenable = true
        -- Clear existing folds
        vim.cmd("normal! zE")
        -- Create folds for each range
        for _, range in ipairs(fold_ranges) do
          vim.cmd(range[1] .. "," .. range[2] .. "fold")
        end
      end)
    end
  end
end

--- Get real (non-filler) lines from a buffer, stripping filler-extmarked lines.
--- Only works for editable buffers that have filler extmarks set.
---@param bufnr number Buffer number to extract lines from
---@return string[] lines Real content lines with fillers removed
function DiffBufferTriple:get_real_lines(bufnr)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not self._editable then
    return all_lines
  end

  -- Get all filler extmark positions
  local filler_marks = vim.api.nvim_buf_get_extmarks(bufnr, self._filler_ns, 0, -1, {})
  local filler_set = {}
  for _, mark in ipairs(filler_marks) do
    filler_set[mark[2]] = true -- mark[2] is the 0-indexed line number
  end

  -- Filter out filler lines
  local real = {}
  for i, line in ipairs(all_lines) do
    if not filler_set[i - 1] then
      table.insert(real, line)
    end
  end
  return real
end

--- Check if any editable buffer (mid or right) has unsaved changes.
---@return boolean
function DiffBufferTriple:has_unsaved_changes()
  if not self._editable then
    return false
  end
  if
    self.mid_bufnr
    and vim.api.nvim_buf_is_valid(self.mid_bufnr)
    and vim.bo[self.mid_bufnr].modified
  then
    return true
  end
  if
    self.right_bufnr
    and vim.api.nvim_buf_is_valid(self.right_bufnr)
    and vim.bo[self.right_bufnr].modified
  then
    return true
  end
  return false
end

--- Get all buffer numbers as a list.
---@return number[] buffers List of buffer numbers
function DiffBufferTriple:get_buffers()
  return { self.left_bufnr, self.mid_bufnr, self.right_bufnr }
end

--- Clean up buffers. Clears gutter data and deletes all three buffers if still valid.
function DiffBufferTriple:destroy()
  for _, bufnr in ipairs({ self.left_bufnr, self.mid_bufnr, self.right_bufnr }) do
    if bufnr then
      gutter.clear(bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end
  self.left_bufnr = nil
  self.mid_bufnr = nil
  self.right_bufnr = nil
end

return M
