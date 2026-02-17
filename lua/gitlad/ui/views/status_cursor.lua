---@mod gitlad.ui.views.status_cursor Status buffer cursor restore module
---@brief [[
--- Provides cursor identity save/restore across status buffer refreshes.
--- Prevents cursor jumps and preserves expansion state when the buffer re-renders.
---@brief ]]

local M = {}

-- Import diff cache key helper
local status_render = require("gitlad.ui.views.status_render")
local diff_cache_key = status_render.diff_cache_key

---@class CursorIdentity
---@field type string The type of element at cursor
---@field section_key string|nil Section key (e.g., "staged", "unstaged")
---@field path string|nil File path (for file/hunk/diff types)
---@field hunk_index number|nil Hunk index (for hunk_header and diff_line)
---@field line_in_hunk number|nil Offset from hunk header (for diff_line)
---@field hash string|nil Commit/stash hash
---@field stash_ref string|nil Stash ref (e.g., "stash@{0}")
---@field submodule_path string|nil Submodule path
---@field worktree_path string|nil Worktree path
---@field rebase_state string|nil Rebase state (todo/stop/done/onto)
---@field raw_line number|nil Fallback raw line number

-- Forward declarations for helper functions used by find_cursor_target
local find_exact_match
local find_file_line
local find_file_any_section
local find_nearest_sibling
local find_section_header
local find_nearest_section
local find_first_item

--- Save the identity of what the cursor is currently on
---@param self StatusBuffer
---@return CursorIdentity|nil
local function save_cursor_identity(self)
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return nil
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, self.winnr)
  if not ok then
    return nil
  end
  local line = cursor[1]

  -- Check section headers first
  local section_info = self.section_lines[line]
  if section_info then
    return {
      type = "section",
      section_key = section_info.section,
    }
  end

  -- Check line_map entries
  local info = self.line_map[line]
  if info then
    if info.type == "file" then
      if info.is_hunk_header then
        return {
          type = "hunk_header",
          section_key = info.section,
          path = info.path,
          hunk_index = info.hunk_index,
        }
      elseif info.hunk_index then
        -- Diff content line - calculate offset from hunk header
        local offset = 0
        for scan = line - 1, 1, -1 do
          local scan_info = self.line_map[scan]
          if
            scan_info
            and scan_info.is_hunk_header
            and scan_info.path == info.path
            and scan_info.hunk_index == info.hunk_index
          then
            offset = line - scan
            break
          end
          if
            not scan_info
            or scan_info.path ~= info.path
            or scan_info.hunk_index ~= info.hunk_index
          then
            offset = line - scan - 1
            break
          end
        end
        return {
          type = "diff_line",
          section_key = info.section,
          path = info.path,
          hunk_index = info.hunk_index,
          line_in_hunk = offset,
        }
      else
        return {
          type = "file",
          section_key = info.section,
          path = info.path,
        }
      end
    elseif info.type == "commit" then
      return {
        type = "commit",
        section_key = info.section,
        hash = info.commit and info.commit.hash,
      }
    elseif info.type == "stash" then
      return {
        type = "stash",
        section_key = info.section,
        stash_ref = info.stash and info.stash.ref,
      }
    elseif info.type == "submodule" then
      return {
        type = "submodule",
        section_key = info.section,
        submodule_path = info.submodule and info.submodule.path,
      }
    elseif info.type == "worktree" then
      return {
        type = "worktree",
        section_key = info.section,
        worktree_path = info.worktree and info.worktree.path,
      }
    elseif info.type == "rebase_commit" then
      return {
        type = "rebase_commit",
        section_key = "rebase_sequence",
        hash = info.hash,
        rebase_state = info.rebase_state,
      }
    elseif info.type == "submodule_diff" then
      return {
        type = "fallback",
        raw_line = line,
      }
    end
  end

  -- Fallback for header/blank lines
  return {
    type = "fallback",
    raw_line = line,
  }
end

--- Find the best target line for a cursor identity in the current buffer state
--- Uses cascading fallback strategy inspired by magit's goto-successor
---@param self StatusBuffer
---@param identity CursorIdentity
---@return number|nil line Target line number
local function find_cursor_target(self, identity)
  if not identity then
    return nil
  end

  -- Priority 1: Exact match
  local target = find_exact_match(self, identity)
  if target then
    return target
  end

  -- Priority 2: Parent element (hunk/diff_line gone -> try file line)
  if identity.type == "diff_line" or identity.type == "hunk_header" then
    target = find_file_line(self, identity.path, identity.section_key)
    if target then
      return target
    end
  end

  -- Priority 3: Nearest sibling in same section
  if identity.section_key then
    target = find_nearest_sibling(self, identity.section_key)
    if target then
      return target
    end
  end

  -- Priority 4: Same file, different section (file moved e.g. unstaged -> staged)
  if identity.path then
    target = find_file_any_section(self, identity.path)
    if target then
      return target
    end
  end

  -- Priority 5: Section header
  if identity.section_key then
    target = find_section_header(self, identity.section_key)
    if target then
      return target
    end
  end

  -- Priority 6: Nearest section header
  local fallback_line = identity.raw_line
  if not fallback_line and identity.section_key then
    fallback_line = 1
  end
  if fallback_line then
    target = find_nearest_section(self, fallback_line)
    if target then
      return target
    end
  end

  -- Priority 7: First item in line_map
  return find_first_item(self)
end

--- Find exact match for identity in current line_map/section_lines
---@param self StatusBuffer
---@param identity CursorIdentity
---@return number|nil
find_exact_match = function(self, identity)
  if identity.type == "section" then
    for line_num, info in pairs(self.section_lines) do
      if info.section == identity.section_key then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "file" then
    for line_num, info in pairs(self.line_map) do
      if
        info.type == "file"
        and info.path == identity.path
        and info.section == identity.section_key
        and not info.hunk_index
      then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "hunk_header" then
    for line_num, info in pairs(self.line_map) do
      if
        info.type == "file"
        and info.path == identity.path
        and info.section == identity.section_key
        and info.is_hunk_header
        and info.hunk_index == identity.hunk_index
      then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "diff_line" then
    -- Find the hunk header, then offset into it
    for line_num, info in pairs(self.line_map) do
      if
        info.type == "file"
        and info.path == identity.path
        and info.section == identity.section_key
        and info.is_hunk_header
        and info.hunk_index == identity.hunk_index
      then
        local t = line_num + (identity.line_in_hunk or 0)
        -- Verify target is still within the same hunk
        local target_info = self.line_map[t]
        if
          target_info
          and target_info.path == identity.path
          and target_info.hunk_index == identity.hunk_index
        then
          return t
        end
        -- If offset is past end, return last line of hunk
        local last_valid = line_num
        for scan = line_num + 1, line_num + 1000 do
          local scan_info = self.line_map[scan]
          if
            scan_info
            and scan_info.path == identity.path
            and scan_info.hunk_index == identity.hunk_index
            and not scan_info.is_hunk_header
          then
            last_valid = scan
          else
            break
          end
        end
        return last_valid
      end
    end
    return nil
  end

  if identity.type == "commit" and identity.hash then
    for line_num, info in pairs(self.line_map) do
      if info.type == "commit" and info.commit and info.commit.hash == identity.hash then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "stash" and identity.stash_ref then
    for line_num, info in pairs(self.line_map) do
      if info.type == "stash" and info.stash and info.stash.ref == identity.stash_ref then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "submodule" and identity.submodule_path then
    for line_num, info in pairs(self.line_map) do
      if
        info.type == "submodule"
        and info.submodule
        and info.submodule.path == identity.submodule_path
      then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "worktree" and identity.worktree_path then
    for line_num, info in pairs(self.line_map) do
      if
        info.type == "worktree"
        and info.worktree
        and info.worktree.path == identity.worktree_path
      then
        return line_num
      end
    end
    return nil
  end

  if identity.type == "rebase_commit" and identity.hash then
    for line_num, info in pairs(self.line_map) do
      if info.type == "rebase_commit" and info.hash == identity.hash then
        return line_num
      end
    end
    return nil
  end

  return nil
end

--- Find a file line (not hunk/diff) in a specific section
---@param self StatusBuffer
---@param path string
---@param section_key string
---@return number|nil
find_file_line = function(self, path, section_key)
  for line_num, info in pairs(self.line_map) do
    if
      info.type == "file"
      and info.path == path
      and info.section == section_key
      and not info.hunk_index
    then
      return line_num
    end
  end
  return nil
end

--- Find a file in any section (for when files move between sections)
---@param self StatusBuffer
---@param path string
---@return number|nil
find_file_any_section = function(self, path)
  for line_num, info in pairs(self.line_map) do
    if info.type == "file" and info.path == path and not info.hunk_index then
      return line_num
    end
  end
  return nil
end

--- Find nearest sibling item in the same section
---@param self StatusBuffer
---@param section_key string
---@return number|nil
find_nearest_sibling = function(self, section_key)
  local entries = {}
  for line_num, info in pairs(self.line_map) do
    if info.section == section_key and not info.hunk_index and not info.is_hunk_header then
      table.insert(entries, line_num)
    end
  end

  if #entries == 0 then
    return nil
  end

  table.sort(entries)
  return entries[1]
end

--- Find a section header line
---@param self StatusBuffer
---@param section_key string
---@return number|nil
find_section_header = function(self, section_key)
  for line_num, info in pairs(self.section_lines) do
    if info.section == section_key then
      return line_num
    end
  end
  return nil
end

--- Find nearest section header to a line number
---@param self StatusBuffer
---@param target_line number
---@return number|nil
find_nearest_section = function(self, target_line)
  local best_line = nil
  local best_dist = math.huge

  for line_num, _ in pairs(self.section_lines) do
    local dist = math.abs(line_num - target_line)
    if dist < best_dist then
      best_dist = dist
      best_line = line_num
    end
  end

  return best_line
end

--- Find first item in line_map
---@param self StatusBuffer
---@return number|nil
find_first_item = function(self)
  local min_line = nil
  for line_num, _ in pairs(self.line_map) do
    if not min_line or line_num < min_line then
      min_line = line_num
    end
  end
  return min_line
end

--- Restore cursor to the best matching position
---@param self StatusBuffer
---@param identity CursorIdentity|nil
local function restore_cursor(self, identity)
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  if not identity then
    return
  end

  local target = find_cursor_target(self, identity)
  if target then
    -- Clamp to buffer line count
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    target = math.min(target, line_count)
    target = math.max(target, 1)
    pcall(vim.api.nvim_win_set_cursor, self.winnr, { target, 0 })
  end
end

--- Clean up stale entries from expansion state
--- Removes entries for files/commits that no longer exist in the current status
---@param self StatusBuffer
local function cleanup_stale_expansion(self)
  local status = self.repo_state.status
  if not status then
    return
  end

  -- Build set of valid file keys from current status
  local valid_file_keys = {}
  for _, section_name in ipairs({ "staged", "unstaged", "untracked", "conflicted" }) do
    local entries = status[section_name] or {}
    for _, entry in ipairs(entries) do
      local key = diff_cache_key(entry.path, section_name)
      valid_file_keys[key] = true
    end
  end

  -- Add submodule keys
  for _, submodule in ipairs(status.submodules or {}) do
    valid_file_keys["submodule:" .. submodule.path] = true
  end

  -- Remove stale entries from expanded_files
  for key, _ in pairs(self.expanded_files) do
    if not valid_file_keys[key] then
      self.expanded_files[key] = nil
    end
  end

  -- Remove stale entries from diff_cache
  for key, _ in pairs(self.diff_cache) do
    if not valid_file_keys[key] then
      self.diff_cache[key] = nil
    end
  end

  -- Remove stale entries from remembered_file_states
  for key, _ in pairs(self.remembered_file_states) do
    if not valid_file_keys[key] then
      self.remembered_file_states[key] = nil
    end
  end

  -- Build set of valid commit hashes
  local valid_hashes = {}
  for _, section_name in ipairs({
    "unpushed_upstream",
    "unpulled_upstream",
    "unpushed_push",
    "unpulled_push",
    "recent",
  }) do
    for _, commit in ipairs(status[section_name] or {}) do
      valid_hashes[commit.hash] = true
    end
  end

  -- Remove stale entries from expanded_commits
  for hash, _ in pairs(self.expanded_commits) do
    if not valid_hashes[hash] then
      self.expanded_commits[hash] = nil
    end
  end
end

--- Attach cursor methods to StatusBuffer class
---@param StatusBuffer_class table The StatusBuffer class
function M.setup(StatusBuffer_class)
  StatusBuffer_class._save_cursor_identity = save_cursor_identity
  StatusBuffer_class._restore_cursor = restore_cursor
  StatusBuffer_class._cleanup_stale_expansion = cleanup_stale_expansion
end

-- Export for testing
M._find_cursor_target = find_cursor_target
M._find_exact_match = find_exact_match
M._find_file_line = find_file_line
M._find_file_any_section = find_file_any_section
M._find_nearest_sibling = find_nearest_sibling
M._find_section_header = find_section_header
M._find_nearest_section = find_nearest_section
M._find_first_item = find_first_item
M._save_cursor_identity = save_cursor_identity
M._cleanup_stale_expansion = cleanup_stale_expansion

return M
