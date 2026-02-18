---@mod gitlad.state.pending_ops Pending operation tracker
---@brief [[
--- Tracks in-flight worktree operations (add/delete) and provides an animated
--- spinner for visual feedback in the status buffer. Also supports change and
--- tick callbacks for driving UI updates.
---@brief ]]

local M = {}

-- Braille dot spinner frames (same as ui/utils/spinner.lua)
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local FRAME_INTERVAL_MS = 80

---@class PendingOp
---@field type "add"|"delete" Operation type
---@field path string Normalized worktree path
---@field description string Human-readable description
---@field repo_root string Repository root this operation belongs to

-- Module state
local pending = {} ---@type table<string, PendingOp>
local frame_index = 1
local timer = nil ---@type uv_timer_t|nil
local change_callbacks = {} ---@type fun()[]
local tick_callbacks = {} ---@type fun()[]

--- Normalize a path for use as a lookup key (strip trailing slash)
---@param path string
---@return string
local function normalize(path)
  return path:gsub("/$", "")
end

--- Fire all registered change callbacks
local function fire_change()
  for _, cb in ipairs(change_callbacks) do
    cb()
  end
end

--- Fire all registered tick callbacks
local function fire_tick()
  for _, cb in ipairs(tick_callbacks) do
    cb()
  end
end

--- Start the animation timer (if not already running)
local function start_timer()
  if timer then
    return
  end
  frame_index = 1
  timer = vim.uv.new_timer()
  timer:start(
    0,
    FRAME_INTERVAL_MS,
    vim.schedule_wrap(function()
      if not timer then
        return
      end
      frame_index = (frame_index % #SPINNER_FRAMES) + 1
      fire_tick()
    end)
  )
end

--- Stop the animation timer
local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  frame_index = 1
end

--- Register a pending operation and return a done() closure.
--- Starts the animation timer on the first registration.
---@param path string Worktree path
---@param op_type "add"|"delete" Operation type
---@param description string Human-readable description (e.g. "Deleting worktree...")
---@param repo_root string Repository root
---@return fun() done Call this when the operation completes (success or failure)
function M.register(path, op_type, description, repo_root)
  local key = normalize(path)
  pending[key] = {
    type = op_type,
    path = key,
    description = description,
    repo_root = repo_root,
  }

  start_timer()
  fire_change()

  local called = false
  return function()
    if called then
      return
    end
    called = true
    pending[key] = nil
    if not next(pending) then
      stop_timer()
    end
    fire_change()
  end
end

--- Check if a path has a pending operation
---@param path string Worktree path
---@return boolean
function M.is_pending(path)
  return pending[normalize(path)] ~= nil
end

--- Check if there are any pending operations
---@return boolean
function M.has_any()
  return next(pending) ~= nil
end

--- Get all pending operations
---@return table<string, PendingOp>
function M.get_all()
  return pending
end

--- Get the current spinner frame character
---@return string
function M.get_spinner_char()
  return SPINNER_FRAMES[frame_index]
end

--- Register a callback for structural changes (op added/removed)
---@param callback fun()
function M.on_change(callback)
  table.insert(change_callbacks, callback)
end

--- Unregister a change callback
---@param callback fun()
function M.off_change(callback)
  for i, cb in ipairs(change_callbacks) do
    if cb == callback then
      table.remove(change_callbacks, i)
      return
    end
  end
end

--- Register a callback for animation frame ticks
---@param callback fun()
function M.on_tick(callback)
  table.insert(tick_callbacks, callback)
end

--- Unregister a tick callback
---@param callback fun()
function M.off_tick(callback)
  for i, cb in ipairs(tick_callbacks) do
    if cb == callback then
      table.remove(tick_callbacks, i)
      return
    end
  end
end

--- QuitPre guard. If the user chooses not to quit, temporarily marks the
--- current buffer as a modified normal buffer so :q aborts with E37.
--- The original buffer state is restored on the next event loop tick.
function M._quit_guard()
  if not M.has_any() then
    return
  end
  local descs = {}
  for _, op in pairs(pending) do
    table.insert(descs, "  - " .. op.description .. " (" .. op.path .. ")")
  end
  local msg = "Worktree operations in progress:\n"
    .. table.concat(descs, "\n")
    .. "\n\nQuitting now may leave worktrees in an inconsistent state.\nQuit anyway?"
  local choice = vim.fn.confirm(msg, "&Yes\n&No", 2)
  if choice ~= 1 then
    -- Trick :q into aborting: temporarily make the buffer look like
    -- a modified normal file. After :q sees E37 and aborts, we restore
    -- the original state via vim.schedule.
    local buf = vim.api.nvim_get_current_buf()
    local saved_bt = vim.bo[buf].buftype
    local saved_mod = vim.bo[buf].modified
    vim.bo[buf].buftype = ""
    vim.bo[buf].modified = true
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].buftype = saved_bt
        vim.bo[buf].modified = saved_mod
      end
    end)
  end
end

--- Reset all state (for testing)
function M.clear_all()
  pending = {}
  stop_timer()
  change_callbacks = {}
  tick_callbacks = {}
  frame_index = 1
end

return M
