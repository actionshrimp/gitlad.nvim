---@mod gitlad.state.expansion.reducer Pure expansion state reducer
---@brief [[
--- Elm Architecture-style reducer for expansion state transitions.
--- apply(state, cmd) -> new_state is a pure function with no side effects.
---@brief ]]

local M = {}

---@class FileExpansion
---@field expanded boolean|"headers" Expansion state: false=collapsed, "headers"=@@ only, true=full
---@field hunks table<number, boolean>|nil Per-hunk expansion state (when in headers mode)
---@field remembered table<number, boolean>|nil Saved hunk state for restoration

---@class SectionExpansion
---@field collapsed boolean Whether the section is collapsed
---@field remembered_files table<string, FileExpansion>|nil Saved file states for restoration

---@class ExpansionState
---@field visibility_level number Global visibility level (1-4, default 2)
---@field files table<string, FileExpansion> Map of "section:path" to file expansion state
---@field sections table<string, SectionExpansion> Map of section key to section expansion state
---@field commits table<string, boolean> Map of commit hash to expanded state

--- Create a new empty expansion state
---@param visibility_level? number Initial visibility level (default 2)
---@return ExpansionState
function M.new(visibility_level)
  return {
    visibility_level = visibility_level or 2,
    files = {},
    sections = {},
    commits = {},
  }
end

--- Deep copy an expansion state for immutability
---@param state ExpansionState
---@return ExpansionState
local function copy_state(state)
  return {
    visibility_level = state.visibility_level,
    files = vim.deepcopy(state.files),
    sections = vim.deepcopy(state.sections),
    commits = vim.deepcopy(state.commits),
  }
end

--- Apply a command to expansion state, returning new state (PURE FUNCTION)
---@param state ExpansionState
---@param cmd ExpansionCommand
---@return ExpansionState
function M.apply(state, cmd)
  if cmd.type == "reset" then
    return M.new(state.visibility_level)
  end

  -- Create a copy for immutability
  local new_state = copy_state(state)

  if cmd.type == "toggle_file" then
    return M._apply_toggle_file(new_state, cmd.file_key)
  elseif cmd.type == "toggle_section" then
    return M._apply_toggle_section(new_state, cmd.section_key)
  elseif cmd.type == "toggle_hunk" then
    return M._apply_toggle_hunk(new_state, cmd.file_key, cmd.hunk_index)
  elseif cmd.type == "set_file_expansion" then
    return M._apply_set_file_expansion(new_state, cmd.file_key, cmd.value)
  elseif cmd.type == "set_visibility_level" then
    return M._apply_set_visibility_level(new_state, cmd.level, cmd.scope)
  elseif cmd.type == "toggle_all_sections" then
    return M._apply_toggle_all_sections(new_state, cmd.sections, cmd.all_collapsed)
  end

  return new_state
end

--- Apply toggle_file command
---@param state ExpansionState (already copied)
---@param file_key string
---@return ExpansionState
function M._apply_toggle_file(state, file_key)
  -- TODO: Implement in Step 2
  return state
end

--- Apply toggle_section command
---@param state ExpansionState (already copied)
---@param section_key string
---@return ExpansionState
function M._apply_toggle_section(state, section_key)
  -- TODO: Implement in Step 2
  return state
end

--- Apply toggle_hunk command
---@param state ExpansionState (already copied)
---@param file_key string
---@param hunk_index number
---@return ExpansionState
function M._apply_toggle_hunk(state, file_key, hunk_index)
  -- TODO: Implement in Step 2
  return state
end

--- Apply set_file_expansion command
---@param state ExpansionState (already copied)
---@param file_key string
---@param value FileExpansionValue
---@return ExpansionState
function M._apply_set_file_expansion(state, file_key, value)
  -- TODO: Implement in Step 3
  return state
end

--- Apply set_visibility_level command
---@param state ExpansionState (already copied)
---@param level number
---@param scope Scope
---@return ExpansionState
function M._apply_set_visibility_level(state, level, scope)
  -- TODO: Implement in Step 3
  return state
end

--- Apply toggle_all_sections command
---@param state ExpansionState (already copied)
---@param sections string[]
---@param all_collapsed boolean
---@return ExpansionState
function M._apply_toggle_all_sections(state, sections, all_collapsed)
  -- TODO: Implement in Step 6
  return state
end

--- Helper: Get file expansion state, returning default if not set
---@param state ExpansionState
---@param file_key string
---@return FileExpansion
function M.get_file(state, file_key)
  return state.files[file_key] or { expanded = false }
end

--- Helper: Get section expansion state, returning default if not set
---@param state ExpansionState
---@param section_key string
---@return SectionExpansion
function M.get_section(state, section_key)
  return state.sections[section_key] or { collapsed = false }
end

--- Helper: Check if a file is expanded (either fully or in headers mode)
---@param state ExpansionState
---@param file_key string
---@return boolean
function M.is_file_expanded(state, file_key)
  local file = M.get_file(state, file_key)
  return file.expanded == true or file.expanded == "headers"
end

--- Helper: Check if a section is collapsed
---@param state ExpansionState
---@param section_key string
---@return boolean
function M.is_section_collapsed(state, section_key)
  local section = M.get_section(state, section_key)
  return section.collapsed == true
end

return M
