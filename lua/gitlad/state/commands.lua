---@mod gitlad.state.commands State command definitions
---@brief [[
--- Elm Architecture-style commands for state transitions.
--- Commands are data structures that describe what should happen to the state.
--- They can be generated from user actions or from git output.
---@brief ]]

local M = {}

---@alias StatusCommandType
---| "stage_file"      -- Move file to staged
---| "unstage_file"    -- Move file to unstaged
---| "refresh"         -- Full replacement from git status
---| "stage_all"       -- Stage all unstaged + untracked
---| "unstage_all"     -- Unstage all staged
---| "remove_file"     -- Remove file from status (after discard)

---@class StatusCommand
---@field type StatusCommandType
---@field path? string File path (for single-file operations)
---@field from_section? "staged"|"unstaged"|"untracked" Source section
---@field status? GitStatusResult Full status (for refresh command)

--- Create a stage_file command
---@param path string File path to stage
---@param from_section "unstaged"|"untracked" Which section the file is in
---@return StatusCommand
function M.stage_file(path, from_section)
  return {
    type = "stage_file",
    path = path,
    from_section = from_section,
  }
end

--- Create an unstage_file command
---@param path string File path to unstage
---@return StatusCommand
function M.unstage_file(path)
  return {
    type = "unstage_file",
    path = path,
    from_section = "staged",
  }
end

--- Create a refresh command (full status replacement)
---@param status GitStatusResult New status from git
---@return StatusCommand
function M.refresh(status)
  return {
    type = "refresh",
    status = status,
  }
end

--- Create a stage_all command
---@return StatusCommand
function M.stage_all()
  return { type = "stage_all" }
end

--- Create an unstage_all command
---@return StatusCommand
function M.unstage_all()
  return { type = "unstage_all" }
end

--- Create a remove_file command (for after discard)
---@param path string File path to remove
---@param from_section "unstaged"|"untracked" Which section the file is in
---@return StatusCommand
function M.remove_file(path, from_section)
  return {
    type = "remove_file",
    path = path,
    from_section = from_section,
  }
end

return M
