---@mod gitlad.commands Command dispatcher
local M = {}

local subcommands = {
  status = function()
    require("gitlad.ui.views.status").open()
  end,
  -- Future commands:
  -- log = function() ... end,
  -- branch = function() ... end,
  -- stash = function() ... end,
}

--- Execute a gitlad command
---@param args string Command arguments
function M.execute(args)
  local cmd = args and args:match("^%s*(%S+)") or "status"

  local handler = subcommands[cmd]
  if handler then
    handler()
  else
    -- Default to status if unknown command
    subcommands.status()
  end
end

--- Complete command arguments
---@param arg_lead string Current argument being typed
---@return string[]
function M.complete(arg_lead)
  local matches = {}
  for name, _ in pairs(subcommands) do
    if name:find("^" .. vim.pesc(arg_lead)) then
      table.insert(matches, name)
    end
  end
  table.sort(matches)
  return matches
end

return M
