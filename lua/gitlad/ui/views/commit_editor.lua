---@mod gitlad.ui.views.commit_editor Commit message editor buffer
---@brief [[
--- Buffer for editing commit messages with magit-style keybindings.
--- C-c C-c to confirm, C-c C-k to abort.
---@brief ]]

local M = {}

local git = require("gitlad.git")
local config = require("gitlad.config")
local keymap_util = require("gitlad.utils.keymap")

---@class CommitEditorState
---@field bufnr number Buffer number
---@field winnr number|nil Window number
---@field repo_state RepoState
---@field args string[] Extra git commit arguments
---@field amend boolean Whether this is an amend
---@field verbose_diff string[]|nil Diff lines for verbose mode
---@field opened_in_split boolean Whether the editor was opened in a split

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

--- Get the staged files summary
---@param repo_root string
---@param callback fun(lines: string[]|nil)
local function get_staged_files_summary(repo_root, callback)
  local cli = require("gitlad.git.cli")
  -- Use git diff --cached --name-status for a nice summary
  cli.run_async({ "diff", "--cached", "--name-status" }, { cwd = repo_root }, function(result)
    if result.code == 0 and #result.stdout > 0 then
      -- Format: "A\tfilename" or "M\tfilename" etc.
      -- Convert to readable format
      local lines = {}
      for _, line in ipairs(result.stdout) do
        local status, path = line:match("^(%S+)%s+(.+)$")
        if status and path then
          local status_text
          if status == "A" then
            status_text = "new file"
          elseif status == "M" then
            status_text = "modified"
          elseif status == "D" then
            status_text = "deleted"
          elseif status == "R" then
            status_text = "renamed"
          elseif status == "C" then
            status_text = "copied"
          elseif status:match("^R%d+") then
            -- Rename with percentage (e.g., R100)
            status_text = "renamed"
          elseif status:match("^C%d+") then
            status_text = "copied"
          else
            status_text = status
          end
          table.insert(lines, string.format("        %s:   %s", status_text, path))
        end
      end
      callback(lines)
    else
      callback(nil)
    end
  end)
end

--- Create the commit editor buffer content
---@param message_lines string[] Initial message lines
---@param staged_files string[]|nil Summary of staged files
---@param verbose_diff string[]|nil Diff for verbose mode
---@return string[]
local function build_buffer_content(message_lines, staged_files, verbose_diff)
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

  -- Add staged files summary
  if staged_files and #staged_files > 0 then
    table.insert(lines, "#")
    table.insert(lines, "# Changes to be committed:")
    for _, file_line in ipairs(staged_files) do
      table.insert(lines, "#" .. file_line)
    end
  end

  -- Add verbose diff if requested
  if verbose_diff and #verbose_diff > 0 then
    table.insert(lines, "#")
    table.insert(lines, "# Diff:")
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
  local winnr = active_editor.winnr
  local repo_state = active_editor.repo_state
  local opened_in_split = active_editor.opened_in_split
  active_editor = nil

  -- First, mark the buffer as not modified to avoid "unsaved changes" warnings
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modified = false
  end

  -- Switch away from the editor buffer synchronously so that subsequent
  -- keypresses land in the correct buffer (avoids race with vim.schedule)
  if opened_in_split and winnr and vim.api.nvim_win_is_valid(winnr) then
    -- Close the split window (this won't close the last window since status is still there)
    vim.api.nvim_win_close(winnr, true)
  else
    -- If we replaced the buffer, switch back to status view
    if repo_state then
      local status_view = require("gitlad.ui.views.status")
      status_view.open(repo_state)
    end
  end

  -- Defer only buffer deletion to avoid issues when called from a keymap on that buffer
  vim.schedule(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)
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

  -- Execute commit with streaming output viewer (shows hook progress)
  git.commit_streaming(message, args, { cwd = repo_state.repo_root }, function(success, err)
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
  -- C-c C-c to commit
  keymap_util.set(bufnr, "n", "<C-c><C-c>", do_commit, "Confirm commit")
  keymap_util.set(bufnr, "i", "<C-c><C-c>", function()
    vim.cmd("stopinsert")
    do_commit()
  end, "Confirm commit")

  -- C-c C-k to abort
  keymap_util.set(bufnr, "n", "<C-c><C-k>", abort_commit, "Abort commit")
  keymap_util.set(bufnr, "i", "<C-c><C-k>", function()
    vim.cmd("stopinsert")
    abort_commit()
  end, "Abort commit")

  -- ZZ to commit (vim convention, matches rebase editor)
  keymap_util.set(bufnr, "n", "ZZ", do_commit, "Confirm commit")

  -- ZQ to abort (vim convention, matches rebase editor)
  keymap_util.set(bufnr, "n", "ZQ", abort_commit, "Abort commit")

  -- q to abort (when not in insert mode)
  keymap_util.set(bufnr, "n", "q", abort_commit, "Abort commit")
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

  -- Get split configuration
  local cfg = config.get()
  local split_mode = cfg.commit_editor and cfg.commit_editor.split or "above"
  local opened_in_split = split_mode == "above"

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
    opened_in_split = opened_in_split,
  }

  -- Set up keymaps
  setup_keymaps(bufnr)

  -- Open in split above or current window based on config
  if opened_in_split then
    vim.cmd("aboveleft split")
    vim.api.nvim_set_current_buf(bufnr)
  else
    vim.api.nvim_set_current_buf(bufnr)
  end
  active_editor.winnr = vim.api.nvim_get_current_win()

  -- Load initial content asynchronously
  -- First get staged files summary, then optionally get verbose diff
  local function load_content(initial_message)
    get_staged_files_summary(repo_state.repo_root, function(staged_files)
      if verbose then
        get_verbose_diff(repo_state.repo_root, true, function(diff_lines)
          vim.schedule(function()
            if not active_editor or active_editor.bufnr ~= bufnr then
              return
            end
            local content = build_buffer_content(initial_message or {}, staged_files, diff_lines)
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
          local content = build_buffer_content(initial_message or {}, staged_files, nil)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
          -- Position cursor at start
          vim.api.nvim_win_set_cursor(active_editor.winnr, { 1, 0 })
          vim.bo[bufnr].modified = false
        end)
      end
    end)
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
