---@mod gitlad.state.expansion.scope Scope resolution for expansion operations
---@brief [[
--- Pure functions for determining the scope of expansion operations
--- based on cursor position and buffer context.
---@brief ]]

local M = {}

---@alias ScopeType "global"|"section"|"file"|"hunk"

---@class Scope
---@field type ScopeType What kind of scope this is
---@field section_key string|nil Section key if type is "section", "file", or "hunk"
---@field file_key string|nil "section:path" key if type is "file" or "hunk"
---@field hunk_index number|nil Hunk index if type is "hunk"

--- Create a global scope
---@return Scope
function M.global()
  return { type = "global" }
end

--- Create a section scope
---@param section_key string Section name
---@return Scope
function M.section(section_key)
  return {
    type = "section",
    section_key = section_key,
  }
end

--- Create a file scope
---@param section_key string Section name
---@param file_key string "section:path" key
---@return Scope
function M.file(section_key, file_key)
  return {
    type = "file",
    section_key = section_key,
    file_key = file_key,
  }
end

--- Create a hunk scope
---@param section_key string Section name
---@param file_key string "section:path" key
---@param hunk_index number Hunk index
---@return Scope
function M.hunk(section_key, file_key, hunk_index)
  return {
    type = "hunk",
    section_key = section_key,
    file_key = file_key,
    hunk_index = hunk_index,
  }
end

---@class LineInfo
---@field type "file"|"commit"|"stash"|"submodule"
---@field path string|nil File path (for file type)
---@field section string|nil Section name
---@field hunk_index number|nil Hunk index if on diff line
---@field is_hunk_header boolean|nil True if on @@ line

---@class SectionInfo
---@field name string Section display name
---@field section string Section key

--- Resolve scope from cursor position and buffer context
--- This is a pure function that determines what scope applies based on where the cursor is.
---@param line number Current cursor line (1-indexed)
---@param line_map table<number, LineInfo> Map of line numbers to line info
---@param section_lines table<number, SectionInfo> Map of line numbers to section headers
---@return Scope
function M.resolve(line, line_map, section_lines)
  -- Check if we're on a section header
  local section_info = section_lines[line]
  if section_info then
    return M.section(section_info.section)
  end

  -- Check if we're on a file/diff line
  local line_info = line_map[line]
  if line_info and line_info.type == "file" then
    local section_key = line_info.section
    local file_key = section_key .. ":" .. line_info.path

    -- If on a hunk header, scope is the hunk
    if line_info.is_hunk_header and line_info.hunk_index then
      return M.hunk(section_key, file_key, line_info.hunk_index)
    end

    -- Otherwise scope is the file
    return M.file(section_key, file_key)
  end

  -- Default to global scope
  return M.global()
end

--- Find the parent section for a given line
--- Used when we need to apply an operation to the parent section instead of the item
---@param line number Current cursor line
---@param section_lines table<number, SectionInfo> Map of line numbers to section headers
---@return string|nil section_key The section key, or nil if not found
---@return number|nil section_line The line number of the section header
function M.find_parent_section(line, section_lines)
  local best_section = nil
  local best_line = nil

  for section_line, section_info in pairs(section_lines) do
    if section_line <= line and (best_line == nil or section_line > best_line) then
      best_section = section_info.section
      best_line = section_line
    end
  end

  return best_section, best_line
end

return M
