---@mod gitlad.ui.views.diff.buffer_triple Diff buffer triple for 3-pane display
---@brief [[
--- Manages three synchronized scratch buffers for 3-way diff display.
--- Left buffer shows HEAD, middle shows INDEX, right shows WORKTREE.
--- All three windows are scrollbound and cursorbind for synchronized navigation.
---@brief ]]

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

--- Format a line number for virtual text display (right-justified to 4 chars).
---@param lineno number|nil Line number or nil for filler lines
---@return string formatted Right-justified line number string
function M._format_lineno(lineno)
  if lineno == nil then
    return "    "
  end
  return string.format("%4d", lineno)
end

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
local DiffBufferTriple = {}
DiffBufferTriple.__index = DiffBufferTriple

--- Create a new DiffBufferTriple. Creates three scratch buffers and assigns them to
--- the given windows. Configures all windows for synchronized scrolling.
---@param left_winnr number Left window number
---@param mid_winnr number Middle window number
---@param right_winnr number Right window number
---@return DiffBufferTriple
function M.new(left_winnr, mid_winnr, right_winnr)
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

  -- Create three scratch buffers
  local buffers = {}
  for i = 1, 3 do
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    buffers[i] = bufnr
  end

  self.left_bufnr = buffers[1]
  self.mid_bufnr = buffers[2]
  self.right_bufnr = buffers[3]

  -- Assign buffers to windows
  vim.api.nvim_win_set_buf(left_winnr, self.left_bufnr)
  vim.api.nvim_win_set_buf(mid_winnr, self.mid_bufnr)
  vim.api.nvim_win_set_buf(right_winnr, self.right_bufnr)

  -- Configure window options for all three windows
  for _, winnr in ipairs({ left_winnr, mid_winnr, right_winnr }) do
    local opts = { win = winnr, scope = "local" }
    vim.api.nvim_set_option_value("scrollbind", true, opts)
    vim.api.nvim_set_option_value("cursorbind", true, opts)
    vim.api.nvim_set_option_value("wrap", false, opts)
    vim.api.nvim_set_option_value("number", false, opts)
    vim.api.nvim_set_option_value("signcolumn", "no", opts)
    vim.api.nvim_set_option_value("foldcolumn", "0", opts)
    vim.api.nvim_set_option_value("foldmethod", "manual", opts)
    vim.api.nvim_set_option_value("foldenable", false, opts)
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

  -- Re-lock all buffers
  vim.bo[self.left_bufnr].modifiable = false
  vim.bo[self.mid_bufnr].modifiable = false
  vim.bo[self.right_bufnr].modifiable = false

  -- Sync scroll positions
  vim.cmd("syncbind")
end

--- Apply line-level highlights for all three panes.
--- Left↔mid shows staged changes, mid↔right shows unstaged changes.
--- Word-level inline diff computed for change pairs independently.
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
    local left_extmark_opts = {
      virt_text = { { M._format_lineno(info.left_lineno), "GitladDiffLineNr" } },
      virt_text_pos = "inline",
    }
    if left_hl then
      left_extmark_opts.line_hl_group = left_hl
    end
    vim.api.nvim_buf_set_extmark(self.left_bufnr, self._ns, line_idx, 0, left_extmark_opts)

    -- Mid side highlights
    local mid_hl = M._hl_for_type.mid[info.mid_type]
    local mid_extmark_opts = {
      virt_text = { { M._format_lineno(info.mid_lineno), "GitladDiffLineNr" } },
      virt_text_pos = "inline",
    }
    if mid_hl then
      mid_extmark_opts.line_hl_group = mid_hl
    end
    vim.api.nvim_buf_set_extmark(self.mid_bufnr, self._ns, line_idx, 0, mid_extmark_opts)

    -- Right side highlights
    local right_hl = M._hl_for_type.right[info.right_type]
    local right_extmark_opts = {
      virt_text = { { M._format_lineno(info.right_lineno), "GitladDiffLineNr" } },
      virt_text_pos = "inline",
    }
    if right_hl then
      right_extmark_opts.line_hl_group = right_hl
    end
    vim.api.nvim_buf_set_extmark(self.right_bufnr, self._ns, line_idx, 0, right_extmark_opts)

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

--- Get all buffer numbers as a list.
---@return number[] buffers List of buffer numbers
function DiffBufferTriple:get_buffers()
  return { self.left_bufnr, self.mid_bufnr, self.right_bufnr }
end

--- Clean up buffers. Deletes all three buffers if they are still valid.
function DiffBufferTriple:destroy()
  for _, bufnr in ipairs({ self.left_bufnr, self.mid_bufnr, self.right_bufnr }) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  self.left_bufnr = nil
  self.mid_bufnr = nil
  self.right_bufnr = nil
end

return M
