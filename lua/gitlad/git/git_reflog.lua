---@mod gitlad.git.git_reflog Reflog operations
---@brief [[
--- Reflog-related git operations.
--- Shows history of when branch tips and HEAD changed.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")

-- Separator for reflog format (ASCII record separator)
local REFLOG_SEP = "\30" -- %x1E

--- Get reflog format string for parsing
---@return string
local function get_reflog_format_string()
  -- Format: hash|||author|||selector|||subject
  return "%h" .. REFLOG_SEP .. "%aN" .. REFLOG_SEP .. "%gd" .. REFLOG_SEP .. "%gs"
end

--- Get reflog entries for a given ref
---@param ref string Git ref (e.g., "HEAD", "main", branch name)
---@param opts? GitCommandOptions
---@param callback fun(entries: ReflogEntry[]|nil, err: string|nil)
function M.reflog(ref, opts, callback)
  local format = get_reflog_format_string()
  local reflog_args = {
    "reflog",
    "show",
    "--format=" .. format,
    "-n",
    "256",
    ref,
    "--",
  }

  cli.run_async(reflog_args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_reflog(result.stdout), nil)
  end)
end

return M
