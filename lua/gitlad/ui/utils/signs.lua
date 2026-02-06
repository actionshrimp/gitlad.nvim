---@mod gitlad.ui.utils.signs Sign placement utilities
---@brief [[
--- Shared utility for placing expand/collapse signs in buffer views.
--- Used by status, log, and other expandable buffer views.
---@brief ]]

local M = {}

---@class SignLineInfo
---@field expanded boolean? Whether this line's content is expanded
---@field sign_text string? Custom sign text (overrides expanded v/>)
---@field sign_hl string? Custom sign highlight group

--- Place expand/collapse indicator signs in a buffer
---@param bufnr number Buffer number
---@param sign_lines table<number, SignLineInfo> Map of line numbers to sign info
---@param namespace number Namespace for the signs
function M.place_expand_signs(bufnr, sign_lines, namespace)
  -- Clear existing signs
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  -- Place signs for lines that have expand indicators or custom signs
  for line_num, sign_info in pairs(sign_lines) do
    local sign_text, sign_hl
    if sign_info.sign_text then
      sign_text = sign_info.sign_text
      sign_hl = sign_info.sign_hl or "GitladExpandIndicator"
    else
      sign_text = sign_info.expanded and "v" or ">"
      sign_hl = "GitladExpandIndicator"
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, line_num - 1, 0, {
      sign_text = sign_text,
      sign_hl_group = sign_hl,
      priority = 10,
    })
  end
end

return M
