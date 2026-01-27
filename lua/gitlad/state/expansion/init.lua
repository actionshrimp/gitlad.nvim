---@mod gitlad.state.expansion Expansion state management
---@brief [[
--- Elm Architecture-style expansion state management.
--- Handles visibility of files, sections, hunks, and commits in the status buffer.
---
--- Usage:
---   local expansion = require("gitlad.state.expansion")
---   local state = expansion.reducer.new()
---   local cmd = expansion.commands.toggle_file("unstaged:file.txt")
---   local new_state = expansion.reducer.apply(state, cmd)
---@brief ]]

local M = {}

-- Re-export submodules
M.commands = require("gitlad.state.expansion.commands")
M.reducer = require("gitlad.state.expansion.reducer")
M.scope = require("gitlad.state.expansion.scope")

return M
