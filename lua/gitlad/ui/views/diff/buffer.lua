---@mod gitlad.ui.views.diff.buffer Diff buffer pair for side-by-side display
---@brief [[
--- Manages two synchronized scratch buffers for side-by-side diff display.
--- Left buffer shows old content, right buffer shows new content.
--- Both windows are scrollbound and cursorbind for synchronized navigation.
---@brief ]]

local M = {}

--- Highlight group mapping: given a DiffLineType, return the highlight group name.
--- Exposed as `M._hl_for_type` for testing.
---@type table<string, table<string, string|nil>>
M._hl_for_type = {
  left = {
    context = nil, -- No highlight for context lines
    change = "GitladDiffChangeOld",
    delete = "GitladDiffDelete",
    add = nil, -- Left side doesn't show additions
    filler = "GitladDiffFiller",
  },
  right = {
    context = nil,
    change = "GitladDiffChangeNew",
    add = "GitladDiffAdd",
    delete = nil, -- Right side doesn't show deletions
    filler = "GitladDiffFiller",
  },
}

--- Format a line number for virtual text display (right-justified to 4 chars).
--- Returns a 4-char blank string for nil.
---@param lineno number|nil Line number or nil for filler lines
---@return string formatted Right-justified line number string
function M._format_lineno(lineno)
  if lineno == nil then
    return "    "
  end
  return string.format("%4d", lineno)
end

---@class DiffBufferOpts
---@field editable? boolean Make the right buffer editable (default false)

---@class DiffBufferPair
---@field left_bufnr number Left buffer number
---@field right_bufnr number Right buffer number
---@field left_winnr number Left window number
---@field right_winnr number Right window number
---@field left_lines string[] Left buffer line content (for inline diff)
---@field right_lines string[] Right buffer line content (for inline diff)
---@field line_map AlignedLineInfo[] Maps buffer line to metadata
---@field file_path string Current file path (for treesitter)
---@field _ns number Namespace for diff highlights
---@field _filler_ns number Namespace for filler line extmarks (editable mode)
---@field _editable boolean Whether right buffer is editable
local DiffBufferPair = {}
DiffBufferPair.__index = DiffBufferPair

--- Create a new DiffBufferPair. Creates two scratch buffers and assigns them to
--- the given windows. Configures both windows for synchronized scrolling.
---@param left_winnr number Left window number
---@param right_winnr number Right window number
---@param buf_opts? DiffBufferOpts Options (editable, etc.)
---@return DiffBufferPair
function M.new(left_winnr, right_winnr, buf_opts)
  buf_opts = buf_opts or {}
  local self = setmetatable({}, DiffBufferPair)

  self.left_winnr = left_winnr
  self.right_winnr = right_winnr
  self.left_lines = {}
  self.right_lines = {}
  self.line_map = {}
  self.file_path = ""
  self._ns = vim.api.nvim_create_namespace("gitlad_diff_view")
  self._filler_ns = vim.api.nvim_create_namespace("gitlad_diff_filler")
  self._editable = buf_opts.editable or false

  -- Create left scratch buffer (always read-only)
  self.left_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self.left_bufnr].buftype = "nofile"
  vim.bo[self.left_bufnr].bufhidden = "wipe"
  vim.bo[self.left_bufnr].swapfile = false
  vim.bo[self.left_bufnr].modifiable = false

  -- Create right buffer
  self.right_bufnr = vim.api.nvim_create_buf(false, true)
  if self._editable then
    -- Editable: use acwrite so we control the save operation
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
  vim.api.nvim_win_set_buf(right_winnr, self.right_bufnr)

  -- Configure window options for both windows
  for _, winnr in ipairs({ left_winnr, right_winnr }) do
    local win_opts = { win = winnr, scope = "local" }
    vim.api.nvim_set_option_value("scrollbind", true, win_opts)
    vim.api.nvim_set_option_value("cursorbind", true, win_opts)
    vim.api.nvim_set_option_value("wrap", false, win_opts)
    vim.api.nvim_set_option_value("number", false, win_opts)
    vim.api.nvim_set_option_value("signcolumn", "no", win_opts)
    vim.api.nvim_set_option_value("foldcolumn", "0", win_opts)
    vim.api.nvim_set_option_value("foldmethod", "manual", win_opts)
    vim.api.nvim_set_option_value("foldenable", false, win_opts)
  end

  return self
end

--- Replace filler-line content with tilde characters (like vim's empty-buffer lines).
--- Modifies left_lines/right_lines in place based on the line_map types.
---@param left_lines string[] Left buffer lines (modified in place)
---@param right_lines string[] Right buffer lines (modified in place)
---@param line_map AlignedLineInfo[] Line metadata
function M._apply_filler_content(left_lines, right_lines, line_map)
  for i, info in ipairs(line_map) do
    if info.left_type == "filler" then
      left_lines[i] = "~"
    end
    if info.right_type == "filler" then
      right_lines[i] = "~"
    end
  end
end

--- Set the content of both buffers from aligned side-by-side data.
--- Unlocks buffers, sets lines, applies filetype for treesitter,
--- applies diff highlights, and re-locks buffers.
---@param aligned AlignedContent Aligned content from content.align_sides()
---@param file_path string File path for filetype detection
function DiffBufferPair:set_content(aligned, file_path)
  self.line_map = aligned.line_map
  self.left_lines = aligned.left_lines
  self.right_lines = aligned.right_lines
  self.file_path = file_path

  -- Replace filler lines with ~ characters
  M._apply_filler_content(self.left_lines, self.right_lines, self.line_map)

  -- Unlock both buffers
  vim.bo[self.left_bufnr].modifiable = true
  vim.bo[self.right_bufnr].modifiable = true

  -- Set lines in both buffers
  vim.api.nvim_buf_set_lines(self.left_bufnr, 0, -1, false, self.left_lines)
  vim.api.nvim_buf_set_lines(self.right_bufnr, 0, -1, false, self.right_lines)

  -- Set filetype from extension for treesitter highlighting
  local ft = vim.filetype.match({ filename = file_path }) or ""
  vim.bo[self.left_bufnr].filetype = ft
  vim.bo[self.right_bufnr].filetype = ft

  -- Apply diff highlights
  self:apply_diff_highlights()

  -- Re-lock left buffer (always read-only)
  vim.bo[self.left_bufnr].modifiable = false

  if self._editable then
    -- Track filler lines with extmarks on the right buffer
    vim.api.nvim_buf_clear_namespace(self.right_bufnr, self._filler_ns, 0, -1)
    for i, info in ipairs(self.line_map) do
      if info.right_type == "filler" then
        vim.api.nvim_buf_set_extmark(self.right_bufnr, self._filler_ns, i - 1, 0, {})
      end
    end

    -- Set buffer name for acwrite
    vim.api.nvim_buf_set_name(self.right_bufnr, "gitlad://diff/" .. file_path)

    -- Mark as unmodified after loading content
    vim.bo[self.right_bufnr].modified = false
  else
    -- Re-lock right buffer
    vim.bo[self.right_bufnr].modifiable = false
  end

  -- Sync scroll positions
  vim.cmd("syncbind")
end

--- Apply line-level highlights based on the line_map.
--- Uses extmarks for line background highlights, line number virtual text,
--- and word-level inline diff highlights for change-type line pairs.
function DiffBufferPair:apply_diff_highlights()
  local inline = require("gitlad.ui.views.diff.inline")

  -- Clear existing extmarks in both buffers
  vim.api.nvim_buf_clear_namespace(self.left_bufnr, self._ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.right_bufnr, self._ns, 0, -1)

  for i, info in ipairs(self.line_map) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Left side highlights
    local left_hl = M._hl_for_type.left[info.left_type]
    local left_lineno_text = M._format_lineno(info.left_lineno)
    local left_extmark_opts = {
      virt_text = { { left_lineno_text, "GitladDiffLineNr" } },
      virt_text_pos = "inline",
    }
    if left_hl then
      left_extmark_opts.line_hl_group = left_hl
    end
    vim.api.nvim_buf_set_extmark(self.left_bufnr, self._ns, line_idx, 0, left_extmark_opts)

    -- Right side highlights
    local right_hl = M._hl_for_type.right[info.right_type]
    local right_lineno_text = M._format_lineno(info.right_lineno)
    local right_extmark_opts = {
      virt_text = { { right_lineno_text, "GitladDiffLineNr" } },
      virt_text_pos = "inline",
    }
    if right_hl then
      right_extmark_opts.line_hl_group = right_hl
    end
    vim.api.nvim_buf_set_extmark(self.right_bufnr, self._ns, line_idx, 0, right_extmark_opts)

    -- Word-level inline diff for change-type line pairs
    if info.left_type == "change" and info.right_type == "change" then
      local left_line = self.left_lines[i] or ""
      local right_line = self.right_lines[i] or ""
      local result = inline.compute_inline_diff(left_line, right_line)

      for _, range in ipairs(result.old_ranges) do
        vim.api.nvim_buf_set_extmark(self.left_bufnr, self._ns, line_idx, range.col_start, {
          end_col = range.col_end,
          hl_group = "GitladDiffDeleteInline",
          priority = 200,
        })
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

--- Get real (non-filler) lines from a buffer, stripping filler-extmarked lines.
--- Only works for editable buffers that have filler extmarks set.
---@param bufnr number Buffer number to extract lines from
---@return string[] lines Real content lines with fillers removed
function DiffBufferPair:get_real_lines(bufnr)
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

--- Check if the right buffer (or any editable buffer) has unsaved changes.
---@return boolean
function DiffBufferPair:has_unsaved_changes()
  if not self._editable then
    return false
  end
  if self.right_bufnr and vim.api.nvim_buf_is_valid(self.right_bufnr) then
    return vim.bo[self.right_bufnr].modified
  end
  return false
end

--- Clean up buffers. Deletes both buffers if they are still valid.
function DiffBufferPair:destroy()
  if self.left_bufnr and vim.api.nvim_buf_is_valid(self.left_bufnr) then
    vim.api.nvim_buf_delete(self.left_bufnr, { force = true })
  end
  if self.right_bufnr and vim.api.nvim_buf_is_valid(self.right_bufnr) then
    vim.api.nvim_buf_delete(self.right_bufnr, { force = true })
  end
  self.left_bufnr = nil
  self.right_bufnr = nil
end

return M
