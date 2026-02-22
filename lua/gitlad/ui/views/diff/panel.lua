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
---@field type "header"|"separator"|"file"
---@field file_index number|nil Index into file_pairs (for "file" type)

---@class DiffPanelRenderResult
---@field lines string[]
---@field line_info table<number, DiffPanelLineInfo>

---@class DiffPanelOpts
---@field width number|nil Panel width (default: 35)
---@field on_select_file fun(index: number)|nil Callback when file is selected
---@field on_close fun()|nil Callback when panel is closed

---@class DiffPanel
---@field bufnr number Buffer number
---@field winnr number Window number
---@field line_map table<number, DiffPanelLineInfo> Maps line number to metadata
---@field selected_file number Currently selected file index (1-based)
---@field file_pairs DiffFilePair[] Current file pairs
---@field on_select_file fun(index: number) Callback when file is selected
---@field on_close fun() Callback when panel is closed
---@field width number Panel width
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

--- Pure render function for file list
---@param file_pairs DiffFilePair[]
---@param selected_index number Currently selected file (1-based)
---@param width number Panel width
---@return DiffPanelRenderResult
function M._render_file_list(file_pairs, selected_index, width)
  local lines = {}
  local line_info = {}

  -- Header line
  local header = " Files (" .. #file_pairs .. ")"
  table.insert(lines, header)
  line_info[#lines] = { type = "header", file_index = nil }

  -- Separator line
  local separator = " " .. string.rep("\xe2\x94\x80", width - 2)
  table.insert(lines, separator)
  line_info[#lines] = { type = "separator", file_index = nil }

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
  self.on_close = opts.on_close or function() end
  self.file_pairs = {}
  self.selected_file = 1
  self.line_map = {}

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
function DiffPanel:render(file_pairs)
  self.file_pairs = file_pairs

  -- Clamp selected_file to valid range
  if self.selected_file < 1 then
    self.selected_file = 1
  end
  if self.selected_file > #file_pairs then
    self.selected_file = math.max(1, #file_pairs)
  end

  local result = M._render_file_list(file_pairs, self.selected_file, self.width)

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

  -- Move cursor to the selected file line
  -- File lines start at line 3 (after header + separator)
  local target_line = 2 + index
  if vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_win_set_cursor(self.winnr, { target_line, 0 })
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

--- Navigate to the next file entry
function DiffPanel:_goto_next_file()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local current_line = cursor[1]
  local line_count = vim.api.nvim_buf_line_count(self.bufnr)

  for line = current_line + 1, line_count do
    local info = self.line_map[line]
    if info and info.type == "file" then
      vim.api.nvim_win_set_cursor(self.winnr, { line, 0 })
      return
    end
  end
end

--- Navigate to the previous file entry
function DiffPanel:_goto_prev_file()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    local info = self.line_map[line]
    if info and info.type == "file" then
      vim.api.nvim_win_set_cursor(self.winnr, { line, 0 })
      return
    end
  end
end

--- Select the file at the current cursor position
function DiffPanel:_select_file_at_cursor()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local line = cursor[1]
  local info = self.line_map[line]

  if info and info.type == "file" and info.file_index then
    self:select_file(info.file_index)
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
