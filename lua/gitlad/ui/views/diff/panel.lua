---@mod gitlad.ui.views.diff.panel File panel sidebar for native diff viewer
---@brief [[
--- A file panel sidebar that lists changed files from a DiffSpec.
--- Provides navigation between files and a selection indicator.
--- Pure render function (_render_file_list) is testable without vim.
---@brief ]]

local M = {}

--- Try to get a file type icon from nvim-web-devicons (optional dependency)
---@param filename string
---@return string|nil icon
---@return string|nil hl_name Highlight group name
local function get_devicon(filename)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    return nil, nil
  end
  return devicons.get_icon(filename, nil, { default = true })
end

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
---@field type "header"|"separator"|"file"|"commit_all"|"commit"|"dir"
---@field file_index number|nil Index into file_pairs (for "file" type)
---@field commit_index number|nil Index into pr_info.commits (for "commit" type)
---@field icon_hl string|nil Highlight group for file type icon (from nvim-web-devicons)
---@field icon_byte_offset number|nil Byte offset of the icon in the line
---@field dir_path string|nil For "dir" type, path used as collapse key
---@field depth number|nil Tree depth for file entries (used for highlight offsets)

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
---@field collapsed_dirs table<string, boolean> Map of dir paths to collapsed state
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

--- Get the display name for a file in tree mode (basename, or old_base -> new_base for renames)
---@param pair DiffFilePair
---@param entry_name string Basename from tree entry
---@return string
local function get_tree_display_name(pair, entry_name)
  if pair.status == "R" and pair.old_path ~= pair.new_path then
    local old_base = pair.old_path:match("[^/]+$") or pair.old_path
    local new_base = pair.new_path:match("[^/]+$") or pair.new_path
    if old_base ~= new_base then
      return old_base .. " -> " .. new_base
    end
  end
  return entry_name
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
---@param icon_fn (fun(filename: string): string|nil, string|nil)|nil Returns icon, hl_name
---@param collapsed_dirs table<string, boolean>|nil Map of dir paths to collapsed state
---@return DiffPanelRenderResult
function M._render_file_list(
  file_pairs,
  selected_index,
  width,
  pr_info,
  selected_commit,
  icon_fn,
  collapsed_dirs
)
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

  -- File lines (tree-structured)
  local diff_tree = require("gitlad.ui.views.diff.tree")
  local root = diff_tree.build_tree(file_pairs)
  local flat_entries = diff_tree.flatten(root, collapsed_dirs or {})

  for _, entry in ipairs(flat_entries) do
    if entry.type == "dir" then
      -- Render directory line: [space][indent][fold_icon] [dirname]
      local indent = string.rep("  ", entry.depth)
      local fold_icon = entry.is_collapsed and "\xe2\x96\xb8" or "\xe2\x96\xbe"
      local dir_line = " " .. indent .. fold_icon .. " " .. entry.name
      table.insert(lines, dir_line)
      line_info[#lines] = { type = "dir", dir_path = entry.path }
    else
      -- Render file line: [indicator][indent][status] [icon ][name][padding][stats]
      local pair = file_pairs[entry.file_index]
      local indent = string.rep("  ", entry.depth)
      local indent_width = entry.depth * 2

      local indicator = (entry.file_index == selected_index) and "\xe2\x96\xb8" or " "
      local status = pair.status
      local stats = format_stats(pair)

      -- Display name: basename, or "old_base -> new_base" for renames
      local display_name = get_tree_display_name(pair, entry.name)

      -- Resolve file type icon (optional)
      local icon, icon_hl
      if icon_fn then
        local fname = (pair.new_path ~= "" and pair.new_path or pair.old_path):match("[^/]+$")
          or entry.name
        icon, icon_hl = icon_fn(fname)
      end

      -- Calculate available width for name
      -- Layout: [indicator(1)][indent][status(1)] [icon(1) ][name]  [stats]
      local icon_extra = icon and 2 or 0
      local fixed_width = 4 + indent_width + icon_extra + #stats
      if #stats > 0 then
        fixed_width = fixed_width + 1
      end
      local name_width = width - fixed_width
      if name_width < 5 then
        name_width = 5
      end

      local truncated_name = truncate_path(display_name, name_width)

      -- Build the line
      local icon_section = ""
      local icon_byte_offset_val
      if icon then
        local indicator_bytes = (entry.file_index == selected_index) and 3 or 1
        icon_byte_offset_val = indicator_bytes + indent_width + 1 + 1 -- + status + space
        icon_section = icon .. " "
      end

      local name_padding = ""
      local stats_section = ""
      if #stats > 0 then
        local pad_len = name_width - #truncated_name
        if pad_len > 0 then
          name_padding = string.rep(" ", pad_len)
        end
        stats_section = " " .. stats
      end

      local file_line = indicator
        .. indent
        .. status
        .. " "
        .. icon_section
        .. truncated_name
        .. name_padding
        .. stats_section
      table.insert(lines, file_line)
      local file_info = { type = "file", file_index = entry.file_index, depth = entry.depth }
      if icon and icon_hl then
        file_info.icon_hl = icon_hl
        file_info.icon_byte_offset = icon_byte_offset_val
      end
      line_info[#lines] = file_info
    end
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
  self.collapsed_dirs = {}

  -- Create a scratch buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "wipe"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].modifiable = false
  vim.bo[self.bufnr].filetype = "gitlad-diff-panel"

  -- Set buffer in window BEFORE window options (nvim_win_set_buf triggers
  -- autocmds like BufWinEnter/FileType that can reset window-local options)
  vim.api.nvim_win_set_buf(winnr, self.bufnr)

  -- Set window options after buffer is in place
  local win_opts = { win = winnr, scope = "local" }
  vim.api.nvim_set_option_value("number", false, win_opts)
  vim.api.nvim_set_option_value("signcolumn", "no", win_opts)
  vim.api.nvim_set_option_value("wrap", false, win_opts)
  vim.api.nvim_set_option_value("winfixwidth", true, win_opts)
  vim.api.nvim_set_option_value("cursorline", true, win_opts)

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
    self.selected_commit,
    get_devicon,
    self.collapsed_dirs
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
    elseif info.type == "dir" then
      hl.set(self.bufnr, ns, line_idx, 0, #line, "Directory")
    elseif info.type == "file" and info.file_index then
      local pair = self.file_pairs[info.file_index]
      if not pair then
        goto continue
      end

      -- Highlight selected file line
      if info.file_index == self.selected_file then
        hl.set_line(self.bufnr, ns, line_idx, "CursorLine")
      end

      -- Highlight status character (after indicator + indent)
      local indent_bytes = (info.depth or 0) * 2
      local status_byte_offset
      if info.file_index == self.selected_file then
        -- Triangle indicator is 3 bytes
        status_byte_offset = 3 + indent_bytes
      else
        -- Space indicator is 1 byte
        status_byte_offset = 1 + indent_bytes
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

      -- Highlight file type icon (from nvim-web-devicons)
      if info.icon_hl and info.icon_byte_offset then
        -- Most devicons are 3-byte UTF-8 characters
        local icon_start = info.icon_byte_offset
        local icon_text = line:sub(icon_start + 1, icon_start + 4) -- grab up to 4 bytes
        local icon_len = #(icon_text:match("^[^\128-\191][\128-\191]*") or "")
        if icon_len == 0 then
          icon_len = 3
        end
        hl.set(self.bufnr, ns, line_idx, icon_start, icon_start + icon_len, info.icon_hl)
      end

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

  -- Select file / toggle directory
  keymap.set(bufnr, "n", "<CR>", function()
    self:_select_file_at_cursor()
  end, "Select file / Toggle directory")

  -- Toggle directory collapse
  keymap.set(bufnr, "n", "<Tab>", function()
    self:_toggle_dir_at_cursor()
  end, "Toggle directory")

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

  if info.type == "dir" and info.dir_path then
    self.collapsed_dirs[info.dir_path] = not self.collapsed_dirs[info.dir_path]
    self:render(self.file_pairs)
  elseif info.type == "file" and info.file_index then
    self:select_file(info.file_index)
  elseif info.type == "commit_all" then
    self.on_select_commit(nil)
  elseif info.type == "commit" and info.commit_index then
    self.on_select_commit(info.commit_index)
  end
end

--- Toggle directory collapse at the current cursor position
function DiffPanel:_toggle_dir_at_cursor()
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winnr)
  local line = cursor[1]
  local info = self.line_map[line]

  if info and info.type == "dir" and info.dir_path then
    self.collapsed_dirs[info.dir_path] = not self.collapsed_dirs[info.dir_path]
    self:render(self.file_pairs)
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
