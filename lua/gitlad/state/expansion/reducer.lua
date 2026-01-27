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
    return M._apply_toggle_hunk(new_state, cmd.file_key, cmd.hunk_index, cmd.total_hunks)
  elseif cmd.type == "set_file_expansion" then
    return M._apply_set_file_expansion(new_state, cmd.file_key, cmd.value)
  elseif cmd.type == "set_visibility_level" then
    return M._apply_set_visibility_level(
      new_state,
      cmd.level,
      cmd.scope,
      cmd.sections,
      cmd.file_keys,
      cmd.commit_hashes
    )
  elseif cmd.type == "toggle_all_sections" then
    return M._apply_toggle_all_sections(new_state, cmd.sections, cmd.all_collapsed)
  end

  return new_state
end

--- Apply toggle_file command
--- Toggles between expanded (true/headers) and collapsed (false)
--- When collapsing: saves current state to remembered for later restoration
--- When expanding: restores from remembered or defaults to true
---@param state ExpansionState (already copied)
---@param file_key string
---@return ExpansionState
function M._apply_toggle_file(state, file_key)
  local file = state.files[file_key] or { expanded = false }

  if file.expanded then
    -- Currently expanded -> collapse
    -- Save current state for restoration
    local new_file = {
      expanded = false,
      remembered = nil,
    }
    -- Save hunk state if we're in headers mode with per-hunk expansion
    if file.expanded == "headers" and file.hunks then
      new_file.remembered = vim.deepcopy(file.hunks)
    elseif file.expanded == true then
      -- Was fully expanded, remember that (nil means "was fully expanded")
      new_file.remembered = nil
    end
    state.files[file_key] = new_file
  else
    -- Currently collapsed -> expand
    -- Restore from remembered state or default to fully expanded
    local new_file = { expanded = true }
    if file.remembered then
      new_file.expanded = "headers"
      new_file.hunks = vim.deepcopy(file.remembered)
    end
    state.files[file_key] = new_file
  end

  return state
end

--- Apply toggle_section command
--- Toggles between collapsed (true) and expanded (false)
---@param state ExpansionState (already copied)
---@param section_key string
---@return ExpansionState
function M._apply_toggle_section(state, section_key)
  local section = state.sections[section_key] or { collapsed = false }

  state.sections[section_key] = {
    collapsed = not section.collapsed,
    remembered_files = section.remembered_files,
  }

  return state
end

--- Apply toggle_hunk command
--- Toggles a specific hunk's expansion when file is in headers mode
--- If file is fully expanded, transitions to headers mode with this hunk collapsed
---@param state ExpansionState (already copied)
---@param file_key string
---@param hunk_index number
---@param total_hunks? number Total number of hunks (needed when transitioning from fully expanded)
---@return ExpansionState
function M._apply_toggle_hunk(state, file_key, hunk_index, total_hunks)
  local file = state.files[file_key]
  if not file then
    return state
  end

  if file.expanded == "headers" then
    -- Already in headers mode: toggle the specific hunk
    local hunks = file.hunks or {}
    hunks[hunk_index] = not hunks[hunk_index]
    state.files[file_key] = {
      expanded = "headers",
      hunks = hunks,
      remembered = file.remembered,
    }
  elseif file.expanded == true and total_hunks then
    -- Fully expanded: transition to headers mode with this hunk collapsed
    local hunks = {}
    for i = 1, total_hunks do
      hunks[i] = (i ~= hunk_index) -- All expanded except this one
    end
    state.files[file_key] = {
      expanded = "headers",
      hunks = hunks,
      remembered = file.remembered,
    }
  end
  -- If file is collapsed or no total_hunks provided, do nothing

  return state
end

--- Apply set_file_expansion command
--- Directly sets a file's expansion state to a specific value
---@param state ExpansionState (already copied)
---@param file_key string
---@param value FileExpansionValue
---@return ExpansionState
function M._apply_set_file_expansion(state, file_key, value)
  local file = state.files[file_key] or {}

  if value == false then
    -- Collapsing: preserve remembered state from before
    state.files[file_key] = {
      expanded = false,
      remembered = file.remembered,
    }
  elseif value == "headers" then
    state.files[file_key] = {
      expanded = "headers",
      hunks = {}, -- No hunks expanded initially
      remembered = file.remembered,
    }
  else -- value == true
    state.files[file_key] = {
      expanded = true,
      remembered = file.remembered,
    }
  end

  return state
end

--- Apply set_visibility_level command
--- Applies a visibility level to the given scope
--- Level 1: Collapse sections, clear file/commit expansions
--- Level 2: Expand sections, clear file/commit expansions
--- Level 3: Expand sections, set files to headers mode
--- Level 4: Expand sections, fully expand files and commits
---@param state ExpansionState (already copied)
---@param level number (1-4)
---@param scope Scope
---@param sections? string[] Section keys to operate on
---@param file_keys? string[] File keys to operate on
---@param commit_hashes? string[] Commit hashes to operate on
---@return ExpansionState
function M._apply_set_visibility_level(state, level, scope, sections, file_keys, commit_hashes)
  level = math.max(1, math.min(4, level)) -- Clamp to 1-4
  state.visibility_level = level

  if scope.type == "global" then
    return M._apply_visibility_level_global(state, level, sections, file_keys, commit_hashes)
  elseif scope.type == "section" then
    return M._apply_visibility_level_section(
      state,
      level,
      scope.section_key,
      file_keys,
      commit_hashes
    )
  elseif scope.type == "file" then
    return M._apply_visibility_level_file(state, level, scope.file_key)
  end
  -- Hunk scope falls through to file
  if scope.type == "hunk" and scope.file_key then
    return M._apply_visibility_level_file(state, level, scope.file_key)
  end

  return state
end

--- Apply visibility level globally
---@param state ExpansionState (already copied)
---@param level number
---@param sections? string[]
---@param file_keys? string[]
---@param commit_hashes? string[]
---@return ExpansionState
function M._apply_visibility_level_global(state, level, sections, file_keys, commit_hashes)
  sections = sections or {}
  file_keys = file_keys or {}
  commit_hashes = commit_hashes or {}

  if level == 1 then
    -- Collapse all sections, clear all expansions
    for _, section_key in ipairs(sections) do
      state.sections[section_key] = {
        collapsed = true,
        remembered_files = state.sections[section_key]
          and state.sections[section_key].remembered_files,
      }
    end
    state.files = {}
    state.commits = {}
  elseif level == 2 then
    -- Expand all sections, clear file diffs and commit details
    for _, section_key in ipairs(sections) do
      state.sections[section_key] = {
        collapsed = false,
        remembered_files = state.sections[section_key]
          and state.sections[section_key].remembered_files,
      }
    end
    state.files = {}
    state.commits = {}
  elseif level == 3 then
    -- Expand all sections, set files to headers mode
    for _, section_key in ipairs(sections) do
      state.sections[section_key] = {
        collapsed = false,
        remembered_files = state.sections[section_key]
          and state.sections[section_key].remembered_files,
      }
    end
    for _, file_key in ipairs(file_keys) do
      local existing = state.files[file_key] or {}
      state.files[file_key] = {
        expanded = "headers",
        hunks = {},
        remembered = existing.remembered,
      }
    end
    state.commits = {}
  elseif level == 4 then
    -- Expand everything
    for _, section_key in ipairs(sections) do
      state.sections[section_key] = {
        collapsed = false,
        remembered_files = state.sections[section_key]
          and state.sections[section_key].remembered_files,
      }
    end
    for _, file_key in ipairs(file_keys) do
      local existing = state.files[file_key] or {}
      state.files[file_key] = {
        expanded = true,
        remembered = existing.remembered,
      }
    end
    for _, hash in ipairs(commit_hashes) do
      state.commits[hash] = true
    end
  end

  return state
end

--- Apply visibility level to a single section
---@param state ExpansionState (already copied)
---@param level number
---@param section_key string
---@param file_keys? string[]
---@param commit_hashes? string[]
---@return ExpansionState
function M._apply_visibility_level_section(state, level, section_key, file_keys, commit_hashes)
  file_keys = file_keys or {}
  commit_hashes = commit_hashes or {}

  if level == 1 then
    -- Collapse the section
    state.sections[section_key] = {
      collapsed = true,
      remembered_files = state.sections[section_key]
        and state.sections[section_key].remembered_files,
    }
    -- Clear file expansions for this section
    for _, file_key in ipairs(file_keys) do
      state.files[file_key] = nil
    end
    -- Clear commit expansions for this section
    for _, hash in ipairs(commit_hashes) do
      state.commits[hash] = nil
    end
  elseif level == 2 then
    -- Expand section, clear file diffs
    state.sections[section_key] = {
      collapsed = false,
      remembered_files = state.sections[section_key]
        and state.sections[section_key].remembered_files,
    }
    for _, file_key in ipairs(file_keys) do
      state.files[file_key] = nil
    end
    for _, hash in ipairs(commit_hashes) do
      state.commits[hash] = nil
    end
  elseif level == 3 then
    -- Expand section, set files to headers mode
    state.sections[section_key] = {
      collapsed = false,
      remembered_files = state.sections[section_key]
        and state.sections[section_key].remembered_files,
    }
    for _, file_key in ipairs(file_keys) do
      local existing = state.files[file_key] or {}
      state.files[file_key] = {
        expanded = "headers",
        hunks = {},
        remembered = existing.remembered,
      }
    end
  elseif level == 4 then
    -- Expand section and everything in it
    state.sections[section_key] = {
      collapsed = false,
      remembered_files = state.sections[section_key]
        and state.sections[section_key].remembered_files,
    }
    for _, file_key in ipairs(file_keys) do
      local existing = state.files[file_key] or {}
      state.files[file_key] = {
        expanded = true,
        remembered = existing.remembered,
      }
    end
    for _, hash in ipairs(commit_hashes) do
      state.commits[hash] = true
    end
  end

  return state
end

--- Apply visibility level to a single file
---@param state ExpansionState (already copied)
---@param level number
---@param file_key string
---@return ExpansionState
function M._apply_visibility_level_file(state, level, file_key)
  local existing = state.files[file_key] or {}

  if level == 1 or level == 2 then
    -- Collapse file diff
    state.files[file_key] = {
      expanded = false,
      remembered = existing.remembered,
    }
  elseif level == 3 then
    -- Headers mode
    state.files[file_key] = {
      expanded = "headers",
      hunks = {},
      remembered = existing.remembered,
    }
  elseif level == 4 then
    -- Fully expand
    state.files[file_key] = {
      expanded = true,
      remembered = existing.remembered,
    }
  end

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
