---@mod gitlad.ui.views.status Status buffer view
---@brief [[
--- Main status buffer showing staged, unstaged, and untracked files.
---@brief ]]

local M = {}

local state = require("gitlad.state")
local config = require("gitlad.config")
local history_view = require("gitlad.ui.views.history")
local git = require("gitlad.git")

---@class LineInfo
---@field path string File path
---@field section "staged"|"unstaged"|"untracked"|"conflicted" Section type

---@class SectionInfo
---@field name string Section name
---@field section "staged"|"unstaged"|"untracked"|"conflicted" Section type

---@class StatusBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field line_map table<number, LineInfo> Map of line numbers to file info
---@field section_lines table<number, SectionInfo> Map of line numbers to section headers
---@field expanded_files table<string, boolean> Map of "section:path" to expanded state
---@field diff_cache table<string, string[]> Map of "section:path" to diff lines
local StatusBuffer = {}
StatusBuffer.__index = StatusBuffer

-- Active status buffers by repo root
local status_buffers = {}

--- Create or get a status buffer for a repository
---@param repo_state RepoState
---@return StatusBuffer
local function get_or_create_buffer(repo_state)
  local key = repo_state.repo_root

  if status_buffers[key] and vim.api.nvim_buf_is_valid(status_buffers[key].bufnr) then
    return status_buffers[key]
  end

  local self = setmetatable({}, StatusBuffer)
  self.repo_state = repo_state
  self.line_map = {} -- Maps line numbers to file info
  self.section_lines = {} -- Maps line numbers to section headers
  self.expanded_files = {} -- Tracks which files have diffs expanded
  self.diff_cache = {} -- Caches fetched diff lines

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://status")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Listen for status updates
  repo_state:on("status", function()
    vim.schedule(function()
      self:render()
    end)
  end)

  status_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function StatusBuffer:_setup_keymaps()
  local opts = { buffer = self.bufnr, silent = true }

  -- Staging single file
  vim.keymap.set("n", "s", function()
    self:_stage_current()
  end, vim.tbl_extend("force", opts, { desc = "Stage file" }))

  vim.keymap.set("n", "u", function()
    self:_unstage_current()
  end, vim.tbl_extend("force", opts, { desc = "Unstage file" }))

  -- Staging all
  vim.keymap.set("n", "S", function()
    self:_stage_all()
  end, vim.tbl_extend("force", opts, { desc = "Stage all" }))

  vim.keymap.set("n", "U", function()
    self:_unstage_all()
  end, vim.tbl_extend("force", opts, { desc = "Unstage all" }))

  -- Discard
  vim.keymap.set("n", "x", function()
    self:_discard_current()
  end, vim.tbl_extend("force", opts, { desc = "Discard changes" }))

  -- Refresh
  vim.keymap.set("n", "g", function()
    self.repo_state:refresh_status(true)
  end, vim.tbl_extend("force", opts, { desc = "Refresh status" }))

  -- Close
  vim.keymap.set("n", "q", function()
    self:close()
  end, vim.tbl_extend("force", opts, { desc = "Close status" }))

  -- Navigation
  vim.keymap.set("n", "n", function()
    self:_goto_next_file()
  end, vim.tbl_extend("force", opts, { desc = "Next file" }))

  vim.keymap.set("n", "p", function()
    self:_goto_prev_file()
  end, vim.tbl_extend("force", opts, { desc = "Previous file" }))

  vim.keymap.set("n", "<M-n>", function()
    self:_goto_next_section()
  end, vim.tbl_extend("force", opts, { desc = "Next section" }))

  vim.keymap.set("n", "<M-p>", function()
    self:_goto_prev_section()
  end, vim.tbl_extend("force", opts, { desc = "Previous section" }))

  -- Visit file
  vim.keymap.set("n", "<CR>", function()
    self:_visit_file()
  end, vim.tbl_extend("force", opts, { desc = "Visit file" }))

  -- Diff toggle
  vim.keymap.set("n", "<Tab>", function()
    self:_toggle_diff()
  end, vim.tbl_extend("force", opts, { desc = "Toggle diff" }))

  -- Git command history
  vim.keymap.set("n", "$", function()
    history_view.open()
  end, vim.tbl_extend("force", opts, { desc = "Show git command history" }))

  -- Help
  vim.keymap.set("n", "?", function()
    self:_show_help()
  end, vim.tbl_extend("force", opts, { desc = "Show help" }))
end

--- Get the file path at the current cursor position
---@return string|nil path
---@return string|nil section "staged"|"unstaged"|"untracked"|"conflicted"
function StatusBuffer:_get_current_file()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info then
    return info.path, info.section
  end

  return nil, nil
end

--- Stage the file under cursor
function StatusBuffer:_stage_current()
  local path, section = self:_get_current_file()
  if not path then
    return
  end

  if section == "unstaged" or section == "untracked" then
    self.repo_state:stage(path, section)
  end
end

--- Unstage the file under cursor
function StatusBuffer:_unstage_current()
  local path, section = self:_get_current_file()
  if not path then
    return
  end

  if section == "staged" then
    self.repo_state:unstage(path)
  end
end

--- Get the cache key for a file's diff
---@param path string
---@param section string
---@return string
local function diff_cache_key(path, section)
  return section .. ":" .. path
end

--- Filter out git diff header lines, keeping only the actual diff content
---@param lines string[]
---@return string[]
local function filter_diff_header(lines)
  local result = {}
  local in_hunk = false

  for _, line in ipairs(lines) do
    -- Start including lines once we hit the first hunk header
    if line:match("^@@") then
      in_hunk = true
    end
    if in_hunk then
      table.insert(result, line)
    end
  end

  return result
end

--- Read file content and format as "added" lines
---@param path string Full path to file
---@param callback fun(lines: string[]|nil, err: string|nil)
local function read_file_as_added(path, callback)
  vim.schedule(function()
    local file = io.open(path, "r")
    if not file then
      callback(nil, "Could not read file")
      return
    end

    local lines = {}
    for line in file:lines() do
      table.insert(lines, "+" .. line)
    end
    file:close()

    callback(lines, nil)
  end)
end

--- Toggle diff view for current file
function StatusBuffer:_toggle_diff()
  local path, section = self:_get_current_file()
  if not path then
    return
  end

  local key = diff_cache_key(path, section)

  -- Toggle expanded state
  if self.expanded_files[key] then
    -- Collapse
    self.expanded_files[key] = false
    self:render()
    return
  end

  -- Expand - check if diff is cached
  if self.diff_cache[key] then
    self.expanded_files[key] = true
    self:render()
    return
  end

  -- Untracked files: read the full file content
  if section == "untracked" then
    local full_path = self.repo_state.repo_root .. path
    read_file_as_added(full_path, function(lines, err)
      if err then
        vim.notify("[gitlad] Read error: " .. err, vim.log.levels.ERROR)
        return
      end

      vim.schedule(function()
        self.diff_cache[key] = lines or {}
        self.expanded_files[key] = true
        self:render()
      end)
    end)
    return
  end

  -- Fetch the diff for staged/unstaged files
  local staged = (section == "staged")
  git.diff(path, staged, { cwd = self.repo_state.repo_root }, function(diff_lines, err)
    if err then
      vim.notify("[gitlad] Diff error: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      -- Filter out the diff header, keep only the actual diff
      self.diff_cache[key] = filter_diff_header(diff_lines or {})
      self.expanded_files[key] = true
      self:render()
    end)
  end)
end

--- Navigate to next file entry
function StatusBuffer:_goto_next_file()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(self.bufnr)

  for line = current_line + 1, total_lines do
    if self.line_map[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous file entry
function StatusBuffer:_goto_prev_file()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    if self.line_map[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to next section header
function StatusBuffer:_goto_next_section()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(self.bufnr)

  for line = current_line + 1, total_lines do
    if self.section_lines[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous section header
function StatusBuffer:_goto_prev_section()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    if self.section_lines[line] then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Visit the file at cursor
function StatusBuffer:_visit_file()
  local path = self:_get_current_file()
  if not path then
    return
  end

  local full_path = self.repo_state.repo_root .. path
  -- Close status and open file
  self:close()
  vim.cmd("edit " .. vim.fn.fnameescape(full_path))
end

--- Stage all unstaged and untracked files
function StatusBuffer:_stage_all()
  self.repo_state:stage_all()
end

--- Unstage all staged files
function StatusBuffer:_unstage_all()
  self.repo_state:unstage_all()
end

--- Discard changes for file at cursor
function StatusBuffer:_discard_current()
  local path, section = self:_get_current_file()
  if not path then
    return
  end

  if section == "staged" then
    vim.notify("[gitlad] Cannot discard staged changes. Unstage first.", vim.log.levels.WARN)
    return
  end

  if section == "untracked" then
    -- Confirm deletion of untracked file
    vim.ui.select({ "Yes", "No" }, {
      prompt = string.format("Delete untracked file '%s'?", path),
    }, function(choice)
      if choice == "Yes" then
        self.repo_state:discard(path, section)
      end
    end)
  else
    -- Confirm discard of changes
    vim.ui.select({ "Yes", "No" }, {
      prompt = string.format("Discard changes to '%s'?", path),
    }, function(choice)
      if choice == "Yes" then
        self.repo_state:discard(path, section)
      end
    end)
  end
end

--- Show help popup
function StatusBuffer:_show_help()
  local help_lines = {
    "Gitlad Status - Keybindings",
    "",
    "Navigation:",
    "  n      Next file",
    "  p      Previous file",
    "  M-n    Next section",
    "  M-p    Previous section",
    "",
    "Staging:",
    "  s      Stage file at cursor",
    "  u      Unstage file at cursor",
    "  S      Stage all",
    "  U      Unstage all",
    "",
    "Actions:",
    "  <CR>   Visit file",
    "  x      Discard changes",
    "  <Tab>  Toggle inline diff",
    "",
    "Other:",
    "  g      Refresh",
    "  $      Git command history",
    "  q      Close",
    "  ?      This help",
  }

  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.bo[buf].modifiable = false

  local width = 35
  local height = #help_lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
  })

  -- Close on any key
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })

  vim.keymap.set("n", "?", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
end

--- Render the status buffer
function StatusBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local status = self.repo_state.status
  if not status then
    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "Loading..." })
    return
  end

  local cfg = config.get()
  local lines = {}
  self.line_map = {} -- Reset line map
  self.section_lines = {} -- Reset section lines

  -- Helper to add a section header and track its line number
  local function add_section_header(name, section, count)
    table.insert(lines, string.format("%s (%d)", name, count))
    self.section_lines[#lines] = { name = name, section = section }
  end

  -- Helper to add a file entry and track its line number
  local function add_file_line(entry, section, sign, status_char, use_display)
    local display = use_display
        and entry.orig_path
        and string.format("%s -> %s", entry.orig_path, entry.path)
      or entry.path

    -- Check if this file is expanded
    local key = diff_cache_key(entry.path, section)
    local is_expanded = self.expanded_files[key]
    local expand_indicator = is_expanded and "v" or ">"

    local line_text = status_char
        and string.format("  %s %s %s %s", expand_indicator, sign, status_char, display)
      or string.format("  %s %s   %s", expand_indicator, sign, display)
    table.insert(lines, line_text)
    self.line_map[#lines] = { path = entry.path, section = section }

    -- Add diff lines if expanded
    if is_expanded and self.diff_cache[key] then
      for _, diff_line in ipairs(self.diff_cache[key]) do
        table.insert(lines, "    " .. diff_line)
        -- Diff lines also map to the same file
        self.line_map[#lines] = { path = entry.path, section = section }
      end
    end
  end

  -- Header
  local head_line = string.format("Head:     %s", status.branch)
  if self.repo_state.refreshing then
    head_line = head_line .. "  (Refreshing...)"
  end
  table.insert(lines, head_line)
  if status.upstream then
    local ahead_behind = ""
    if status.ahead > 0 or status.behind > 0 then
      ahead_behind = string.format(" [+%d/-%d]", status.ahead, status.behind)
    end
    table.insert(lines, string.format("Upstream: %s%s", status.upstream, ahead_behind))
  end
  table.insert(lines, "")

  -- Staged changes
  if #status.staged > 0 then
    add_section_header("Staged", "staged", #status.staged)
    for _, entry in ipairs(status.staged) do
      add_file_line(entry, "staged", cfg.signs.staged, entry.index_status, true)
    end
    table.insert(lines, "")
  end

  -- Unstaged changes
  if #status.unstaged > 0 then
    add_section_header("Unstaged", "unstaged", #status.unstaged)
    for _, entry in ipairs(status.unstaged) do
      add_file_line(entry, "unstaged", cfg.signs.unstaged, entry.worktree_status, false)
    end
    table.insert(lines, "")
  end

  -- Untracked files
  if #status.untracked > 0 then
    add_section_header("Untracked", "untracked", #status.untracked)
    for _, entry in ipairs(status.untracked) do
      add_file_line(entry, "untracked", cfg.signs.untracked, nil, false)
    end
    table.insert(lines, "")
  end

  -- Conflicted files
  if #status.conflicted > 0 then
    add_section_header("Conflicted", "conflicted", #status.conflicted)
    for _, entry in ipairs(status.conflicted) do
      add_file_line(entry, "conflicted", cfg.signs.conflict, nil, false)
    end
    table.insert(lines, "")
  end

  -- Clean working tree message
  if
    #status.staged == 0
    and #status.unstaged == 0
    and #status.untracked == 0
    and #status.conflicted == 0
  then
    table.insert(lines, "Nothing to commit, working tree clean")
  end

  -- Help line
  table.insert(lines, "")
  table.insert(lines, "s=stage  u=unstage  g=refresh  $=history  q=close")

  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
end

--- Open the status buffer in a window
function StatusBuffer:open()
  -- Check if already open in a window
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    return
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Initial render
  self:render()

  -- Trigger refresh
  self.repo_state:refresh_status()
end

--- Close the status buffer
function StatusBuffer:close()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = nil
    return
  end

  -- Check if this is the last window
  local windows = vim.api.nvim_list_wins()
  if #windows == 1 then
    -- Can't close last window, switch to an empty buffer instead
    local empty_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(self.winnr, empty_buf)
  else
    vim.api.nvim_win_close(self.winnr, false)
  end

  self.winnr = nil
end

--- Open status view for current repository
function M.open()
  local repo_state = state.get()
  if not repo_state then
    vim.notify("[gitlad] Not in a git repository", vim.log.levels.WARN)
    return
  end

  local buf = get_or_create_buffer(repo_state)
  buf:open()
end

--- Close status view
function M.close()
  local repo_state = state.get()
  if not repo_state then
    return
  end

  local key = repo_state.repo_root
  local buf = status_buffers[key]
  if buf then
    buf:close()
  end
end

--- Clear all status buffers (useful for testing)
function M.clear_all()
  for _, buf in pairs(status_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  status_buffers = {}
end

return M
