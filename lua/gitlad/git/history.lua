---@mod gitlad.git.history Git command history
---@brief [[
--- Ring buffer for tracking git commands for transparency and debugging.
--- Accessible via `$` keybinding in status buffer.
---@brief ]]

local M = {}

---@class GitHistoryEntry
---@field cmd string The git subcommand (e.g., "status", "add")
---@field args string[] Full command arguments
---@field cwd string Working directory
---@field exit_code number Exit code
---@field stdout string[] Stdout lines
---@field stderr string[] Stderr lines
---@field timestamp number Unix timestamp when command started
---@field duration_ms number Duration in milliseconds

---@class GitHistory
---@field entries GitHistoryEntry[] Ring buffer of entries
---@field max_size number Maximum entries to keep
---@field head number Index of next write position
---@field count number Current number of entries
local GitHistory = {}
GitHistory.__index = GitHistory

-- Singleton instance
local instance = nil

--- Create a new history instance
---@param max_size? number Maximum entries (default 100)
---@return GitHistory
function GitHistory.new(max_size)
  local self = setmetatable({}, GitHistory)
  self.max_size = max_size or 100
  self.entries = {}
  self.head = 1
  self.count = 0
  return self
end

--- Add an entry to the history
---@param entry GitHistoryEntry
function GitHistory:add(entry)
  self.entries[self.head] = entry
  self.head = (self.head % self.max_size) + 1
  if self.count < self.max_size then
    self.count = self.count + 1
  end
end

--- Get all entries in reverse chronological order (newest first)
---@return GitHistoryEntry[]
function GitHistory:get_all()
  local result = {}
  if self.count == 0 then
    return result
  end

  -- Start from the most recent entry (one before head)
  local idx = self.head - 1
  if idx < 1 then
    idx = self.max_size
  end

  for _ = 1, self.count do
    local entry = self.entries[idx]
    if entry then
      table.insert(result, entry)
    end
    idx = idx - 1
    if idx < 1 then
      idx = self.max_size
    end
  end

  return result
end

--- Get the most recent entry
---@return GitHistoryEntry|nil
function GitHistory:get_latest()
  if self.count == 0 then
    return nil
  end
  local idx = self.head - 1
  if idx < 1 then
    idx = self.max_size
  end
  return self.entries[idx]
end

--- Clear all history
function GitHistory:clear()
  self.entries = {}
  self.head = 1
  self.count = 0
end

--- Get singleton instance
---@return GitHistory
function M.get()
  if not instance then
    instance = GitHistory.new()
  end
  return instance
end

--- Add an entry to the global history
---@param entry GitHistoryEntry
function M.add(entry)
  M.get():add(entry)
end

--- Get all entries from global history
---@return GitHistoryEntry[]
function M.get_all()
  return M.get():get_all()
end

--- Get the most recent entry
---@return GitHistoryEntry|nil
function M.get_latest()
  return M.get():get_latest()
end

--- Clear global history
function M.clear()
  M.get():clear()
end

--- Format a history entry for display
---@param entry GitHistoryEntry
---@return string[] lines
function M.format_entry(entry)
  local lines = {}
  local time_str = os.date("%H:%M:%S", entry.timestamp)
  local status_icon = entry.exit_code == 0 and "✓" or "✗"
  local duration_str = string.format("%.0fms", entry.duration_ms)
  local cmd_str = #entry.args > 0 and table.concat(entry.args, " ") or entry.cmd

  -- Header line
  table.insert(
    lines,
    string.format("%s [%s] git %s (%s)", status_icon, time_str, cmd_str, duration_str)
  )

  return lines
end

--- Format a history entry with full details
---@param entry GitHistoryEntry
---@return string[] lines
function M.format_entry_full(entry)
  local lines = {}
  local time_str = os.date("%H:%M:%S", entry.timestamp)
  local status_icon = entry.exit_code == 0 and "✓" or "✗"
  local duration_str = string.format("%.0fms", entry.duration_ms)
  local cmd_str = #entry.args > 0 and table.concat(entry.args, " ") or entry.cmd

  -- Header
  table.insert(
    lines,
    string.format("%s [%s] git %s (%s)", status_icon, time_str, cmd_str, duration_str)
  )
  table.insert(lines, string.format("  cwd: %s", entry.cwd))
  table.insert(lines, string.format("  exit: %d", entry.exit_code))

  -- Full command
  if #entry.args > 0 then
    table.insert(lines, string.format("  cmd: git %s", table.concat(entry.args, " ")))
  end

  -- Stdout
  if #entry.stdout > 0 then
    table.insert(lines, "  stdout:")
    for _, line in ipairs(entry.stdout) do
      table.insert(lines, "    " .. line)
    end
  end

  -- Stderr
  if #entry.stderr > 0 then
    table.insert(lines, "  stderr:")
    for _, line in ipairs(entry.stderr) do
      table.insert(lines, "    " .. line)
    end
  end

  return lines
end

-- Export the class for testing
M.GitHistory = GitHistory

return M
