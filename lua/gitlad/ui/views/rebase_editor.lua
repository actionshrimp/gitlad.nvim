---@mod gitlad.ui.views.rebase_editor Interactive rebase editor buffer
---@brief [[
--- Vim-native rebase editor for git-rebase-todo files.
--- Edit with full vim motions; action abbreviations auto-expand on save.
--- ZZ/C-c C-c to submit, ZQ/C-c C-k to abort.
---@brief ]]

local M = {}

local keymap = require("gitlad.utils.keymap")

---@class RebaseEditorState
---@field bufnr number Buffer number
---@field winnr number|nil Window number
---@field filename string Path to git-rebase-todo
---@field on_close fun(success: boolean) Callback when editor closes
---@field aborted boolean Whether the user aborted
---@field comment_char string Git comment character (usually #)

--- Active rebase editor (only one at a time)
---@type RebaseEditorState|nil
local active_editor = nil

--- Action abbreviation map (single char → full word)
local ACTION_ABBREVIATIONS = {
  p = "pick",
  r = "reword",
  e = "edit",
  s = "squash",
  f = "fixup",
  d = "drop",
  x = "exec",
  b = "break",
}

--- Get git's comment character
---@return string
local function get_comment_char()
  local result = vim.fn.systemlist({ "git", "config", "--get", "core.commentChar" })
  if vim.v.shell_error == 0 and result[1] and result[1] ~= "" then
    return result[1]
  end
  return "#"
end

--- Expand single-character action abbreviations to full words in-place.
--- Operates on the given buffer. For each todo line, if the first word is a
--- recognized single-char abbreviation, replaces it with the full word.
--- Uses nvim_buf_set_text to avoid moving the cursor.
---@param bufnr number Buffer number
---@param comment_char string Git comment character
function M._expand_action_abbreviations(bufnr, comment_char)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local comment_pat = "^" .. vim.pesc(comment_char)

  for i, line in ipairs(lines) do
    -- Skip empty lines and comment lines
    if line == "" or line:match(comment_pat) then
      goto continue
    end

    -- Match: single char followed by space and more content
    local abbrev = line:match("^(%a)%s")
    if abbrev and ACTION_ABBREVIATIONS[abbrev] then
      local full = ACTION_ABBREVIATIONS[abbrev]
      -- Replace just the abbreviation character with the full word
      vim.api.nvim_buf_set_text(bufnr, i - 1, 0, i - 1, 1, { full })
    end

    ::continue::
  end
end

--- Set up auto-expansion autocmds for the rebase editor buffer.
--- Creates buffer-local InsertLeave and TextChanged autocmds that expand
--- single-char action abbreviations to full words.
---@param bufnr number Buffer number
---@param comment_char string Git comment character
local function setup_auto_expansion(bufnr, comment_char)
  local expanding = false
  local augroup = vim.api.nvim_create_augroup("gitlad_rebase_expand_" .. bufnr, { clear = true })

  local function do_expand()
    if expanding then
      return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    expanding = true
    M._expand_action_abbreviations(bufnr, comment_char)
    expanding = false
  end

  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
    group = augroup,
    buffer = bufnr,
    callback = do_expand,
  })
end

--- Show commit at point in diffview
local function show_commit_at_point()
  local line = vim.api.nvim_get_current_line()
  local hash = line:match("(%x%x%x%x%x%x%x+)")
  if hash then
    -- Try to use diffview if available
    local ok, diffview = pcall(require, "diffview")
    if ok then
      diffview.open({ hash .. "^!" })
    else
      -- Fallback to git show in a split
      vim.cmd("split")
      vim.cmd("terminal git show " .. hash)
    end
  end
end

--- Build help text for the rebase editor
---@param comment_char string
---@return string[]
local function build_help_text(comment_char)
  local c = comment_char
  return {
    c .. "",
    c .. " This is a normal vim buffer. Edit freely with vim motions.",
    c .. "",
    c .. " Action words (pick, reword, edit, squash, fixup, drop, exec, break)",
    c .. " auto-expand from abbreviations: e.g. type 'f' and it becomes 'fixup'.",
    c .. "",
    c .. " Reorder lines:  ddp (move down), ddkP (move up), :m +1, visual mode, etc.",
    c .. " Change action:  cw fixup<Esc>, or just cw f<Esc> (auto-expands)",
    c .. " Remove commit:  dd (delete the line entirely)",
    c .. "",
    c .. " Keybindings:",
    c .. "   ZZ          submit (save and apply rebase)",
    c .. "   ZQ          abort (cancel rebase)",
    c .. "   C-c C-c     submit (also works in insert mode)",
    c .. "   C-c C-k     abort (also works in insert mode)",
    c .. "   <CR>        show commit at point in diffview",
    c .. "   q           close (prompts to save if modified)",
    c .. "",
    c .. " These lines can be re-ordered; they are executed from top to bottom.",
    c .. "",
    c .. " If you remove a line here THAT COMMIT WILL BE LOST.",
    c .. "",
    c .. " However, if you remove everything, the rebase will be aborted.",
    c .. "",
  }
end

--- Set up keymaps for the rebase editor buffer
---@param bufnr number Buffer number
local function setup_keymaps(bufnr)
  local opts = { nowait = true }

  -- Show commit at point
  keymap.set(bufnr, "n", "<CR>", function()
    show_commit_at_point()
  end, "Show commit", opts)

  -- Submit (save and close successfully)
  keymap.set(bufnr, "n", "ZZ", function()
    M.submit()
  end, "Submit", opts)

  keymap.set(bufnr, "n", "<C-c><C-c>", function()
    M.submit()
  end, "Submit", opts)

  keymap.set(bufnr, "i", "<C-c><C-c>", function()
    vim.cmd("stopinsert")
    M.submit()
  end, "Submit", opts)

  -- Abort (close without saving, signal failure)
  keymap.set(bufnr, "n", "ZQ", function()
    M.abort()
  end, "Abort", opts)

  keymap.set(bufnr, "n", "<C-c><C-k>", function()
    M.abort()
  end, "Abort", opts)

  keymap.set(bufnr, "i", "<C-c><C-k>", function()
    vim.cmd("stopinsert")
    M.abort()
  end, "Abort", opts)

  keymap.set(bufnr, "n", "q", function()
    -- q asks for confirmation if there are unsaved changes
    if vim.bo[bufnr].modified then
      vim.ui.select({ "Yes", "No" }, { prompt = "Save changes before closing?" }, function(choice)
        if choice == "Yes" then
          M.submit()
        elseif choice == "No" then
          M.abort()
        end
        -- nil means cancelled, do nothing
      end)
    else
      M.submit()
    end
  end, "Close", opts)
end

--- Submit the rebase (save and signal success)
function M.submit()
  if not active_editor then
    return
  end

  local editor = active_editor
  active_editor = nil

  -- Save the file
  vim.cmd("silent! write")

  -- Close the buffer
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(editor.bufnr) then
      vim.api.nvim_buf_delete(editor.bufnr, { force = true })
    end
    editor.on_close(true)
  end)
end

--- Abort the rebase (signal failure)
function M.abort()
  if not active_editor then
    return
  end

  local editor = active_editor
  active_editor = nil
  editor.aborted = true

  -- Close the buffer without saving
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(editor.bufnr) then
      vim.api.nvim_buf_delete(editor.bufnr, { force = true })
    end
    editor.on_close(false)
  end)
end

--- Close the rebase editor (internal cleanup)
function M.close()
  if active_editor then
    local editor = active_editor
    active_editor = nil
    if vim.api.nvim_buf_is_valid(editor.bufnr) then
      vim.api.nvim_buf_delete(editor.bufnr, { force = true })
    end
  end
end

--- Open the rebase editor
---@param filename string Path to git-rebase-todo
---@param on_close fun(success: boolean) Callback when editor closes
function M.open(filename, on_close)
  -- Close existing editor if any
  if active_editor then
    M.close()
  end

  local comment_char = get_comment_char()

  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(filename))
  local bufnr = vim.api.nvim_get_current_buf()
  local winnr = vim.api.nvim_get_current_win()

  -- Set buffer options
  vim.bo[bufnr].filetype = "gitrebase"
  vim.bo[bufnr].buftype = "" -- Regular file buffer
  vim.bo[bufnr].swapfile = false

  active_editor = {
    bufnr = bufnr,
    winnr = winnr,
    filename = filename,
    on_close = on_close,
    aborted = false,
    comment_char = comment_char,
  }

  -- Set up keymaps (no conflicting single-key maps)
  setup_keymaps(bufnr)

  -- Expand any abbreviations in the initial content
  M._expand_action_abbreviations(bufnr, comment_char)

  -- Set up auto-expansion for edits
  setup_auto_expansion(bufnr, comment_char)

  -- Replace git's default help text with our own
  -- Find where the help section starts and replace it
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local help_start = nil
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    if
      line:match("^" .. vim.pesc(comment_char) .. "%s*Commands:")
      or line:match("^" .. vim.pesc(comment_char) .. " p,")
    then
      help_start = i
      break
    end
  end

  if help_start then
    -- Replace from help_start to end with our help text
    local help_lines = build_help_text(comment_char)
    vim.api.nvim_buf_set_lines(bufnr, help_start - 1, line_count, false, help_lines)
  else
    -- No existing help found, append our help
    local help_lines = build_help_text(comment_char)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, help_lines)
  end

  -- Save the file with our help text
  vim.cmd("silent! write")

  -- Move cursor to first line
  vim.api.nvim_win_set_cursor(winnr, { 1, 0 })

  -- Cleanup autocommand
  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = bufnr,
    once = true,
    callback = function()
      -- If buffer is unloaded without explicit close, treat as abort
      if active_editor and active_editor.bufnr == bufnr then
        local editor = active_editor
        active_editor = nil
        if not editor.aborted then
          editor.on_close(false)
        end
      end
    end,
  })
end

--- Check if rebase editor is currently active
---@return boolean
function M.is_active()
  return active_editor ~= nil
end

--- Get the current rebase editor state (for testing)
---@return RebaseEditorState|nil
function M._get_state()
  return active_editor
end

return M
