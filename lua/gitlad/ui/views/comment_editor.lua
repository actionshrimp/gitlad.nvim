---@mod gitlad.ui.views.comment_editor Comment editor buffer
---@brief [[
--- Scratch buffer for writing PR comments. Follows the commit_editor pattern.
--- C-c C-c to submit, C-c C-k to abort.
---@brief ]]

local M = {}

local keymap_util = require("gitlad.utils.keymap")

---@class CommentEditorOpts
---@field title string Title shown in buffer header comment
---@field initial_body? string Pre-filled body text
---@field on_submit fun(body: string) Called with the comment body when submitted
---@field on_abort? fun() Called when aborted

---@class CommentEditorState
---@field bufnr number Buffer number
---@field winnr number|nil Window number
---@field opts CommentEditorOpts Editor options
local active_editor = nil

--- Extract the comment body from the buffer (excluding comment lines)
---@param bufnr number
---@return string
local function extract_body(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body_lines = {}

  for _, line in ipairs(lines) do
    if not line:match("^#") then
      table.insert(body_lines, line)
    end
  end

  -- Trim trailing empty lines
  while #body_lines > 0 and body_lines[#body_lines] == "" do
    table.remove(body_lines)
  end

  return table.concat(body_lines, "\n")
end

--- Close the editor
local function close_editor()
  if not active_editor then
    return
  end

  local bufnr = active_editor.bufnr
  local winnr = active_editor.winnr
  active_editor = nil

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modified = false
  end

  -- Close the split window
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_close(winnr, true)
  end

  -- Defer buffer deletion
  vim.schedule(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)
end

--- Submit the comment
local function do_submit()
  if not active_editor then
    return
  end

  local body = extract_body(active_editor.bufnr)

  if body == "" then
    vim.notify("[gitlad] Aborting: empty comment", vim.log.levels.WARN)
    return
  end

  local on_submit = active_editor.opts.on_submit
  close_editor()
  on_submit(body)
end

--- Abort the comment
local function do_abort()
  if not active_editor then
    return
  end

  local on_abort = active_editor.opts.on_abort
  close_editor()

  if on_abort then
    on_abort()
  end

  vim.notify("[gitlad] Comment aborted", vim.log.levels.INFO)
end

--- Set up keymaps for the comment editor buffer
---@param bufnr number
local function setup_keymaps(bufnr)
  -- C-c C-c to submit
  keymap_util.set(bufnr, "n", "<C-c><C-c>", do_submit, "Submit comment")
  keymap_util.set(bufnr, "i", "<C-c><C-c>", function()
    vim.cmd("stopinsert")
    do_submit()
  end, "Submit comment")

  -- C-c C-k to abort
  keymap_util.set(bufnr, "n", "<C-c><C-k>", do_abort, "Abort comment")
  keymap_util.set(bufnr, "i", "<C-c><C-k>", function()
    vim.cmd("stopinsert")
    do_abort()
  end, "Abort comment")

  -- ZZ to submit
  keymap_util.set(bufnr, "n", "ZZ", do_submit, "Submit comment")

  -- ZQ to abort
  keymap_util.set(bufnr, "n", "ZQ", do_abort, "Abort comment")

  -- q to abort (normal mode only)
  keymap_util.set(bufnr, "n", "q", do_abort, "Abort comment")
end

--- Open the comment editor
---@param opts CommentEditorOpts
function M.open(opts)
  -- Close any existing editor
  if active_editor then
    close_editor()
  end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "gitlad://COMMENT_EDITMSG")
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"

  -- Initialize state
  active_editor = {
    bufnr = bufnr,
    winnr = nil,
    opts = opts,
  }

  -- Set up keymaps
  setup_keymaps(bufnr)

  -- Open in split above
  vim.cmd("aboveleft split")
  vim.api.nvim_set_current_buf(bufnr)
  active_editor.winnr = vim.api.nvim_get_current_win()

  -- Build content
  local lines = {}

  if opts.initial_body and opts.initial_body ~= "" then
    for line in (opts.initial_body .. "\n"):gmatch("(.-)\n") do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "")
  end

  table.insert(lines, "")
  table.insert(lines, "# " .. opts.title)
  table.insert(lines, "# Press C-c C-c to submit, C-c C-k to abort")
  table.insert(lines, "# Lines starting with '#' will be ignored")

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(active_editor.winnr, { 1, 0 })
  vim.bo[bufnr].modified = false
end

--- Check if comment editor is currently open
---@return boolean
function M.is_open()
  return active_editor ~= nil
end

--- Close the comment editor (for external use)
function M.close()
  close_editor()
end

return M
