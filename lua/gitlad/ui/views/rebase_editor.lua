---@mod gitlad.ui.views.rebase_editor Interactive rebase editor buffer
---@brief [[
--- Buffer for editing git-rebase-todo with evil-collection-magit keybindings.
--- Supports pick, reword, edit, squash, fixup, drop actions with single keystrokes.
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

--- Get git's comment character
---@return string
local function get_comment_char()
  local result = vim.fn.systemlist({ "git", "config", "--get", "core.commentChar" })
  if vim.v.shell_error == 0 and result[1] and result[1] ~= "" then
    return result[1]
  end
  return "#"
end

--- Change the action for the current line
--- Supports vim count for changing multiple lines (e.g., 3p changes 3 lines to pick)
---@param action string New action (pick, reword, edit, squash, fixup)
---@param comment_char string Git comment character
local function set_line_action(action, comment_char)
  local count = vim.v.count1
  local changed = 0

  while changed < count do
    local line = vim.api.nvim_get_current_line()

    -- Remove comment if present (for uncommenting dropped commits)
    local is_commented = line:match("^" .. vim.pesc(comment_char) .. "%s")
    if is_commented then
      line = line:sub(#comment_char + 2) -- Remove "# "
    end

    -- Skip break and exec lines (they don't have commits)
    local first_word = line:match("^(%S+)")
    if first_word and (first_word:match("^br") or first_word:match("^ex") or first_word == "break" or first_word == "exec") then
      vim.cmd("normal! j")
      if changed > 0 then
        break
      end
      return
    end

    -- Skip comment-only lines and the help section
    if line:match("^" .. vim.pesc(comment_char)) and not is_commented then
      break
    end

    -- Parse: "action hash subject" format
    local old_action, hash, rest = line:match("^(%S+)%s+(%x+)%s*(.*)$")
    if old_action and hash then
      -- Preserve short action format if the original was short
      local new_action = action
      if #old_action == 1 then
        new_action = action:sub(1, 1)
      end

      local new_line = new_action .. " " .. hash
      if rest and rest ~= "" then
        new_line = new_line .. " " .. rest
      end
      vim.api.nvim_set_current_line(new_line)
      changed = changed + 1
    else
      break
    end

    vim.cmd("normal! j")
  end

  -- Save after changes
  if changed > 0 and active_editor then
    vim.cmd("silent! write")
  end
end

--- Drop (comment out) the current line
---@param comment_char string Git comment character
local function drop_line(comment_char)
  local line = vim.api.nvim_get_current_line()

  -- Skip if already commented
  if line:match("^" .. vim.pesc(comment_char) .. "%s") then
    vim.cmd("normal! j")
    return
  end

  -- Skip comment lines (help section)
  if line:match("^" .. vim.pesc(comment_char)) then
    return
  end

  -- Comment out the line
  vim.api.nvim_set_current_line(comment_char .. " " .. line)
  vim.cmd("normal! j")

  -- Save after change
  if active_editor then
    vim.cmd("silent! write")
  end
end

--- Insert an exec line below current line
local function insert_exec_line()
  vim.ui.input({ prompt = "Execute: " }, function(cmd)
    if cmd and cmd ~= "" then
      local row = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_buf_set_lines(0, row, row, false, { "exec " .. cmd })
      vim.cmd("normal! j")
      if active_editor then
        vim.cmd("silent! write")
      end
    end
  end)
end

--- Insert a break line below current line
local function insert_break_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, { "break" })
  vim.cmd("normal! j")
  if active_editor then
    vim.cmd("silent! write")
  end
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
    c .. " Commands:",
    c .. "   p      pick   = use commit",
    c .. "   r      reword = use commit, but edit the commit message",
    c .. "   e      edit   = use commit, but stop for amending",
    c .. "   s      squash = use commit, but meld into previous commit",
    c .. '   f      fixup  = like "squash", but discard this commit\'s log message',
    c .. "   x      exec   = run command (the rest of the line) using shell",
    c .. "   d      drop   = remove commit (comment out line)",
    c .. "   u      undo last change",
    c .. "   ZZ     tell Git to make it happen",
    c .. "   ZQ     tell Git that you changed your mind, i.e. abort",
    c .. "   M-k    move the commit up",
    c .. "   M-j    move the commit down",
    c .. "   <CR>   show the commit in another buffer",
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
---@param comment_char string Git comment character
local function setup_keymaps(bufnr, comment_char)
  local opts = { nowait = true }

  -- Action keys (evil-collection-magit style)
  keymap.set(bufnr, "n", "p", function()
    set_line_action("pick", comment_char)
  end, "Pick", opts)

  keymap.set(bufnr, "n", "r", function()
    set_line_action("reword", comment_char)
  end, "Reword", opts)

  keymap.set(bufnr, "n", "e", function()
    set_line_action("edit", comment_char)
  end, "Edit", opts)

  keymap.set(bufnr, "n", "s", function()
    set_line_action("squash", comment_char)
  end, "Squash", opts)

  keymap.set(bufnr, "n", "f", function()
    set_line_action("fixup", comment_char)
  end, "Fixup", opts)

  keymap.set(bufnr, "n", "d", function()
    drop_line(comment_char)
  end, "Drop", opts)

  keymap.set(bufnr, "n", "x", function()
    insert_exec_line()
  end, "Exec", opts)

  keymap.set(bufnr, "n", "b", function()
    insert_break_line()
  end, "Break", opts)

  -- Move lines (evil-collection uses M-j/M-k)
  keymap.set(bufnr, "n", "<M-j>", function()
    vim.cmd("move +1")
    if active_editor then
      vim.cmd("silent! write")
    end
  end, "Move down", opts)

  keymap.set(bufnr, "n", "<M-k>", function()
    vim.cmd("move -2")
    if active_editor then
      vim.cmd("silent! write")
    end
  end, "Move up", opts)

  -- Also support M-n/M-p (magit style)
  keymap.set(bufnr, "n", "<M-n>", function()
    vim.cmd("move +1")
    if active_editor then
      vim.cmd("silent! write")
    end
  end, "Move down", opts)

  keymap.set(bufnr, "n", "<M-p>", function()
    vim.cmd("move -2")
    if active_editor then
      vim.cmd("silent! write")
    end
  end, "Move up", opts)

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

  -- Set up keymaps
  setup_keymaps(bufnr, comment_char)

  -- Replace git's default help text with our own
  -- Find where the help section starts and replace it
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local help_start = nil
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(comment_char) .. "%s*Commands:") or line:match("^" .. vim.pesc(comment_char) .. " p,") then
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
