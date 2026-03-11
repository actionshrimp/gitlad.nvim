---@mod gitlad.utils.persist Lightweight key-value persistence
---@brief [[
--- Simple persistent store for popup switch states and similar small values.
--- Data is stored as JSON in stdpath("data")/gitlad/popup_switches.json.
---
--- Override M._override_path in tests to avoid touching the real data directory.
---@brief ]]

local M = {}

--- Override storage path (for tests)
---@type string|nil
M._override_path = nil

---@return string
local function data_file()
  return M._override_path or (vim.fn.stdpath("data") .. "/gitlad/popup_switches.json")
end

---@type table<string, any>|nil
local _cache = nil

--- Reset the in-memory cache (call after changing _override_path in tests)
function M._reset_cache()
  _cache = nil
end

---@return table<string, any>
local function load()
  if _cache then
    return _cache
  end
  local path = data_file()
  local f = io.open(path, "r")
  if not f then
    _cache = {}
    return _cache
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  _cache = (ok and type(data) == "table") and data or {}
  return _cache
end

---@param data table<string, any>
local function save(data)
  local path = data_file()
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(path, "w")
  if not f then
    return
  end
  f:write(vim.json.encode(data))
  f:close()
end

--- Get a persisted value by key
---@param key string
---@return any
function M.get(key)
  return load()[key]
end

--- Set a persisted value by key
---@param key string
---@param value any
function M.set(key, value)
  local data = load()
  data[key] = value
  save(data)
end

return M
