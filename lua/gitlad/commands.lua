---@mod gitlad.commands Command dispatcher
local M = {}

local subcommands = {
  status = function()
    -- Always force refresh when user explicitly runs :Gitlad command
    require("gitlad.ui.views.status").open(nil, { force_refresh = true })
  end,
  blame = function()
    -- Blame the current file at the cursor line
    local file = vim.fn.expand("%:.")
    if file == "" then
      vim.notify("[gitlad] No file to blame", vim.log.levels.WARN)
      return
    end
    local state = require("gitlad.state")
    local repo_state = state.get()
    if not repo_state then
      vim.notify("[gitlad] Not in a git repository", vim.log.levels.WARN)
      return
    end
    local blame_view = require("gitlad.ui.views.blame")
    blame_view.open_file(repo_state, file)
  end,
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
