---@mod gitlad.state.cache Timestamp-based cache invalidation
---@brief [[
--- Implements fugitive-style cache invalidation using file modification times.
--- This avoids polling and ensures we only refresh when git state actually changes.
---@brief ]]

local M = {}

---@class CacheEntry
---@field data any Cached data
---@field timestamps table<string, number> File timestamps at cache time

---@class Cache
---@field entries table<string, CacheEntry>
---@field watched_files string[] Files to check for invalidation
local Cache = {}
Cache.__index = Cache

--- Create a new cache instance
---@param watched_files? string[] Files to monitor for changes (relative to git dir)
---@return Cache
function M.new(watched_files)
  local self = setmetatable({}, Cache)
  self.entries = {}
  -- Default files that indicate git state changes
  self.watched_files = watched_files
    or {
      "HEAD",
      "index",
      "refs/heads",
      "MERGE_HEAD",
      "REBASE_HEAD",
      "CHERRY_PICK_HEAD",
      "REVERT_HEAD",
    }
  return self
end

--- Get current timestamps for watched files
---@param git_dir string Path to .git directory
---@return table<string, number>
function Cache:_get_timestamps(git_dir)
  local timestamps = {}
  for _, file in ipairs(self.watched_files) do
    local path = git_dir .. "/" .. file
    local mtime = vim.fn.getftime(path)
    -- getftime returns -1 if file doesn't exist
    timestamps[file] = mtime
  end
  return timestamps
end

--- Check if timestamps have changed
---@param old_ts table<string, number>
---@param new_ts table<string, number>
---@return boolean
local function timestamps_changed(old_ts, new_ts)
  for file, mtime in pairs(new_ts) do
    if old_ts[file] ~= mtime then
      return true
    end
  end
  -- Also check if any old files are missing from new
  for file, _ in pairs(old_ts) do
    if new_ts[file] == nil then
      return true
    end
  end
  return false
end

--- Get cached data if still valid
---@param key string Cache key
---@param git_dir string Path to .git directory
---@return any|nil data Cached data or nil if invalid/missing
---@return boolean valid Whether the cache was valid
function Cache:get(key, git_dir)
  local entry = self.entries[key]
  if not entry then
    return nil, false
  end

  local current_ts = self:_get_timestamps(git_dir)
  if timestamps_changed(entry.timestamps, current_ts) then
    -- Cache invalidated
    self.entries[key] = nil
    return nil, false
  end

  return entry.data, true
end

--- Store data in cache
---@param key string Cache key
---@param git_dir string Path to .git directory
---@param data any Data to cache
function Cache:set(key, git_dir, data)
  self.entries[key] = {
    data = data,
    timestamps = self:_get_timestamps(git_dir),
  }
end

--- Invalidate a specific cache entry
---@param key string Cache key
function Cache:invalidate(key)
  self.entries[key] = nil
end

--- Invalidate all cache entries
function Cache:invalidate_all()
  self.entries = {}
end

--- Check if cache entry exists and is valid
---@param key string Cache key
---@param git_dir string Path to .git directory
---@return boolean
function Cache:is_valid(key, git_dir)
  local _, valid = self:get(key, git_dir)
  return valid
end

-- Global cache instance for convenience
local global_cache = M.new()

--- Get the global cache instance
---@return Cache
function M.global()
  return global_cache
end

--- Reset global cache (useful for testing)
function M.reset_global()
  global_cache = M.new()
end

return M
