---@mod gitlad.ui.views.diff.tree Pure directory tree for diff panel file list
---@brief [[
--- Builds a directory tree from flat file pairs and flattens it back to a
--- display-order list with collapsed-dir support. No vim dependency.
---@brief ]]

local M = {}

-- =============================================================================
-- Type Definitions
-- =============================================================================

---@class DiffTreeNode
---@field name string Segment name
---@field path string Full path from root
---@field children table<string, DiffTreeNode> Child nodes keyed by name
---@field file_index number|nil For leaf nodes, index into file_pairs
---@field status string|nil For leaf nodes, file status (M/A/D/R/C)
---@field is_dir boolean

---@class DiffTreeEntry
---@field type "dir"|"file"
---@field name string Display name (flattened dir path or file basename)
---@field path string Full path (used as collapse key for dirs)
---@field depth number Nesting depth (0 = root level)
---@field file_index number|nil For "file" entries only
---@field status string|nil For "file" entries only (M/A/D/R/C)
---@field is_collapsed boolean|nil For "dir" entries only

-- =============================================================================
-- Internal Helpers
-- =============================================================================

--- Get sorted children of a node: directories first (alphabetical), then files (alphabetical)
---@param node DiffTreeNode
---@return DiffTreeNode[]
local function sorted_children(node)
  local dirs = {}
  local files = {}
  for _, child in pairs(node.children) do
    if child.is_dir then
      dirs[#dirs + 1] = child
    else
      files[#files + 1] = child
    end
  end
  table.sort(dirs, function(a, b)
    return a.name < b.name
  end)
  table.sort(files, function(a, b)
    return a.name < b.name
  end)
  local result = {}
  for _, d in ipairs(dirs) do
    result[#result + 1] = d
  end
  for _, f in ipairs(files) do
    result[#result + 1] = f
  end
  return result
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Build a tree from file pairs. Each file's path is split by "/" to create
--- intermediate directory nodes. Leaf nodes store file_index and status.
---@param file_pairs DiffFilePair[]
---@return DiffTreeNode root Virtual root node
function M.build_tree(file_pairs)
  local root = { name = "", path = "", children = {}, is_dir = true }

  for i, pair in ipairs(file_pairs) do
    local path = (pair.new_path ~= "" and pair.new_path) or pair.old_path

    -- Split path by "/"
    local parts = {}
    for part in path:gmatch("[^/]+") do
      parts[#parts + 1] = part
    end

    -- Create intermediate directories
    local current = root
    for j = 1, #parts - 1 do
      local dir_name = parts[j]
      if not current.children[dir_name] then
        current.children[dir_name] = {
          name = dir_name,
          path = table.concat(parts, "/", 1, j),
          children = {},
          is_dir = true,
        }
      end
      current = current.children[dir_name]
    end

    -- Add file leaf
    local file_name = parts[#parts]
    current.children[file_name] = {
      name = file_name,
      path = path,
      children = {},
      file_index = i,
      status = pair.status,
      is_dir = false,
    }
  end

  return root
end

--- Flatten a tree into a display-order list of entries.
--- Applies single-child directory flattening (a/b → "a/b") and respects collapsed state.
---@param root DiffTreeNode
---@param collapsed_dirs table<string, boolean>|nil Map of dir paths to collapsed state
---@return DiffTreeEntry[]
function M.flatten(root, collapsed_dirs)
  collapsed_dirs = collapsed_dirs or {}
  local entries = {}

  local function walk(node, depth)
    local children = sorted_children(node)
    for _, child in ipairs(children) do
      if child.is_dir then
        -- Single-child directory flattening: merge chains of single-dir children
        local display_name = child.name
        local current = child
        while true do
          local sub = sorted_children(current)
          if #sub == 1 and sub[1].is_dir then
            current = sub[1]
            display_name = display_name .. "/" .. current.name
          else
            break
          end
        end

        local is_collapsed = collapsed_dirs[current.path] == true
        entries[#entries + 1] = {
          type = "dir",
          name = display_name,
          path = current.path,
          depth = depth,
          is_collapsed = is_collapsed,
        }

        if not is_collapsed then
          walk(current, depth + 1)
        end
      else
        entries[#entries + 1] = {
          type = "file",
          name = child.name,
          path = child.path,
          depth = depth,
          file_index = child.file_index,
          status = child.status,
        }
      end
    end
  end

  walk(root, 0)
  return entries
end

return M
