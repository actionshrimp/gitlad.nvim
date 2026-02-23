---@mod gitlad.ui.views.diff.gutter Diff gutter line numbers via statuscolumn
---@brief [[
--- Stores per-buffer line number lookup tables and exposes a render() function
--- for use in the `statuscolumn` window option. This replaces inline virtual text
--- line numbers, keeping the cursor out of the gutter area.
---@brief ]]

local M = {}

--- Per-buffer line number lookup: { [bufnr] = { [1-based-lnum] = original_lineno } }
---@type table<number, table<number, number>>
M._linenos = {}

--- Store line number data for a buffer.
---@param bufnr number Buffer number
---@param linenos table<number, number> Map of 1-based buffer line to original file line number
function M.set(bufnr, linenos)
  M._linenos[bufnr] = linenos
end

--- Clear line number data for a buffer.
---@param bufnr number Buffer number
function M.clear(bufnr)
  M._linenos[bufnr] = nil
end

--- Format a line number for statuscolumn display (right-justified to 4 chars + 1 space).
--- Returns 5-char blank string for nil (filler lines).
---@param lineno number|nil Line number or nil for filler lines
---@return string formatted 5-character formatted string
function M._format_lineno(lineno)
  if lineno == nil then
    return "     "
  end
  return string.format("%4d ", lineno)
end

--- Render function called by statuscolumn expression.
--- Reads vim.v.lnum and current buffer to look up the original line number.
---@return string formatted Formatted line number string for statuscolumn
function M.render()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.v.lnum
  local buf_linenos = M._linenos[bufnr]
  if buf_linenos then
    return M._format_lineno(buf_linenos[lnum])
  end
  return M._format_lineno(nil)
end

--- Foldtext function for diff view folds.
--- Displays a centered indicator showing how many unchanged lines are folded.
--- Leading spaces (5 chars) align with the statuscolumn gutter width.
---@return string
function M.foldtext()
  local count = vim.v.foldend - vim.v.foldstart + 1
  return string.format("     ···· %d unchanged lines ····", count)
end

return M
