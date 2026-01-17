---@mod gitlad.utils.errors Error handling utilities
---@brief [[
--- Centralized error handling patterns for git operations.
---@brief ]]

local M = {}

--- Format result for callback (success, err) pattern
---@param result {code: number, stderr: string[]}
---@return boolean success
---@return string|nil err
function M.result_to_callback(result)
  local success = result.code == 0
  local err = not success and table.concat(result.stderr, "\n") or nil
  return success, err
end

--- Notify an error with consistent formatting
---@param operation string Operation name (e.g., "Stage", "Commit")
---@param err string|nil Error message
function M.notify(operation, err)
  vim.notify(
    string.format("[gitlad] %s error: %s", operation, err or "unknown"),
    vim.log.levels.ERROR
  )
end

return M
