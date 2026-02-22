---@mod gitlad.ui.views.diff.panel File panel sidebar for native diff viewer
---@brief [[
--- A file panel sidebar that lists changed files from a DiffSpec.
--- Provides navigation between files and a selection indicator.
--- Pure render function (_render_file_list) is testable without vim.
---@brief ]]

local M = {}

-- =============================================================================
-- Type Definitions
-- =============================================================================

---@class DiffFilePair
---@field old_path string
---@field new_path string
---@field status string "M"|"A"|"D"|"R"|"C"
---@field hunks DiffSideBySideHunk[]
---@field additions number
---@field deletions number
---@field is_binary boolean

---@class DiffPanelLineInfo
---@field type "header"|"separator"|"file"|"commit_all"|"commit"
---@field file_index number|nil Index into file_pairs (for "file" type)
---@field commit_index number|nil Index into pr_info.commits (for "commit" type)

---@class DiffPanelRenderResult
---@field lines string[]
---@field line_info table<number, DiffPanelLineInfo>

---@class DiffPanelOpts
---@field width number|nil Panel width (default: 35)
---@field on_select_file fun(index: number)|nil Callback when file is selected
---@field on_select_commit fun(index: number|nil)|nil Callback when commit is selected (nil = all changes)
---@field on_close fun()|nil Callback when panel is closed

---@class DiffPanel
---@field bufnr number Buffer number
---@field winnr number Window number
---@field line_map table<number, DiffPanelLineInfo> Maps line number to metadata
---@field selected_file number Currently selected file index (1-based)
---@field file_pairs DiffFilePair[] Current file pairs
---@field on_select_file fun(index: number) Callback when file is selected
---@field on_select_commit fun(index: number|nil) Callback when commit is selected (nil = all)
---@field on_close fun() Callback when panel is closed
---@field width number Panel width
---@field pr_info DiffPRInfo|nil PR info for commit section
---@field selected_commit number|nil Currently selected commit index (nil = all changes)
local DiffPanel = {}
DiffPanel.__index = DiffPanel

-- =============================================================================
-- Pure Render Function (testable without vim)
-- =============================================================================

--- Truncate a path to fit within a given width, showing just the filename if needed
---@param path string File path
---@param max_width number Maximum display width
---@return string truncated Truncated path
local function truncate_path(path, max_width)
  if #path <= max_width then
    return path
  end

  -- Extract just the filename
  local filename = path:match("[^/]+$") or path
  if #filename <= max_width then
    return filename
  end

  -- Even filename is too long, truncate it
  if max_width > 3 then
    return filename:sub(1, max_width - 3) .. "..."
  end
  return filename:sub(1, max_width)
end

--- Format diff stats for a file pair
---@param pair DiffFilePair
---@return string stats Formatted stats like "+10 -3"
local function format_stats(pair)
  if pair.is_binary then
    return "binary"
  end

  local parts = {}
  if pair.additions > 0 then
    table.insert(parts, "+" .. pair.additions)
  end
  if pair.deletions > 0 then
    table.insert(parts, "-" .. pair.deletions)
  end

  return table.concat(parts, " ")
end

--- Get the display path for a file pair
---@param pair DiffFilePair
---@return string path
local function get_display_path(pair)
  if pair.status == "R" and pair.old_path ~= pair.new_path then
    return pair.old_path .. " -> " .. pair.new_path
  end
  return pair.new_path ~= "" and pair.new_path or pair.old_path
end

--- Format diff stats for a commit
---@param commit DiffPRCommit
---@return string stats Formatted stats like "+10 -3"
local function format_commit_stats(commit)
  local parts = {}
  if commit.additions > 0 then
    table.insert(parts, "+" .. commit.additions)
  end
  if commit.deletions > 0 then
    table.insert(parts, "-" .. commit.deletions)
  end
  return table.concat(parts, " ")
end

--- Truncate a commit message to fit within a given width
---@param msg string Commit message headline
---@param max_width number Maximum display width
---@return string truncated
local function truncate_message(msg, max_width)
  if #msg <= max_width then
    return msg
  end
  if max_width > 3 then
    return msg:sub(1, max_width - 3) .. "..."
  end
  return msg:sub(1, max_width)
end

--- Pure render function for file list, with optional PR commit section
---@param file_pairs DiffFilePair[]
---@param selected_index number Currently selected file (1-based)
---@param width number Panel width
---@param pr_info DiffPRInfo|nil PR info for commit section (nil = no commit section)
---@param selected_commit number|nil Currently selected commit index (nil = all changes)
---@return DiffPanelRenderResult
function M._render_file_list(file_pairs, selected_index, width, pr_info, selected_commit)
  local lines = {}
  local line_info = {}

  local separator = " " .. string.rep("\xe2\x94\x80", width - 2)

  -- Commit section (only when pr_info is provided)
  if pr_info and pr_info.commits and #pr_info.commits > 0 then
    -- Commits header
    local commits_header = " Commits (" .. #pr_info.commits .. ")"
    table.insert(lines, commits_header)
    line_info[#lines] = { type = "header" }

    -- Separator
    table.insert(lines, separator)
    line_info[#lines] = { type = "separator" }

    -- "All changes" entry
    local all_icon = (selected_commit == nil) and "\xe2\x97\x86" or "\xe2\x97\x87"
    local all_indicator = (selected_commit == nil) and "\xe2\x96\xb8" or " "
    local all_line = all_indicator .. all_icon .. " All changes"
    table.insert(lines, all_line)
    line_info[#lines] = { type = "commit_all" }

    -- Individual commit entries
    for i, commit in ipairs(pr_info.commits) do
      local icon = (selected_commit == i) and "\xe2\x97\x8f" or "\xe2\x97\x8b"
      local indicator = (selected_commit == i) and "\xe2\x96\xb8" or " "
      local stats = format_commit_stats(commit)

      -- Layout: [indicator][icon] [short_oid] [message] [stats]
      -- Icon is 3 bytes, indicator is 1 or 3 bytes, short_oid is 7 chars
      local fixed_width = 4 + 8 + #stats -- indicator(1) + icon(1) + space(1) + oid(7) + space(1) + stats
      if #stats > 0 then
        fixed_width = fixed_width + 1 -- extra space before stats
      end
      local msg_width = width - fixed_width
      if msg_width < 3 then
        msg_width = 3
      end

      local msg = truncate_message(commit.message_headline, msg_width)
      local msg_padding = ""
      local stats_section = ""
      if #stats > 0 then
        local pad_len = msg_width - #msg
        if pad_len > 0 then
          msg_padding = string.rep(" ", pad_len)
        end
        stats_section = " " .. stats
      end

      local commit_line = indicator
        .. icon
        .. " "
        .. commit.short_oid
        .. " "
        .. msg
        .. msg_padding
        .. stats_section
      table.insert(lines, commit_line)
      line_info[#lines] = { type = "commit", commit_index = i }
    end

    -- Separator between commits and files
    table.insert(lines, separator)
    line_info[#lines] = { type = "separator" }
  end

  -- Files header line
  local header = " Files (" .. #file_pairs .. ")"
  table.insert(lines, header)
  line_info[#lines] = { type = "header" }

  -- Separator line
  table.insert(lines, separator)
  line_info[#lines] = { type = "separator" }

  -- File lines
  for i, pair in ipairs(file_pairs) do
    -- Indicator: triangle for selected, space for others
    local indicator = (i == selected_index) and "\xe2\x96\xb8" or " "

    -- Status character
    local status = pair.status

    -- Stats
    local stats = format_stats(pair)

    -- Calculate available width for path
    -- Layout: [indicator][status] [path]  [stats]
    -- indicator=1 char (but multi-byte), status=1 char, spaces=3, stats=variable
    local fixed_width = 4 + #stats -- indicator(1) + status(1) + spaces(2+trailing)
    if #stats > 0 then
      fixed_width = fixed_width + 1 -- extra space before stats
    end
    local path_width = width - fixed_width
    if path_width < 5 then
      path_width = 5
    end

    local path = get_display_path(pair)
    local display_path = truncate_path(path, path_width)

    -- Build the line
    -- Layout: [indicator][status] [path][padding][stats]
    local path_padding = ""
    local stats_section = ""
    if #stats > 0 then
      local pad_len = path_width - #display_path
      if pad_len > 0 then
        path_padding = string.rep(" ", pad_len)
      end
      stats_section = " " .. stats
    end

    local line = indicator .. status .. " " .. display_path .. path_padding .. stats_section
    table.insert(lines, line)
    line_info[#lines] = { type = "file", file_index = i }
  end

  return { lines = lines, line_info = line_info }
end

-- =============================================================================
-- DiffPanel Methods (require vim)
-- =============================================================================

--- Create a new DiffPanel
---@param winnr number Window number to use
---@param opts DiffPanelOpts|nil
---@return DiffPanel
function M.new(winnr, opts)
  opts = opts or {}

  local self = setmetatable({}, DiffPanel)
  self.winnr = winnr
  self.width = opts.width or 35
  self.on_select_file = opts.on_select_file or function() end
  self.on_select_commit = opts.on_select_commit or function() end
  self.on_close = opts.on_close or function() end
  self.file_pairs = {}
  self.selected_file = 1
  self.line_map = {}
  self.pr_info = nil
  self.selected_commit = nil

  -- Create a scratch buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "wipe"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].modifiable = false
  vim.bo[self.bufnr].filetype = "gitlad-diff-panel"

  -- Set window options
  local win_opts = { win = winnr, scope = "local" }
  vim.api.nvim_set_option_value("number", false, win_opts)
  vim.api.nvim_set_option_value("signcolumn", "no", win_opts)
  vim.api.nvim_set_option_value("wrap", false, win_opts)
  vim.api.nvim_set_option_value("winfixwidth", true, win_opts)
  vim.api.nvim_set_option_value("cursorline", true, win_opts)

  -- Set buffer in window
  vim.api.nvim_win_set_buf(winnr, self.bufnr)

  -- Set up keymaps
  self:_setup_keymaps()

  return self
end

--- Render the file list from file_pairs
---@param file_pairs DiffFilePair[]
---@param pr_info DiffPRInfo|nil Optional PR info for commit section
---@param selected_commit number|nil Currently selected commit index
function DiffPanel:render(file_pairs, pr_info, selected_commit)
  self.file_pairs = file_pairs
  if pr_info ~= nil then
    self.pr_info = pr_info
  end
  if selected_commit ~= nil or pr_info ~= nil then
    self.selected_commit = selected_commit
  end

  -- Clamp selected_file to valid range
  if self.selected_file < 1 then
    self.selected_file = 1
  end
  if self.selected_file > #file_pairs then
    self.selected_file = math.max(1, #file_pairs)
  end

  local result = M._render_file_list(
    file_pairs,
    self.selected_file,
    self.width,
    self.pr_info,
    self.selected_commit
  )

  -- Update line_map (1-indexed for cursor positions)
  self.line_map = result.line_info

  -- Set buffer content
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, result.lines)
  vim.bo[self.bufnr].modifiable = false

  -- Apply highlights
  self:_apply_highlights(result)
end

--- Apply syntax highlighting to rendered content
---@param result DiffPanelRenderResult
function DiffPanel:_apply_highlights(result)
  local ok, hl = pcall(require, "gitlad.ui.hl")
  if not ok then
    return
  end

  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  for i, line in ipairs(result.lines) do
    local info = result.line_info[i]
    if not info then
      goto continue
    end

    local line_idx = i - 1 -- 0-indexed

    if info.type == "header" then
      hl.set(self.bufnr, ns, line_idx, 0, #line, "GitladSectionHeader")
    elseif info.type == "separator" then
      hl.set(self.bufnr, ns, line_idx, 0, #line, "Comment")
    elseif info.type == "commit_all" then
      -- Highlight "All changes" entry
      if self.selected_commit == nil then
        hl.set_line(self.bufnr, ns, line_idx, "CursorLine")
      end
      hl.set(self.bufnr, ns, line_idx, 0, #line, "GitladSectionHeader")
    elseif info.type == "commit" and info.commit_index then
      -- Highlight commit entry
      if self.selected_commit == info.commit_index then
        hl.set_line(self.bufnr, ns, line_idx, "CursorLine")
      end

      -- Highlight short OID
      local oid_start = line:find("%x%x%x%x%x%x%x")
      if oid_start then
        hl.set(self.bufnr, ns, line_idx, oid_start - 1, oid_start - 1 + 7, "GitladHash")
      end

      -- Highlight diff stats
      local add_start, add_end = line:find("%+%d+")
      if add_start then
        hl.set(self.bufnr, ns, line_idx, add_start - 1, add_end, "GitladForgePRAdditions")
      end
      local del_start, del_end = line:find("%-%d+", add_end or 1)
      if del_start then
        hl.set(self.bufnr, ns, line_idx, del_start - 1, del_end, "GitladForgePRDeletions")
      end
    elseif info.type == "file" and info.file_index then
      local pair = self.file_pairs[info.file_index]
      if not pair then
        goto continue
      end

      -- Highlight selected file line
      if info.file_index == self.selected_file then
        hl.set_line(self.bufnr, ns, line_idx, "CursorLine")
      end

      -- Highlight status character (position 1 after the indicator)
      -- The indicator is a multi-byte char (3 bytes for triangle, 1 for space)
      local status_byte_offset
      if info.file_index == self.selected_file then
        -- Triangle indicator is 3 bytes
        status_byte_offset = 3
      else
        -- Space indicator is 1 byte
        status_byte_offset = 1
      end

      local status_hl_map = {
        M = "GitladFileModified",
        A = "GitladFileAdded",
        D = "GitladFileDeleted",
        R = "GitladFileRenamed",
        C = "GitladFileCopied",
      }
      local status_hl = status_hl_map[pair.status] or "GitladFileStatus"
      hl.set(self.bufnr, ns, line_idx, status_byte_offset, status_byte_offset + 1, status_hl)

      -- Highlight diff stats (+N and -N)
      local add_start, add_end = line:find("%+%d+")
      if add_start and not pair.is_binary then
        hl.set(self.bufnr, ns, line_idx, add_start - 1, add_end, "GitladForgePRAdditions")
      end

      local del_start, del_end = line:find("%-%d+", add_end or 1)
      if del_start and not pair.is_binary then
        hl.set(self.bufnr, ns, line_idx, del_start - 1, del_end, "GitladForgePRDeletions")
      end

      -- Highlight "binary" text
      if pair.is_binary then
        local bin_start, bin_end = line:find("binary")
        if bin_start then
          hl.set(self.bufnr, ns, line_idx, bin_start - 1, bin_end, "Comment")
        end
      end
    end

    ::continue::
  end
end

--- Select a file by index and notify callback
---@param index number 1-based file index
function DiffPanel:select_file(index)
  if index < 1 or index > #self.file_pairs then
    return
  end

  self.selected_file = index
  self:render(self.file_pairs)

  -- Find the target line from line_map (avoids hardcoding offset)
  for line_nr, info in pairs(self.line_map) do
    if info.type == "file" and info.file_index == index then
      if vim.api.nvim_win_is_valid(self.winnr) then
        vim.api.nvim_win_set_cursor(self.winnr, { line_nr, 0 })
      end
      break
    end
  end

  self.on_select_file(index)
end

--- Set up buffer keymaps
function DiffPanel:_setup_keymaps()
  local keymap = require("gitlad.utils.keymap")
  local bufnr = self.bufnr

  -- Navigation
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_file()
  end, "Next file")

  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_file()
  end, "Previous file")

  -- Select file
  keymap.set(bufnr, "n", "<CR>", function()
    self:_select_file_at_cursor()
  end, "Select file")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self.on_close()
  end, "Close diff view")
end

--- Check if a line info represents a navigable entry (file, commit, or commit_all)
---@param info DiffPanelLineInfo|nil
---@return boolean
local function is_navigable(info)
  if not info then
    return false
  end
  return info.type == "file" or info.type == "commit" or info.type == "commit_all"
end

--- Navigate to the next navigable entry (file or commit)
function DiffPanel:_goto_next_file()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local current_line = cursor[1]
  local line_count = vim.api.nvim_buf_line_count(self.bufnr)

  for line = current_line + 1, line_count do
    if is_navigable(self.line_map[line]) then
      vim.api.nvim_win_set_cursor(self.winnr, { line, 0 })
      return
    end
  end
end

--- Navigate to the previous navigable entry (file or commit)
function DiffPanel:_goto_prev_file()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    if is_navigable(self.line_map[line]) then
      vim.api.nvim_win_set_cursor(self.winnr, { line, 0 })
      return
    end
  end
end

--- Select the file or commit at the current cursor position
function DiffPanel:_select_file_at_cursor()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local line = cursor[1]
  local info = self.line_map[line]

  if not info then
    return
  end

  if info.type == "file" and info.file_index then
    self:select_file(info.file_index)
  elseif info.type == "commit_all" then
    self.on_select_commit(nil)
  elseif info.type == "commit" and info.commit_index then
    self.on_select_commit(info.commit_index)
  end
end

--- Destroy the panel and clean up
function DiffPanel:destroy()
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
  self.bufnr = nil
  self.winnr = nil
  self.line_map = {}
  self.file_pairs = {}
end

return M
