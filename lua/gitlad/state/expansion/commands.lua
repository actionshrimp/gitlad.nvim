---@mod gitlad.state.expansion.commands Expansion state command definitions
---@brief [[
--- Elm Architecture-style commands for expansion state transitions.
--- Commands are data structures that describe what should happen to expansion state.
---@brief ]]

local M = {}

---@alias ExpansionCommandType
---| "toggle_file"           -- Toggle file expansion (collapsed → expanded or expanded → collapsed)
---| "toggle_section"        -- Toggle section collapse
---| "toggle_hunk"           -- Toggle individual hunk within a file
---| "set_file_expansion"    -- Set file to specific expansion state
---| "set_visibility_level"  -- Set visibility level (1-4) for a scope
---| "toggle_all_sections"   -- Toggle all sections (Shift-Tab behavior)
---| "reset"                 -- Clear all expansion state

---@alias FileExpansionValue
---| false       -- Collapsed (no diff shown)
---| "headers"   -- Headers-only mode (show @@ lines, hunks collapsed)
---| true        -- Fully expanded (all hunks shown)

---@class ExpansionCommand
---@field type ExpansionCommandType
---@field file_key? string "section:path" key for file operations
---@field section_key? string Section key for section operations
---@field hunk_index? number Hunk index for hunk operations
---@field total_hunks? number Total number of hunks (for toggle_hunk when file is fully expanded)
---@field level? number Visibility level (1-4) for set_visibility_level
---@field scope? Scope Scope for scoped operations
---@field value? FileExpansionValue Explicit value for set_file_expansion
---@field sections? string[] List of section keys for toggle_all_sections
---@field all_collapsed? boolean Whether all sections are currently collapsed (for toggle_all_sections)

--- Create a toggle_file command
---@param file_key string "section:path" key
---@return ExpansionCommand
function M.toggle_file(file_key)
  return {
    type = "toggle_file",
    file_key = file_key,
  }
end

--- Create a toggle_section command
---@param section_key string Section name (e.g., "staged", "unstaged")
---@return ExpansionCommand
function M.toggle_section(section_key)
  return {
    type = "toggle_section",
    section_key = section_key,
  }
end

--- Create a toggle_hunk command
---@param file_key string "section:path" key
---@param hunk_index number Index of the hunk to toggle
---@param total_hunks? number Total number of hunks (needed when file is fully expanded)
---@return ExpansionCommand
function M.toggle_hunk(file_key, hunk_index, total_hunks)
  return {
    type = "toggle_hunk",
    file_key = file_key,
    hunk_index = hunk_index,
    total_hunks = total_hunks,
  }
end

--- Create a set_file_expansion command
---@param file_key string "section:path" key
---@param value FileExpansionValue Expansion state to set
---@return ExpansionCommand
function M.set_file_expansion(file_key, value)
  return {
    type = "set_file_expansion",
    file_key = file_key,
    value = value,
  }
end

--- Create a set_visibility_level command
---@param level number Visibility level (1-4)
---@param scope Scope Scope to apply the level to
---@return ExpansionCommand
function M.set_visibility_level(level, scope)
  return {
    type = "set_visibility_level",
    level = level,
    scope = scope,
  }
end

--- Create a toggle_all_sections command
---@param sections string[] List of section keys that exist
---@param all_collapsed boolean Whether all sections are currently collapsed
---@return ExpansionCommand
function M.toggle_all_sections(sections, all_collapsed)
  return {
    type = "toggle_all_sections",
    sections = sections,
    all_collapsed = all_collapsed,
  }
end

--- Create a reset command
---@return ExpansionCommand
function M.reset()
  return { type = "reset" }
end

return M
