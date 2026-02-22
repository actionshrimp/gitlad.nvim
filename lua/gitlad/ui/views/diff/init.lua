---@mod gitlad.ui.views.diff DiffView coordinator for native side-by-side diff viewer
---@brief [[
--- Manages the entire diff viewing experience: a tab page with a file panel sidebar
--- on the left and two synchronized side-by-side buffers (old/new) on the right.
---
--- Opens via M.open(diff_spec), which creates a new tab page with 3 windows:
---   [panel | left_diff | right_diff]
---
--- Only one DiffView is active at a time. Opening a new one closes the previous.
---@brief ]]

local M = {}

local buffer_mod = require("gitlad.ui.views.diff.buffer")
local panel_mod = require("gitlad.ui.views.diff.panel")
local content = require("gitlad.ui.views.diff.content")
local keymap = require("gitlad.utils.keymap")

-- The single active DiffView instance (only one at a time)
local active_view = nil

-- =============================================================================
-- DiffView class
-- =============================================================================

---@class DiffView
---@field diff_spec DiffSpec Current diff spec
---@field panel DiffPanel File panel sidebar
---@field buffer_pair DiffBufferPair Side-by-side buffers
---@field tab_page number Tab page number
---@field selected_file number Currently displayed file index (1-based)
---@field _closed boolean Whether the view has been closed
---@field _autocmd_id number|nil Autocmd ID for tab close detection
local DiffView = {}
DiffView.__index = DiffView

--- Create and open a DiffView from a DiffSpec.
--- Creates a new tab page with panel + side-by-side layout.
---@param diff_spec DiffSpec The diff specification to display
---@return DiffView
function DiffView._new(diff_spec)
  local self = setmetatable({}, DiffView)
  self.diff_spec = diff_spec
  self.selected_file = 0
  self._closed = false
  self._autocmd_id = nil
  return self
end

--- Set up the tab page layout and create panel + buffer pair.
function DiffView:_setup_layout()
  -- Create a new tab page
  vim.cmd("tabnew")
  self.tab_page = vim.api.nvim_get_current_tabpage()

  -- We start with a single window. Split it to create 3 panes:
  -- [panel | left | right]
  local right_winnr = vim.api.nvim_get_current_win()

  -- Create left diff window by splitting right
  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()

  -- Create panel window to the left of everything
  vim.cmd("aboveleft vsplit")
  local panel_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(panel_winnr, 35)

  -- Create the panel with callbacks
  self.panel = panel_mod.new(panel_winnr, {
    width = 35,
    on_select_file = function(index)
      self:select_file(index)
    end,
    on_close = function()
      self:close()
    end,
  })

  -- Create the buffer pair
  self.buffer_pair = buffer_mod.new(left_winnr, right_winnr)

  -- Set up keymaps on both diff buffers
  self:_setup_keymaps()

  -- Set up autocmd to detect when tab is closed externally
  self._autocmd_id = vim.api.nvim_create_autocmd("TabClosed", {
    callback = function()
      -- Check if our tab page still exists
      if self._closed then
        return true -- Already closing, remove autocmd
      end
      local tabs = vim.api.nvim_list_tabpages()
      local found = false
      for _, tab in ipairs(tabs) do
        if tab == self.tab_page then
          found = true
          break
        end
      end
      if not found then
        vim.schedule(function()
          self:_on_tab_closed()
        end)
        return true -- Remove autocmd
      end
    end,
  })
end

--- Render the panel and select the first file (or show empty message).
function DiffView:_render_initial()
  local file_pairs = self.diff_spec.file_pairs

  -- Render the panel
  self.panel:render(file_pairs)

  if #file_pairs > 0 then
    -- Select the first file
    self:select_file(1)
  else
    -- No files: show a message in the diff buffers
    self:_show_empty_message()
  end
end

--- Display the file at the given index in the side-by-side buffers.
---@param index number 1-based file index
function DiffView:select_file(index)
  local file_pairs = self.diff_spec.file_pairs
  if index < 1 or index > #file_pairs then
    return
  end

  local file_pair = file_pairs[index]
  local aligned = content.align_sides(file_pair)
  self.buffer_pair:set_content(aligned, file_pair.new_path)
  self.selected_file = index

  -- Update panel selection (render with new selection)
  self.panel.selected_file = index
  self.panel:render(file_pairs)
end

--- Navigate to the next file in the file list.
function DiffView:next_file()
  local count = #self.diff_spec.file_pairs
  if count == 0 then
    return
  end
  local next = self.selected_file + 1
  if next > count then
    next = 1 -- Wrap around
  end
  self:select_file(next)
end

--- Navigate to the previous file in the file list.
function DiffView:prev_file()
  local count = #self.diff_spec.file_pairs
  if count == 0 then
    return
  end
  local prev = self.selected_file - 1
  if prev < 1 then
    prev = count -- Wrap around
  end
  self:select_file(prev)
end

--- Navigate to the next hunk boundary within the current file.
function DiffView:goto_next_hunk()
  if not self.buffer_pair or not self.buffer_pair.line_map then
    return
  end

  -- Get current cursor position from whichever diff buffer is active
  local current_line = 1
  local current_win = vim.api.nvim_get_current_win()
  if current_win == self.buffer_pair.left_winnr or current_win == self.buffer_pair.right_winnr then
    current_line = vim.api.nvim_win_get_cursor(current_win)[1]
  end

  -- Find the next hunk boundary after current line
  for i, info in ipairs(self.buffer_pair.line_map) do
    if info.is_hunk_boundary and i > current_line then
      -- Move cursor in the active diff window
      if vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_win_set_cursor(current_win, { i, 0 })
      end
      return
    end
  end
end

--- Navigate to the previous hunk boundary within the current file.
function DiffView:goto_prev_hunk()
  if not self.buffer_pair or not self.buffer_pair.line_map then
    return
  end

  local current_line = 1
  local current_win = vim.api.nvim_get_current_win()
  if current_win == self.buffer_pair.left_winnr or current_win == self.buffer_pair.right_winnr then
    current_line = vim.api.nvim_win_get_cursor(current_win)[1]
  end

  -- Find the previous hunk boundary before current line
  for i = #self.buffer_pair.line_map, 1, -1 do
    local info = self.buffer_pair.line_map[i]
    if info.is_hunk_boundary and i < current_line then
      if vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_win_set_cursor(current_win, { i, 0 })
      end
      return
    end
  end
end

--- Show a message in the diff buffers when there are no changes.
function DiffView:_show_empty_message()
  local msg = { "", "  No changes" }

  -- Unlock, set, re-lock left buffer
  vim.bo[self.buffer_pair.left_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.buffer_pair.left_bufnr, 0, -1, false, msg)
  vim.bo[self.buffer_pair.left_bufnr].modifiable = false

  -- Unlock, set, re-lock right buffer
  vim.bo[self.buffer_pair.right_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.buffer_pair.right_bufnr, 0, -1, false, msg)
  vim.bo[self.buffer_pair.right_bufnr].modifiable = false
end

--- Set up keymaps on both diff buffers.
function DiffView:_setup_keymaps()
  for _, bufnr in ipairs({ self.buffer_pair.left_bufnr, self.buffer_pair.right_bufnr }) do
    keymap.set(bufnr, "n", "q", function()
      self:close()
    end, "Close diff view")

    keymap.set(bufnr, "n", "gj", function()
      self:next_file()
    end, "Next file")

    keymap.set(bufnr, "n", "gk", function()
      self:prev_file()
    end, "Previous file")

    keymap.set(bufnr, "n", "]c", function()
      self:goto_next_hunk()
    end, "Next hunk")

    keymap.set(bufnr, "n", "[c", function()
      self:goto_prev_hunk()
    end, "Previous hunk")

    keymap.set(bufnr, "n", "gr", function()
      self:refresh()
    end, "Refresh diff")
  end
end

--- Refresh the diff view by re-running the source producer.
function DiffView:refresh()
  local source = self.diff_spec.source
  local repo_root = self.diff_spec.repo_root
  local src = require("gitlad.ui.views.diff.source")

  local function on_result(spec, err)
    if err then
      vim.schedule(function()
        vim.notify("[gitlad] Refresh failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    if spec then
      vim.schedule(function()
        if self._closed then
          return
        end
        self.diff_spec = spec

        -- Remember current file selection
        local prev_selected = self.selected_file

        -- Re-render panel
        self.panel:render(spec.file_pairs)

        -- Re-select same file index (clamped)
        if #spec.file_pairs > 0 then
          local idx = math.min(prev_selected, #spec.file_pairs)
          if idx < 1 then
            idx = 1
          end
          self:select_file(idx)
        else
          self:_show_empty_message()
        end
      end)
    end
  end

  if source.type == "staged" then
    src.produce_staged(repo_root, on_result)
  elseif source.type == "unstaged" then
    src.produce_unstaged(repo_root, on_result)
  elseif source.type == "worktree" then
    src.produce_worktree(repo_root, on_result)
  elseif source.type == "commit" then
    src.produce_commit(repo_root, source.ref, on_result)
  elseif source.type == "range" then
    src.produce_range(repo_root, source.range, on_result)
  elseif source.type == "stash" then
    src.produce_stash(repo_root, source.ref, on_result)
  end
end

--- Close the entire diff view, cleaning up all resources.
function DiffView:close()
  if self._closed then
    return
  end
  self._closed = true

  -- Remove autocmd
  if self._autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self._autocmd_id)
    self._autocmd_id = nil
  end

  -- Destroy panel and buffer pair
  if self.panel then
    self.panel:destroy()
  end
  if self.buffer_pair then
    self.buffer_pair:destroy()
  end

  -- Close the tab page if it still exists and is not the only tab
  if self.tab_page and vim.api.nvim_tabpage_is_valid(self.tab_page) then
    local tabs = vim.api.nvim_list_tabpages()
    if #tabs > 1 then
      -- Switch to the tab first, then close it
      vim.api.nvim_set_current_tabpage(self.tab_page)
      vim.cmd("tabclose")
    end
  end

  -- Clear the active view reference
  if active_view == self then
    active_view = nil
  end
end

--- Handle external tab closure (user closed the tab directly).
function DiffView:_on_tab_closed()
  if self._closed then
    return
  end
  self._closed = true

  -- Remove autocmd
  if self._autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self._autocmd_id)
    self._autocmd_id = nil
  end

  -- Destroy panel and buffer pair (buffers may already be gone)
  if self.panel then
    pcall(function()
      self.panel:destroy()
    end)
  end
  if self.buffer_pair then
    pcall(function()
      self.buffer_pair:destroy()
    end)
  end

  if active_view == self then
    active_view = nil
  end
end

-- =============================================================================
-- Module-level API
-- =============================================================================

--- Open a diff viewer for the given DiffSpec.
--- Creates a new tab page with file panel + side-by-side diff buffers.
--- Closes any existing diff view first.
---@param diff_spec DiffSpec The diff specification to display
---@return DiffView
function M.open(diff_spec)
  -- Close any existing diff view
  if active_view then
    active_view:close()
  end

  local view = DiffView._new(diff_spec)
  view:_setup_layout()
  view:_render_initial()

  active_view = view
  return view
end

--- Close the currently active diff view, if any.
function M.close()
  if active_view then
    active_view:close()
  end
end

--- Get the currently active DiffView, if any.
---@return DiffView|nil
function M.get_active()
  return active_view
end

--- Clear the active view reference (for testing).
function M._clear()
  if active_view then
    active_view:close()
  end
  active_view = nil
end

return M
