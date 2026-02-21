---@mod gitlad.ui.views.output Streaming command output viewer
---@brief [[
--- Floating window that displays streaming command output in real-time.
--- Uses nvim_open_term() to render ANSI escape codes (colors) from git hooks.
---@brief ]]

local keymap = require("gitlad.utils.keymap")

local M = {}

---@class OutputViewerOptions
---@field title? string Window title (default: "Output")
---@field command? string Command being run (shown in title)
---@field focus? boolean Whether to focus the window on open (default: true)

---@class OutputViewer
---@field private _bufnr number Buffer number
---@field private _winnr number|nil Window number
---@field private _chan number Terminal channel ID
---@field private _command string|nil Command being shown
---@field private _title string Window title
---@field private _completed boolean Whether command has completed
---@field private _exit_code number|nil Exit code when completed
---@field private _auto_close_timer uv_timer_t|nil Timer for auto-close
local OutputViewer = {}
OutputViewer.__index = OutputViewer

--- Build the window title string
---@param self OutputViewer
---@return string
local function build_title(self)
  local parts = {}

  if self._completed then
    if self._exit_code == 0 then
      table.insert(parts, "✓ Success")
    else
      table.insert(parts, "✗ Failed (exit " .. self._exit_code .. ")")
    end
  else
    table.insert(parts, "Running...")
  end

  if self._command then
    table.insert(parts, self._command)
  end

  return " " .. table.concat(parts, " │ ") .. " "
end

--- Update the window title
---@param self OutputViewer
local function update_title(self)
  if self._winnr and vim.api.nvim_win_is_valid(self._winnr) then
    vim.api.nvim_win_set_config(self._winnr, {
      title = build_title(self),
    })
  end
end

--- Create and open a new output viewer
---@param opts? OutputViewerOptions
---@return OutputViewer
function M.open(opts)
  opts = opts or {}

  local self = setmetatable({}, OutputViewer)
  self._command = opts.command
  self._title = opts.title or "Output"
  self._completed = false
  self._exit_code = nil
  self._auto_close_timer = nil

  -- Create buffer
  self._bufnr = vim.api.nvim_create_buf(false, true)

  -- Open terminal on the buffer (this handles ANSI escape codes)
  self._chan = vim.api.nvim_open_term(self._bufnr, {})

  -- Calculate window size and position
  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.5))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create floating window
  local focus = opts.focus ~= false -- default true
  self._winnr = vim.api.nvim_open_win(self._bufnr, focus, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = build_title(self),
    title_pos = "center",
    noautocmd = true,
  })

  -- Set window options
  vim.wo[self._winnr].wrap = false
  vim.wo[self._winnr].cursorline = false
  vim.wo[self._winnr].number = false
  vim.wo[self._winnr].relativenumber = false
  vim.wo[self._winnr].signcolumn = "no"

  -- Set up keymaps (works on terminal buffers too)
  keymap.set(self._bufnr, "n", "q", function()
    self:close()
  end, "Close output viewer", { nowait = true })

  keymap.set(self._bufnr, "n", "<Esc>", function()
    self:close()
  end, "Close output viewer", { nowait = true })

  -- Clean up on buffer wipe
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self._bufnr,
    callback = function()
      self:_cleanup()
    end,
  })

  return self
end

--- Append output text (can contain ANSI escape codes)
---@param line string The line to append
---@param _ boolean|nil Unused (was is_stderr, kept for API compatibility)
function OutputViewer:append(line, _)
  if self._completed then
    return
  end

  -- Send to terminal channel - it handles ANSI codes automatically
  -- Use \r\n for proper terminal line endings
  vim.api.nvim_chan_send(self._chan, line .. "\r\n")

  -- Scroll to end if window is valid
  if self._winnr and vim.api.nvim_win_is_valid(self._winnr) then
    local line_count = vim.api.nvim_buf_line_count(self._bufnr)
    pcall(vim.api.nvim_win_set_cursor, self._winnr, { line_count, 0 })
  end
end

--- Mark the command as complete
---@param exit_code number The exit code
function OutputViewer:complete(exit_code)
  if self._completed then
    return
  end

  self._completed = true
  self._exit_code = exit_code

  -- Update window title to show result
  update_title(self)

  -- Auto-close on success after a brief delay
  if exit_code == 0 then
    local timer = vim.uv.new_timer()
    self._auto_close_timer = timer
    timer:start(
      200,
      0,
      vim.schedule_wrap(function()
        self:close()
      end)
    )
  end
end

--- Close the output viewer
function OutputViewer:close()
  self:_cleanup()

  if self._winnr and vim.api.nvim_win_is_valid(self._winnr) then
    vim.api.nvim_win_close(self._winnr, true)
    self._winnr = nil
  end
end

--- Clean up resources
function OutputViewer:_cleanup()
  if self._auto_close_timer then
    self._auto_close_timer:stop()
    self._auto_close_timer:close()
    self._auto_close_timer = nil
  end
end

--- Check if the viewer is still open
---@return boolean
function OutputViewer:is_open()
  return self._winnr ~= nil and vim.api.nvim_win_is_valid(self._winnr)
end

-- =============================================================================
-- LazyOutputViewer - defers window creation until output actually arrives
-- =============================================================================

---@class LazyOutputViewer
---@field private _opts OutputViewerOptions Saved options for deferred open
---@field private _inner OutputViewer|nil Real viewer (created on first append)
local LazyOutputViewer = {}
LazyOutputViewer.__index = LazyOutputViewer

--- Create a new lazy output viewer
---@param opts? OutputViewerOptions
---@return LazyOutputViewer
function LazyOutputViewer.new(opts)
  local self = setmetatable({}, LazyOutputViewer)
  self._opts = opts or {}
  self._inner = nil
  return self
end

--- Append output text. On first call, creates the real viewer.
---@param line string The line to append
---@param is_stderr boolean|nil Whether this is stderr
function LazyOutputViewer:append(line, is_stderr)
  if not self._inner then
    -- Open without stealing focus since we're opening mid-operation
    local opts = vim.tbl_extend("force", self._opts, { focus = false })
    self._inner = M.open(opts)
  end
  self._inner:append(line, is_stderr)
end

--- Mark the command as complete.
--- If no viewer was created and exit_code == 0, do nothing (no output, success).
--- If viewer exists, delegate.
---@param exit_code number The exit code
function LazyOutputViewer:complete(exit_code)
  if self._inner then
    self._inner:complete(exit_code)
  end
  -- No viewer created = no output was produced, nothing to show
end

--- Close the output viewer
function LazyOutputViewer:close()
  if self._inner then
    self._inner:close()
  end
end

--- Check if the viewer is still open
---@return boolean
function LazyOutputViewer:is_open()
  if self._inner then
    return self._inner:is_open()
  end
  return false
end

-- =============================================================================
-- NoopViewer - discards everything (for "never" config)
-- =============================================================================

---@class NoopViewer
local NoopViewer = {}
NoopViewer.__index = NoopViewer

--- Create a new noop viewer
---@return NoopViewer
function NoopViewer.new()
  return setmetatable({}, NoopViewer)
end

function NoopViewer:append(_, _) end
function NoopViewer:complete(_) end
function NoopViewer:close() end

---@return boolean
function NoopViewer:is_open()
  return false
end

-- =============================================================================
-- Factory function
-- =============================================================================

--- Create an output viewer based on config.
--- Returns a LazyOutputViewer (default), OutputViewer ("always"), or NoopViewer ("never").
---@param opts? OutputViewerOptions
---@return OutputViewer|LazyOutputViewer|NoopViewer
function M.create(opts)
  local config = require("gitlad.config")
  local mode = config.get().output and config.get().output.hook_output or "lazy"

  if mode == "never" then
    return NoopViewer.new()
  elseif mode == "always" then
    return M.open(opts)
  else
    -- "lazy" (default)
    return LazyOutputViewer.new(opts)
  end
end

return M
