---@mod gitlad.state.reducer Pure state reducer
---@brief [[
--- Elm Architecture-style reducer for state transitions.
--- apply(status, cmd) -> new_status is a pure function with no side effects.
---@brief ]]

local M = {}

--- Find an entry by path in a list
---@param list GitStatusEntry[]
---@param path string
---@return GitStatusEntry|nil entry
---@return number|nil index
local function find_entry(list, path)
  for i, entry in ipairs(list) do
    if entry.path == path then
      return entry, i
    end
  end
  return nil, nil
end

--- Remove an entry by path from a list, returning new list and removed entry
---@param list GitStatusEntry[]
---@param path string
---@return GitStatusEntry[] new_list
---@return GitStatusEntry|nil removed
local function remove_entry(list, path)
  local new_list = {}
  local removed = nil
  for _, entry in ipairs(list) do
    if entry.path == path then
      removed = entry
    else
      table.insert(new_list, entry)
    end
  end
  return new_list, removed
end

--- Deep copy a status result for immutability
---@param status GitStatusResult
---@return GitStatusResult
local function copy_status(status)
  return {
    branch = status.branch,
    oid = status.oid,
    upstream = status.upstream,
    ahead = status.ahead,
    behind = status.behind,
    staged = vim.deepcopy(status.staged),
    unstaged = vim.deepcopy(status.unstaged),
    untracked = vim.deepcopy(status.untracked),
    conflicted = vim.deepcopy(status.conflicted),
  }
end

--- Apply stage_file command
---@param status GitStatusResult (already copied)
---@param path string
---@param from_section "unstaged"|"untracked"
---@return GitStatusResult
function M._apply_stage_file(status, path, from_section)
  if from_section == "untracked" then
    local new_untracked, removed = remove_entry(status.untracked, path)
    if removed then
      status.untracked = new_untracked
      table.insert(status.staged, {
        path = removed.path,
        index_status = "A",
        worktree_status = ".",
      })
    end
  elseif from_section == "unstaged" then
    local existing_staged = find_entry(status.staged, path)
    local unstaged_entry, unstaged_idx = find_entry(status.unstaged, path)

    if unstaged_entry then
      table.remove(status.unstaged, unstaged_idx)

      if existing_staged then
        -- Partially staged: update the staged entry's worktree_status
        existing_staged.worktree_status = "."
      else
        -- New staged entry
        table.insert(status.staged, {
          path = unstaged_entry.path,
          orig_path = unstaged_entry.orig_path,
          index_status = unstaged_entry.worktree_status,
          worktree_status = ".",
          submodule = unstaged_entry.submodule,
        })
      end
    end
  end

  return status
end

--- Apply unstage_file command
---@param status GitStatusResult (already copied)
---@param path string
---@return GitStatusResult
function M._apply_unstage_file(status, path)
  local staged_entry, staged_idx = find_entry(status.staged, path)
  if not staged_entry then
    return status
  end

  local existing_unstaged = find_entry(status.unstaged, path)
  table.remove(status.staged, staged_idx)

  if staged_entry.index_status == "A" then
    -- Added file becomes untracked
    table.insert(status.untracked, {
      path = staged_entry.path,
      index_status = "?",
      worktree_status = "?",
    })
  elseif existing_unstaged then
    -- Already has unstaged changes: update index_status
    existing_unstaged.index_status = "."
  else
    -- Move to unstaged
    table.insert(status.unstaged, {
      path = staged_entry.path,
      orig_path = staged_entry.orig_path,
      index_status = ".",
      worktree_status = staged_entry.index_status,
      submodule = staged_entry.submodule,
    })
  end

  return status
end

--- Apply stage_all command
---@param status GitStatusResult (already copied)
---@return GitStatusResult
function M._apply_stage_all(status)
  -- Stage all untracked
  for _, entry in ipairs(status.untracked) do
    table.insert(status.staged, {
      path = entry.path,
      index_status = "A",
      worktree_status = ".",
    })
  end
  status.untracked = {}

  -- Stage all unstaged
  for _, entry in ipairs(status.unstaged) do
    local existing = find_entry(status.staged, entry.path)
    if existing then
      existing.worktree_status = "."
    else
      table.insert(status.staged, {
        path = entry.path,
        orig_path = entry.orig_path,
        index_status = entry.worktree_status,
        worktree_status = ".",
        submodule = entry.submodule,
      })
    end
  end
  status.unstaged = {}

  return status
end

--- Apply unstage_all command
---@param status GitStatusResult (already copied)
---@return GitStatusResult
function M._apply_unstage_all(status)
  for _, entry in ipairs(status.staged) do
    if entry.index_status == "A" then
      table.insert(status.untracked, {
        path = entry.path,
        index_status = "?",
        worktree_status = "?",
      })
    else
      local existing = find_entry(status.unstaged, entry.path)
      if existing then
        existing.index_status = "."
      else
        table.insert(status.unstaged, {
          path = entry.path,
          orig_path = entry.orig_path,
          index_status = ".",
          worktree_status = entry.index_status,
          submodule = entry.submodule,
        })
      end
    end
  end
  status.staged = {}

  return status
end

--- Apply a command to status, returning new status (PURE FUNCTION)
---@param status GitStatusResult
---@param cmd StatusCommand
---@return GitStatusResult
function M.apply(status, cmd)
  if cmd.type == "refresh" then
    return cmd.status
  end

  -- Create a copy for immutability
  local new_status = copy_status(status)

  if cmd.type == "stage_file" then
    return M._apply_stage_file(new_status, cmd.path, cmd.from_section)
  elseif cmd.type == "unstage_file" then
    return M._apply_unstage_file(new_status, cmd.path)
  elseif cmd.type == "stage_all" then
    return M._apply_stage_all(new_status)
  elseif cmd.type == "unstage_all" then
    return M._apply_unstage_all(new_status)
  end

  return new_status
end

return M
