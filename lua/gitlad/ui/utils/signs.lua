---@mod gitlad.ui.utils.signs Sign placement utilities
---@brief [[
--- Shared utility for placing expand/collapse signs in buffer views.
--- Used by status, log, and other expandable buffer views.
---@brief ]]

local M = {}

---@class SignLineInfo
---@field expanded boolean Whether this line's content is expanded

--- Place expand/collapse indicator signs in a buffer
---@param bufnr number Buffer number
---@param sign_lines table<number, SignLineInfo> Map of line numbers to sign info
---@param namespace number Namespace for the signs
function M.place_expand_signs(bufnr, sign_lines, namespace)
  -- Clear existing signs
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  -- Place signs for lines that have expand indicators
  for line_num, sign_info in pairs(sign_lines) do
    local sign_text = sign_info.expanded and "v" or ">"
    local sign_hl = "GitladExpandIndicator"

    vim.api.nvim_buf_set_extmark(bufnr, namespace, line_num - 1, 0, {
      sign_text = sign_text,
      sign_hl_group = sign_hl,
      priority = 10,
    })
  end
end

return M
