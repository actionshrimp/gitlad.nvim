---@mod gitlad.ui.views.output Streaming command output viewer
---@brief [[
--- Floating window that displays streaming command output in real-time.
--- Used to show progress of git operations like commits with hooks.
---@brief ]]

local M = {}

local spinner_util = require("gitlad.ui.utils.spinner")
local hl = require("gitlad.ui.hl")

-- Namespace for output viewer highlights
local ns_output = vim.api.nvim_create_namespace("gitlad_output")

---@class OutputViewerOptions
---@field title? string Window title (default: "Output")
---@field command? string Command being run (shown in header)

---@class OutputViewer
---@field private _bufnr number Buffer number
---@field private _winnr number|nil Window number
---@field private _lines string[] Accumulated output lines
---@field private _command string|nil Command being shown
---@field private _title string Window title
---@field private _spinner Spinner Spinner for progress indication
---@field private _completed boolean Whether command has completed
---@field private _exit_code number|nil Exit code when completed
---@field private _auto_close_timer uv_timer_t|nil Timer for auto-close
local OutputViewer = {}
OutputViewer.__index = OutputViewer

--- Create and open a new output viewer
---@param opts? OutputViewerOptions
---@return OutputViewer
function M.open(opts)
  opts = opts or {}

  local self = setmetatable({}, OutputViewer)
  self._lines = {}
  self._command = opts.command
  self._title = opts.title or "Output"
  self._completed = false
  self._exit_code = nil
  self._auto_close_timer = nil

  -- Create spinner
  self._spinner = spinner_util.new()

  -- Create buffer
  self._bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self._bufnr].buftype = "nofile"
  vim.bo[self._bufnr].bufhidden = "wipe"
  vim.bo[self._bufnr].swapfile = false
  vim.bo[self._bufnr].filetype = "gitlad-output"

  -- Calculate window size and position
  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.5))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create floating window (enter=true to focus it for keymaps)
  self._winnr = vim.api.nvim_open_win(self._bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " " .. self._title .. " ",
    title_pos = "center",
    noautocmd = true,
  })

  -- Set window options
  vim.wo[self._winnr].wrap = false
  vim.wo[self._winnr].cursorline = false
  vim.wo[self._winnr].number = false
  vim.wo[self._winnr].relativenumber = false
  vim.wo[self._winnr].signcolumn = "no"

  -- Set up keymaps
  vim.keymap.set("n", "q", function()
    self:close()
  end, { buffer = self._bufnr, nowait = true, desc = "Close output viewer" })

  vim.keymap.set("n", "<Esc>", function()
    self:close()
  end, { buffer = self._bufnr, nowait = true, desc = "Close output viewer" })

  -- Clean up on buffer wipe
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self._bufnr,
    callback = function()
      self:_cleanup()
    end,
  })

  -- Start spinner and render initial content
  self._spinner:start(function()
    self:_render()
  end)
  self:_render()

  return self
end

--- Append a line of output
---@param line string The line to append
---@param is_stderr boolean Whether this is stderr output
function OutputViewer:append(line, is_stderr)
  if self._completed then
    return
  end

  -- Store line with stderr flag for highlighting
  table.insert(self._lines, { text = line, is_stderr = is_stderr })
  self:_render()
end

--- Mark the command as complete
---@param exit_code number The exit code
function OutputViewer:complete(exit_code)
  if self._completed then
    return
  end

  self._completed = true
  self._exit_code = exit_code
  self._spinner:stop()
  self:_render()

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
  self._spinner:destroy()

  if self._auto_close_timer then
    self._auto_close_timer:stop()
    self._auto_close_timer:close()
    self._auto_close_timer = nil
  end
end

--- Render the buffer content
function OutputViewer:_render()
  if not vim.api.nvim_buf_is_valid(self._bufnr) then
    return
  end

  local lines = {}

  -- Header line with command and status
  local header
  if self._completed then
    local status_icon = self._exit_code == 0 and "✓" or "✗"
    local status_text = self._exit_code == 0 and "Success"
      or ("Failed (exit " .. self._exit_code .. ")")
    header = status_icon .. " " .. status_text
    if self._command then
      header = header .. "  │  " .. self._command
    end
  else
    header = self._spinner:get_char() .. " Running..."
    if self._command then
      header = header .. "  │  " .. self._command
    end
  end
  table.insert(lines, header)
  table.insert(lines, string.rep("─", 80))

  -- Output lines
  for _, line_info in ipairs(self._lines) do
    table.insert(lines, line_info.text)
  end

  -- If no output yet, show placeholder
  if #self._lines == 0 and not self._completed then
    table.insert(lines, "")
    table.insert(lines, "  Waiting for output...")
  end

  -- Update buffer
  vim.bo[self._bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self._bufnr, 0, -1, false, lines)
  vim.bo[self._bufnr].modifiable = false

  -- Apply highlighting
  self:_apply_highlights(lines)

  -- Scroll to end if window is valid
  if self._winnr and vim.api.nvim_win_is_valid(self._winnr) then
    local line_count = vim.api.nvim_buf_line_count(self._bufnr)
    pcall(vim.api.nvim_win_set_cursor, self._winnr, { line_count, 0 })
  end
end

--- Apply highlights to the buffer
---@param lines string[]
function OutputViewer:_apply_highlights(lines)
  vim.api.nvim_buf_clear_namespace(self._bufnr, ns_output, 0, -1)

  -- Header line (line 0)
  if self._completed then
    local hl_group = self._exit_code == 0 and "GitladOutputSuccess" or "GitladOutputFailure"
    hl.set(self._bufnr, ns_output, 0, 0, 1, hl_group) -- Status icon
  else
    hl.set(self._bufnr, ns_output, 0, 0, 1, "GitladOutputSpinner") -- Spinner
  end

  -- Command part of header
  if self._command then
    local cmd_start = lines[1]:find("│")
    if cmd_start then
      hl.set(self._bufnr, ns_output, 0, cmd_start + 2, #lines[1], "GitladOutputCommand")
    end
  end

  -- Separator line (line 1)
  hl.set(self._bufnr, ns_output, 1, 0, #lines[2], "GitladOutputSeparator")

  -- Output lines (starting at line 2)
  for i, line_info in ipairs(self._lines) do
    local line_idx = i + 1 -- 0-indexed, offset by header (2 lines)
    if line_info.is_stderr then
      hl.set(self._bufnr, ns_output, line_idx, 0, #line_info.text, "GitladOutputStderr")
    end
  end
end

--- Check if the viewer is still open
---@return boolean
function OutputViewer:is_open()
  return self._winnr ~= nil and vim.api.nvim_win_is_valid(self._winnr)
end

return M
