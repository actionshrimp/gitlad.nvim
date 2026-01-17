---@mod gitlad.ui.views.commit_editor Commit message editor buffer
---@brief [[
--- Buffer for editing commit messages with magit-style keybindings.
--- C-c C-c to confirm, C-c C-k to abort.
---@brief ]]

local M = {}

local git = require("gitlad.git")

---@class CommitEditorState
---@field bufnr number Buffer number
---@field winnr number|nil Window number
---@field repo_state RepoState
---@field args string[] Extra git commit arguments
---@field amend boolean Whether this is an amend
---@field verbose_diff string[]|nil Diff lines for verbose mode

--- Active commit editor (only one at a time)
---@type CommitEditorState|nil
local active_editor = nil

--- Get the initial commit message for amend
---@param repo_root string
---@param callback fun(message: string[]|nil)
local function get_amend_message(repo_root, callback)
  local cli = require("gitlad.git.cli")
  cli.run_async({ "log", "-1", "--pretty=%B" }, { cwd = repo_root }, function(result)
    if result.code == 0 then
      -- Remove trailing empty lines
      local lines = result.stdout
      while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
      end
      callback(lines)
    else
      callback(nil)
    end
  end)
end

--- Get the diff for verbose mode
---@param repo_root string
---@param staged boolean
---@param callback fun(lines: string[]|nil)
local function get_verbose_diff(repo_root, staged, callback)
  local cli = require("gitlad.git.cli")
  local args = { "diff" }
  if staged then
    table.insert(args, "--cached")
  end
  cli.run_async(args, { cwd = repo_root }, function(result)
    if result.code == 0 then
      callback(result.stdout)
    else
      callback(nil)
    end
  end)
end

--- Create the commit editor buffer content
---@param message_lines string[] Initial message lines
---@param verbose_diff string[]|nil Diff for verbose mode
---@return string[]
local function build_buffer_content(message_lines, verbose_diff)
  local lines = {}

  -- Add message lines (or empty line for new commit)
  if #message_lines > 0 then
    vim.list_extend(lines, message_lines)
  else
    table.insert(lines, "")
  end

  -- Add help comment
  table.insert(lines, "")
  table.insert(lines, "# Press C-c C-c to commit, C-c C-k to abort")
  table.insert(lines, "# Lines starting with '#' will be ignored")

  -- Add verbose diff if requested
  if verbose_diff and #verbose_diff > 0 then
    table.insert(lines, "#")
    table.insert(lines, "# Changes to be committed:")
    for _, diff_line in ipairs(verbose_diff) do
      table.insert(lines, "# " .. diff_line)
    end
  end

  return lines
end

--- Extract commit message from buffer (excluding comments)
---@param bufnr number
---@return string[]
local function extract_message(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local message = {}

  for _, line in ipairs(lines) do
    -- Skip comment lines
    if not line:match("^#") then
      table.insert(message, line)
    end
  end

  -- Trim trailing empty lines
  while #message > 0 and message[#message] == "" do
    table.remove(message)
  end

  return message
end

--- Close the commit editor and return to status view
local function close_editor()
  if not active_editor then
    return
  end

  local bufnr = active_editor.bufnr
  local repo_state = active_editor.repo_state
  active_editor = nil

  -- First, mark the buffer as not modified to avoid "unsaved changes" warnings
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modified = false
  end

  -- Return to status view first (before deleting buffer)
  if repo_state then
    local status_view = require("gitlad.ui.views.status")
    status_view.open(repo_state)
  end

  -- Defer buffer deletion to avoid issues when called from a keymap on that buffer
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  end
end

--- Confirm and execute the commit
local function do_commit()
  if not active_editor then
    return
  end

  local message = extract_message(active_editor.bufnr)

  -- Check for empty message
  if #message == 0 then
    vim.notify("[gitlad] Aborting commit due to empty message", vim.log.levels.WARN)
    return
  end

  local repo_state = active_editor.repo_state
  local args = active_editor.args

  -- Close editor first
  close_editor()

  -- Execute commit
  git.commit(message, args, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Commit created", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Commit failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Abort the commit
local function abort_commit()
  close_editor()
  vim.notify("[gitlad] Commit aborted", vim.log.levels.INFO)
end

--- Set up keymaps for the commit editor buffer
---@param bufnr number
local function setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true }

  -- C-c C-c to commit
  vim.keymap.set(
    "n",
    "<C-c><C-c>",
    do_commit,
    vim.tbl_extend("force", opts, { desc = "Confirm commit" })
  )
  vim.keymap.set("i", "<C-c><C-c>", function()
    vim.cmd("stopinsert")
    do_commit()
  end, vim.tbl_extend("force", opts, { desc = "Confirm commit" }))

  -- C-c C-k to abort
  vim.keymap.set(
    "n",
    "<C-c><C-k>",
    abort_commit,
    vim.tbl_extend("force", opts, { desc = "Abort commit" })
  )
  vim.keymap.set("i", "<C-c><C-k>", function()
    vim.cmd("stopinsert")
    abort_commit()
  end, vim.tbl_extend("force", opts, { desc = "Abort commit" }))

  -- q to abort (when not in insert mode)
  vim.keymap.set("n", "q", abort_commit, vim.tbl_extend("force", opts, { desc = "Abort commit" }))
end

--- Open the commit editor
---@param repo_state RepoState
---@param args string[] Extra git commit arguments (from popup switches/options)
function M.open(repo_state, args)
  -- Close any existing editor
  if active_editor then
    close_editor()
  end

  -- Check if this is an amend
  local amend = false
  for _, arg in ipairs(args) do
    if arg == "--amend" then
      amend = true
      break
    end
  end

  -- Check if verbose mode
  local verbose = false
  for _, arg in ipairs(args) do
    if arg == "--verbose" then
      verbose = true
      break
    end
  end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "gitlad://COMMIT_EDITMSG")
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "gitcommit"

  -- Initialize state
  active_editor = {
    bufnr = bufnr,
    winnr = nil,
    repo_state = repo_state,
    args = args,
    amend = amend,
  }

  -- Set up keymaps
  setup_keymaps(bufnr)

  -- Open in current window
  vim.api.nvim_set_current_buf(bufnr)
  active_editor.winnr = vim.api.nvim_get_current_win()

  -- Load initial content asynchronously
  local function load_content(initial_message)
    if verbose then
      get_verbose_diff(repo_state.repo_root, true, function(diff_lines)
        vim.schedule(function()
          if not active_editor or active_editor.bufnr ~= bufnr then
            return
          end
          local content = build_buffer_content(initial_message or {}, diff_lines)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
          -- Position cursor at start
          vim.api.nvim_win_set_cursor(active_editor.winnr, { 1, 0 })
          vim.bo[bufnr].modified = false
        end)
      end)
    else
      vim.schedule(function()
        if not active_editor or active_editor.bufnr ~= bufnr then
          return
        end
        local content = build_buffer_content(initial_message or {}, nil)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
        -- Position cursor at start
        vim.api.nvim_win_set_cursor(active_editor.winnr, { 1, 0 })
        vim.bo[bufnr].modified = false
      end)
    end
  end

  if amend then
    get_amend_message(repo_state.repo_root, function(message)
      load_content(message)
    end)
  else
    load_content({})
  end
end

--- Check if commit editor is currently open
---@return boolean
function M.is_open()
  return active_editor ~= nil
end

--- Close the commit editor (for external use)
function M.close()
  close_editor()
end

return M
