---@mod gitlad.worktrunk.parse Worktrunk JSON output parser
---@brief [[
--- Parses JSON output from `wt list --format=json`.
--- The wt CLI outputs a JSON array (not NDJSON) spanning multiple lines.
---@brief ]]

local M = {}

---@class WorktreeInfo
---@field branch string Branch name
---@field path string Absolute path to the worktree
---@field kind string "worktree" (all worktrees have this kind in wt output)
---@field is_main boolean Whether this is the main worktree
---@field is_current boolean Whether this is the currently active worktree
---@field working_tree { staged: boolean, modified: boolean, untracked: boolean }|nil
---@field main { ahead: integer, behind: integer }|nil Commits ahead/behind main branch
---@field remote { ahead: integer, behind: integer, name: string, branch: string }|nil
---@field main_state string|nil e.g. "is_main", "ahead", "integrated"
---@field operation_state string|nil e.g. "conflicts"

--- Parse output of `wt list --format=json`
--- wt outputs a JSON array spanning multiple lines.
--- Also accepts NDJSON (one JSON object per line) for compatibility.
---@param output string[] Lines from wt list --format=json
---@return WorktreeInfo[]
function M.parse_list(output)
  if not output or #output == 0 then
    return {}
  end

  -- Join all lines into a single string
  local json_str = table.concat(output, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  if json_str == "" then
    return {}
  end

  -- Try to parse as a JSON array first (actual wt output format)
  if vim.startswith(json_str, "[") then
    local ok, decoded = pcall(vim.json.decode, json_str)
    if ok and type(decoded) == "table" then
      return decoded
    end
    return {}
  end

  -- Fallback: try NDJSON (one JSON object per line)
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

--- Merge WorktreeInfo from wt list into WorktreeEntry list.
--- Matches by branch name and attaches wt data as a `.wt` field.
---@param worktrees WorktreeEntry[]
---@param infos WorktreeInfo[]
---@return WorktreeEntry[]
function M.merge(worktrees, infos)
  local by_branch = {}
  for _, info in ipairs(infos) do
    if info.branch then
      by_branch[info.branch] = info
    end
  end
  for _, entry in ipairs(worktrees) do
    if entry.branch then
      entry.wt = by_branch[entry.branch]
    end
  end
  return worktrees
end

return M
