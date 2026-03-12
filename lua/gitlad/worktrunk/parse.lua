---@mod gitlad.worktrunk.parse Worktrunk JSON output parser
---@brief [[
--- Parses NDJSON output from `wt list --format=json`.
--- Each line is a separate JSON object (not a JSON array).
---@brief ]]

local M = {}

---@class WorktreeInfo
---@field branch string Branch name
---@field path string Absolute path to the worktree
---@field kind string "main" | "linked"
---@field working_tree { modified: integer, staged: integer, untracked: integer }|nil
---@field main { ahead: integer, behind: integer }|nil Ahead/behind relative to main/trunk branch
---@field remote { ahead: integer, behind: integer }|nil Ahead/behind relative to remote
---@field ci { status: string, stale: boolean }|nil CI status
---@field operation_state string|nil e.g. "conflicts"
---@field main_state string|nil e.g. "integrated", "empty"

--- Parse output of `wt list --format=json`
--- wt outputs one JSON object per line (NDJSON), not a JSON array
---@param output string[] Lines from wt list --format=json
---@return WorktreeInfo[]
function M.parse_list(output)
  local result = {}
  for _, line in ipairs(output) do
    if line and line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and decoded then
        table.insert(result, decoded)
      end
    end
  end
  return result
end

return M
