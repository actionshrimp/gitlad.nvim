---@mod gitlad.utils.path Path manipulation utilities
---@brief [[
--- Utilities for path formatting, particularly for rename display.
---@brief ]]

local M = {}

--- Split a path into components
---@param path string
---@return string[]
local function split_path(path)
  local components = {}
  for component in path:gmatch("[^/]+") do
    table.insert(components, component)
  end
  return components
end

--- Join path components back into a path string
---@param components string[]
---@param start_idx number? Starting index (default 1)
---@param end_idx number? Ending index (default #components)
---@return string
local function join_path(components, start_idx, end_idx)
  start_idx = start_idx or 1
  end_idx = end_idx or #components
  if start_idx > end_idx then
    return ""
  end
  local result = {}
  for i = start_idx, end_idx do
    table.insert(result, components[i])
  end
  return table.concat(result, "/")
end

--- Format a rename pair in Git's compact diffstat style
--- Examples:
---   old.txt, new.txt -> {old.txt => new.txt}
---   dir/old.txt, dir/new.txt -> dir/{old.txt => new.txt}
---   a/b/file.txt, a/c/file.txt -> a/{b => c}/file.txt
---   old/path/file.txt, new/path/file.txt -> {old => new}/path/file.txt
---@param orig string Original path
---@param new string New path
---@return string Formatted compact path
function M.format_rename(orig, new)
  if not orig or not new then
    return new or orig or ""
  end

  -- If paths are identical, just return the path
  if orig == new then
    return new
  end

  local orig_parts = split_path(orig)
  local new_parts = split_path(new)

  -- Find common prefix length (matching leading components)
  local prefix_len = 0
  local min_len = math.min(#orig_parts, #new_parts)
  for i = 1, min_len do
    if orig_parts[i] == new_parts[i] then
      prefix_len = i
    else
      break
    end
  end

  -- Find common suffix length (matching trailing components)
  -- But don't overlap with prefix
  local suffix_len = 0
  local max_suffix = math.min(#orig_parts - prefix_len, #new_parts - prefix_len)
  for i = 1, max_suffix do
    local orig_idx = #orig_parts - i + 1
    local new_idx = #new_parts - i + 1
    if orig_parts[orig_idx] == new_parts[new_idx] then
      suffix_len = i
    else
      break
    end
  end

  -- Build the result
  local prefix = join_path(orig_parts, 1, prefix_len)
  local suffix = join_path(orig_parts, #orig_parts - suffix_len + 1, #orig_parts)

  -- The differing parts
  local orig_diff = join_path(orig_parts, prefix_len + 1, #orig_parts - suffix_len)
  local new_diff = join_path(new_parts, prefix_len + 1, #new_parts - suffix_len)

  -- Build formatted string
  local result = ""
  if prefix ~= "" then
    result = prefix .. "/"
  end
  result = result .. "{" .. orig_diff .. " => " .. new_diff .. "}"
  if suffix ~= "" then
    result = result .. "/" .. suffix
  end

  return result
end

return M
