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
local save_mod = require("gitlad.ui.views.diff.save")
local keymap = require("gitlad.utils.keymap")

--- Check if a source type supports editable buffers.
---@param source_type DiffSourceType
---@return boolean
local function is_editable_source(source_type)
  return source_type == "staged"
    or source_type == "unstaged"
    or source_type == "worktree"
    or source_type == "three_way"
end

-- The single active DiffView instance (only one at a time)
local active_view = nil

-- =============================================================================
-- DiffView class
-- =============================================================================

---@class DiffView
---@field diff_spec DiffSpec Current diff spec
---@field panel DiffPanel File panel sidebar
---@field buffer_pair DiffBufferPair|nil Side-by-side buffers (2-pane mode)
---@field buffer_triple DiffBufferTriple|nil Triple buffers (3-pane mode)
---@field three_way boolean Whether this is a 3-way view
---@field tab_page number Tab page number
---@field selected_file number Currently displayed file index (1-based)
---@field provider ForgeProvider|nil Forge provider (for PR review)
---@field pr_number number|nil PR number (for PR review)
---@field review_state ReviewState|nil Review thread state (PR mode only)
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
  self.three_way = false
  self.buffer_triple = nil
  self._closed = false
  self._autocmd_id = nil
  return self
end

--- Set up the tab page layout and create panel + buffer pair.
function DiffView:_setup_layout()
  -- Create a new tab page
  vim.cmd("tabnew")
  self.tab_page = vim.api.nvim_get_current_tabpage()

  -- Set tab label to the diff spec title
  vim.api.nvim_tabpage_set_var(self.tab_page, "gitlad_label", self.diff_spec.title)

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
    on_select_commit = function(index)
      self:select_commit(index)
    end,
    on_close = function()
      self:close()
    end,
  })

  -- Create the buffer pair (editable for local diff sources)
  local editable = is_editable_source(self.diff_spec.source.type)
  self.buffer_pair = buffer_mod.new(left_winnr, right_winnr, { editable = editable })

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

--- Set up the tab page layout for 3-way view: [panel | left | mid | right].
function DiffView:_setup_layout_three_way()
  local buffer_triple_mod = require("gitlad.ui.views.diff.buffer_triple")

  -- Create a new tab page
  vim.cmd("tabnew")
  self.tab_page = vim.api.nvim_get_current_tabpage()

  -- Set tab label
  vim.api.nvim_tabpage_set_var(self.tab_page, "gitlad_label", self.diff_spec.title)

  -- We start with a single window. Split to create 4 panes:
  -- [panel | left | mid | right]
  local right_winnr = vim.api.nvim_get_current_win()

  -- Create mid window by splitting right
  vim.cmd("vsplit")
  local mid_winnr = vim.api.nvim_get_current_win()

  -- Create left window by splitting mid
  vim.cmd("vsplit")
  local left_winnr = vim.api.nvim_get_current_win()

  -- Create panel window to the left of everything
  vim.cmd("aboveleft vsplit")
  local panel_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(panel_winnr, 35)

  -- Set winbar labels for the three diff panes
  local source_type = self.diff_spec.source.type
  local left_label, mid_label, right_label
  if source_type == "merge" then
    left_label = " OURS"
    mid_label = " WORKTREE"
    right_label = " THEIRS"
  else
    left_label = " HEAD"
    mid_label = " INDEX"
    right_label = " WORKTREE"
  end
  vim.api.nvim_set_option_value("winbar", left_label, { win = left_winnr, scope = "local" })
  vim.api.nvim_set_option_value("winbar", mid_label, { win = mid_winnr, scope = "local" })
  vim.api.nvim_set_option_value("winbar", right_label, { win = right_winnr, scope = "local" })

  -- Create the panel with callbacks
  self.panel = panel_mod.new(panel_winnr, {
    width = 35,
    on_select_file = function(index)
      self:select_file(index)
    end,
    on_select_commit = function() end,
    on_close = function()
      self:close()
    end,
  })

  -- Create the buffer triple with appropriate editability mode
  local editable_mode = "none"
  if source_type == "three_way" then
    editable_mode = "mid_and_right"
  elseif source_type == "merge" then
    editable_mode = "mid_only"
  end
  self.buffer_triple =
    buffer_triple_mod.new(left_winnr, mid_winnr, right_winnr, { editable = editable_mode })

  -- Set up keymaps on all 3 diff buffers
  self:_setup_keymaps()

  -- Set up autocmd to detect when tab is closed externally
  self._autocmd_id = vim.api.nvim_create_autocmd("TabClosed", {
    callback = function()
      if self._closed then
        return true
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
        return true
      end
    end,
  })
end

--- Find the file index matching a given path
---@param file_pairs DiffFilePair[] File pairs to search
---@param path string File path to match
---@return number|nil index 1-based index of the matching file, or nil if not found
function DiffView._find_file_index(file_pairs, path)
  if not path or path == "" then
    return nil
  end
  for i, pair in ipairs(file_pairs) do
    if pair.new_path == path or pair.old_path == path then
      return i
    end
  end
  return nil
end

--- Render the panel and select the initial file (or show empty message).
---@param initial_file string|nil Optional file path to auto-select
function DiffView:_render_initial(initial_file)
  local file_pairs = self.diff_spec.file_pairs
  local source = self.diff_spec.source

  -- Render the panel (with PR info if available)
  local pr_info = source.pr_info
  local selected_commit = source.selected_commit
  self.panel:render(file_pairs, pr_info, selected_commit)

  if #file_pairs > 0 then
    -- Determine which file to select
    local target_index = 1
    if initial_file then
      local found = DiffView._find_file_index(file_pairs, initial_file)
      if found then
        target_index = found
      end
    end
    self:select_file(target_index)
  else
    -- No files: show a message in the diff buffers
    self:_show_empty_message()
  end

  -- Fetch review threads for PR diffs (async, overlays applied when ready)
  if self.provider and self.pr_number then
    self:_fetch_review_threads()
  end
end

--- Display the file at the given index in the diff buffers.
---@param index number 1-based file index
function DiffView:select_file(index)
  local file_pairs = self.diff_spec.file_pairs
  if index < 1 or index > #file_pairs then
    return
  end

  -- Guard: prompt if switching to a different file with unsaved changes
  if index ~= self.selected_file and self:_has_unsaved_changes() then
    if not self:_prompt_unsaved("Switch files") then
      return
    end
  end

  if self.three_way then
    -- 3-way mode: use three_way alignment
    local three_way_mod = require("gitlad.ui.views.diff.three_way")
    local three_way_files = self.diff_spec.three_way_files
    if three_way_files and three_way_files[index] then
      local aligned = three_way_mod.align_three_way(three_way_files[index])
      self.buffer_triple:set_content(aligned, file_pairs[index].new_path)
      self.buffer_triple:apply_folds(aligned.line_map)
    end
  else
    -- 2-pane mode: use standard alignment
    local file_pair = file_pairs[index]
    local aligned = content.align_sides(file_pair)
    self.buffer_pair:set_content(aligned, file_pair.new_path)

    -- Apply review overlays if we have review state
    self:_apply_review_overlays(file_pair.new_path)
  end

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

--- Select a commit within a PR diff view.
--- Re-runs the diff producer for the selected commit and updates the view.
---@param index number|nil Index into pr_info.commits (nil = all changes)
function DiffView:select_commit(index)
  local source = self.diff_spec.source
  if source.type ~= "pr" or not source.pr_info then
    return
  end

  -- Don't re-select the same commit
  if index == source.selected_commit then
    return
  end

  local src = require("gitlad.ui.views.diff.source")
  local repo_root = self.diff_spec.repo_root
  local pr_info = source.pr_info

  src.produce_pr(repo_root, pr_info, index, function(spec, err)
    if err then
      vim.schedule(function()
        vim.notify("[gitlad] Failed to load commit diff: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    if spec then
      vim.schedule(function()
        if self._closed then
          return
        end
        self.diff_spec = spec

        -- Re-render panel with new commit selection
        self.panel:render(spec.file_pairs, pr_info, index)

        -- Select first file
        if #spec.file_pairs > 0 then
          self:select_file(1)
        else
          self:_show_empty_message()
        end
      end)
    end
  end)
end

--- Navigate to the next commit in PR mode.
function DiffView:next_commit()
  local source = self.diff_spec.source
  if source.type ~= "pr" or not source.pr_info then
    return
  end

  local commits = source.pr_info.commits
  if not commits or #commits == 0 then
    return
  end

  local current = source.selected_commit
  local next_idx
  if current == nil then
    -- Currently on "All changes" -> go to first commit
    next_idx = 1
  elseif current >= #commits then
    -- On last commit -> wrap to "All changes"
    next_idx = nil
  else
    next_idx = current + 1
  end

  self:select_commit(next_idx)
end

--- Navigate to the previous commit in PR mode.
function DiffView:prev_commit()
  local source = self.diff_spec.source
  if source.type ~= "pr" or not source.pr_info then
    return
  end

  local commits = source.pr_info.commits
  if not commits or #commits == 0 then
    return
  end

  local current = source.selected_commit
  local prev_idx
  if current == nil then
    -- Currently on "All changes" -> wrap to last commit
    prev_idx = #commits
  elseif current <= 1 then
    -- On first commit -> go to "All changes"
    prev_idx = nil
  else
    prev_idx = current - 1
  end

  self:select_commit(prev_idx)
end

--- Get the current line_map from whichever buffer mode is active.
---@return ThreeWayLineInfo[]|AlignedLineInfo[]|nil
function DiffView:_get_line_map()
  if self.three_way then
    return self.buffer_triple and self.buffer_triple.line_map
  else
    return self.buffer_pair and self.buffer_pair.line_map
  end
end

--- Check if the current window is one of the diff buffer windows.
---@param win number Window handle
---@return boolean
function DiffView:_is_diff_window(win)
  if self.three_way then
    return self.buffer_triple
      and (
        win == self.buffer_triple.left_winnr
        or win == self.buffer_triple.mid_winnr
        or win == self.buffer_triple.right_winnr
      )
  else
    return self.buffer_pair
      and (win == self.buffer_pair.left_winnr or win == self.buffer_pair.right_winnr)
  end
end

--- Navigate to the next hunk boundary within the current file.
function DiffView:goto_next_hunk()
  local line_map = self:_get_line_map()
  if not line_map then
    return
  end

  local current_line = 1
  local current_win = vim.api.nvim_get_current_win()
  if self:_is_diff_window(current_win) then
    current_line = vim.api.nvim_win_get_cursor(current_win)[1]
  end

  for i, info in ipairs(line_map) do
    if info.is_hunk_boundary and i > current_line then
      if vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_win_set_cursor(current_win, { i, 0 })
      end
      return
    end
  end
end

--- Navigate to the previous hunk boundary within the current file.
function DiffView:goto_prev_hunk()
  local line_map = self:_get_line_map()
  if not line_map then
    return
  end

  local current_line = 1
  local current_win = vim.api.nvim_get_current_win()
  if self:_is_diff_window(current_win) then
    current_line = vim.api.nvim_win_get_cursor(current_win)[1]
  end

  for i = #line_map, 1, -1 do
    local info = line_map[i]
    if info.is_hunk_boundary and i < current_line then
      if vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_win_set_cursor(current_win, { i, 0 })
      end
      return
    end
  end
end

--- Fetch review threads from the provider and populate review_state.
--- Called automatically when a PR diff opens with a provider set.
function DiffView:_fetch_review_threads()
  if not self.provider or not self.pr_number then
    return
  end

  if not self.provider.get_review_threads then
    return
  end

  self.provider:get_review_threads(self.pr_number, function(threads, pr_node_id, err)
    vim.schedule(function()
      if self._closed then
        return
      end
      if err then
        vim.notify("[gitlad] Failed to load review threads: " .. err, vim.log.levels.WARN)
        return
      end
      if not threads then
        return
      end

      local review_mod = require("gitlad.ui.views.diff.review")
      self.review_state = review_mod.new_state()
      self.review_state.threads = threads
      self.review_state.thread_map = review_mod.group_threads_by_path(threads)
      self.review_state.pr_node_id = pr_node_id

      -- Enable signcolumn for review mode
      for _, winnr in ipairs({ self.buffer_pair.left_winnr, self.buffer_pair.right_winnr }) do
        if vim.api.nvim_win_is_valid(winnr) then
          vim.api.nvim_set_option_value("signcolumn", "yes:1", { win = winnr, scope = "local" })
        end
      end

      -- Apply overlays to current file
      local file_pairs = self.diff_spec.file_pairs
      if self.selected_file >= 1 and self.selected_file <= #file_pairs then
        self:_apply_review_overlays(file_pairs[self.selected_file].new_path)
      end
    end)
  end)
end

--- Apply review overlays for a given file path.
---@param file_path string The file path to apply overlays for
function DiffView:_apply_review_overlays(file_path)
  if not self.review_state then
    return
  end

  local review_mod = require("gitlad.ui.views.diff.review")
  local file_threads = self.review_state.thread_map[file_path] or {}

  -- Get pending comments for this file
  local file_pending = {}
  if self.review_state.pending_mode then
    for _, pc in ipairs(self.review_state.pending_comments) do
      if pc.path == file_path then
        table.insert(file_pending, pc)
      end
    end
  end

  self.review_state.file_thread_positions = review_mod.apply_overlays(
    self.buffer_pair,
    file_threads,
    self.buffer_pair.line_map,
    self.review_state.collapsed,
    #file_pending > 0 and file_pending or nil
  )
end

--- Navigate to the next review thread in the current file.
function DiffView:goto_next_thread()
  if not self.review_state or not self.review_state.file_thread_positions then
    return
  end

  local review_mod = require("gitlad.ui.views.diff.review")
  local current_win = vim.api.nvim_get_current_win()
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]

  local next_line =
    review_mod.next_thread_line(self.review_state.file_thread_positions, current_line)
  if next_line then
    vim.api.nvim_win_set_cursor(current_win, { next_line, 0 })
  end
end

--- Navigate to the previous review thread in the current file.
function DiffView:goto_prev_thread()
  if not self.review_state or not self.review_state.file_thread_positions then
    return
  end

  local review_mod = require("gitlad.ui.views.diff.review")
  local current_win = vim.api.nvim_get_current_win()
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]

  local prev_line =
    review_mod.prev_thread_line(self.review_state.file_thread_positions, current_line)
  if prev_line then
    vim.api.nvim_win_set_cursor(current_win, { prev_line, 0 })
  end
end

--- Toggle expand/collapse of the thread at cursor.
function DiffView:toggle_thread_at_cursor()
  if not self.review_state or not self.review_state.file_thread_positions then
    return
  end

  local review_mod = require("gitlad.ui.views.diff.review")
  local current_win = vim.api.nvim_get_current_win()
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]

  local thread = review_mod.thread_at_cursor(self.review_state.file_thread_positions, current_line)
  if not thread then
    return
  end

  -- Toggle collapsed state
  local is_collapsed = self.review_state.collapsed[thread.id]
  if is_collapsed == nil then
    is_collapsed = true -- Default is collapsed
  end
  self.review_state.collapsed[thread.id] = not is_collapsed

  -- Re-apply overlays
  local file_pairs = self.diff_spec.file_pairs
  if self.selected_file >= 1 and self.selected_file <= #file_pairs then
    self:_apply_review_overlays(file_pairs[self.selected_file].new_path)
  end
end

--- Get the current file path and line info at cursor for review operations.
---@return { path: string, lineno: number, side: string }|nil info
function DiffView:_get_review_line_info()
  if not self.buffer_pair or not self.buffer_pair.line_map then
    return nil
  end

  local file_pairs = self.diff_spec.file_pairs
  if self.selected_file < 1 or self.selected_file > #file_pairs then
    return nil
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]
  local info = self.buffer_pair.line_map[current_line]
  if not info then
    return nil
  end

  -- Determine side and line number based on which buffer is active
  local side, lineno
  if current_win == self.buffer_pair.left_winnr then
    side = "LEFT"
    lineno = info.left_lineno
  else
    side = "RIGHT"
    lineno = info.right_lineno
  end

  if not lineno then
    return nil -- Filler line
  end

  return {
    path = file_pairs[self.selected_file].new_path,
    lineno = lineno,
    side = side,
  }
end

--- Add a new review comment at the cursor position.
--- In pending mode, adds to the local pending list instead of submitting.
function DiffView:add_review_comment()
  if not self.provider or not self.pr_number then
    vim.notify("[gitlad] Not in a PR diff view", vim.log.levels.WARN)
    return
  end

  local line_info = self:_get_review_line_info()
  if not line_info then
    vim.notify("[gitlad] No valid line at cursor", vim.log.levels.WARN)
    return
  end

  -- Pending mode: accumulate locally
  if self.review_state and self.review_state.pending_mode then
    local comment_editor = require("gitlad.ui.views.comment_editor")
    local title = string.format("[Pending] Comment on %s:%d", line_info.path, line_info.lineno)

    comment_editor.open({
      title = title,
      on_submit = function(body)
        ---@type PendingComment
        local pc = {
          path = line_info.path,
          line = line_info.lineno,
          side = line_info.side,
          body = body,
        }
        table.insert(self.review_state.pending_comments, pc)
        local count = #self.review_state.pending_comments
        vim.notify(
          string.format("[gitlad] Comment added to pending review (%d total)", count),
          vim.log.levels.INFO
        )
        -- Re-apply overlays to show the pending comment
        local file_pairs = self.diff_spec.file_pairs
        if self.selected_file >= 1 and self.selected_file <= #file_pairs then
          self:_apply_review_overlays(file_pairs[self.selected_file].new_path)
        end
      end,
    })
    return
  end

  -- Immediate mode: submit directly via REST API
  if not self.provider.create_review_comment then
    vim.notify("[gitlad] Provider does not support review comments", vim.log.levels.WARN)
    return
  end

  -- Get the head commit OID for the commit_id parameter
  local source = self.diff_spec.source
  local commit_id
  if source.pr_info then
    if source.selected_commit and source.pr_info.commits then
      local commit = source.pr_info.commits[source.selected_commit]
      if commit then
        commit_id = commit.oid
      end
    end
    if not commit_id then
      commit_id = source.pr_info.head_oid
    end
  end

  if not commit_id then
    vim.notify("[gitlad] Cannot determine commit for review comment", vim.log.levels.WARN)
    return
  end

  local comment_editor = require("gitlad.ui.views.comment_editor")
  local provider = self.provider
  local pr_number = self.pr_number
  local title = string.format("Review comment on %s:%d", line_info.path, line_info.lineno)

  comment_editor.open({
    title = title,
    on_submit = function(body)
      vim.notify("[gitlad] Submitting review comment...", vim.log.levels.INFO)
      provider:create_review_comment(pr_number, {
        body = body,
        path = line_info.path,
        line = line_info.lineno,
        side = line_info.side,
        commit_id = commit_id,
      }, function(_, err)
        vim.schedule(function()
          if err then
            vim.notify("[gitlad] Failed to add comment: " .. err, vim.log.levels.ERROR)
            return
          end
          vim.notify("[gitlad] Review comment added", vim.log.levels.INFO)
          -- Re-fetch threads to show the new comment
          self:_fetch_review_threads()
        end)
      end)
    end,
  })
end

--- Reply to the review thread at the cursor position.
function DiffView:reply_to_thread()
  if not self.provider or not self.pr_number then
    vim.notify("[gitlad] Not in a PR diff view", vim.log.levels.WARN)
    return
  end

  if not self.provider.reply_to_review_comment then
    vim.notify("[gitlad] Provider does not support thread replies", vim.log.levels.WARN)
    return
  end

  if not self.review_state or not self.review_state.file_thread_positions then
    vim.notify("[gitlad] No review threads loaded", vim.log.levels.WARN)
    return
  end

  local review_mod = require("gitlad.ui.views.diff.review")
  local current_win = vim.api.nvim_get_current_win()
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]

  local thread = review_mod.thread_at_cursor(self.review_state.file_thread_positions, current_line)
  if not thread then
    vim.notify("[gitlad] No review thread at cursor", vim.log.levels.WARN)
    return
  end

  -- Find the first comment's database_id to reply to
  if #thread.comments == 0 then
    vim.notify("[gitlad] Thread has no comments to reply to", vim.log.levels.WARN)
    return
  end

  local first_comment = thread.comments[1]
  if not first_comment.database_id then
    vim.notify("[gitlad] Cannot reply: comment has no database ID", vim.log.levels.WARN)
    return
  end

  local comment_editor = require("gitlad.ui.views.comment_editor")
  local provider = self.provider
  local pr_number = self.pr_number
  local title = string.format("Reply to @%s on %s", first_comment.author.login, thread.path)

  comment_editor.open({
    title = title,
    on_submit = function(body)
      vim.notify("[gitlad] Submitting reply...", vim.log.levels.INFO)
      provider:reply_to_review_comment(pr_number, first_comment.database_id, body, function(_, err)
        vim.schedule(function()
          if err then
            vim.notify("[gitlad] Failed to reply: " .. err, vim.log.levels.ERROR)
            return
          end
          vim.notify("[gitlad] Reply added", vim.log.levels.INFO)
          -- Re-fetch threads to show the reply
          self:_fetch_review_threads()
        end)
      end)
    end,
  })
end

--- Open the submit review popup (Approve / Request Changes / Comment).
function DiffView:submit_review()
  if not self.provider or not self.pr_number then
    vim.notify("[gitlad] Not in a PR diff view", vim.log.levels.WARN)
    return
  end

  if not self.provider.submit_review then
    vim.notify("[gitlad] Provider does not support review submission", vim.log.levels.WARN)
    return
  end

  if not self.review_state or not self.review_state.pr_node_id then
    vim.notify("[gitlad] No PR node ID available. Try refreshing.", vim.log.levels.WARN)
    return
  end

  local popup = require("gitlad.ui.popup")
  local comment_editor = require("gitlad.ui.views.comment_editor")
  local provider = self.provider
  local pr_node_id = self.review_state.pr_node_id
  local pending = self.review_state.pending_comments
  local has_pending = #pending > 0

  local function do_submit(event, event_label)
    comment_editor.open({
      title = string.format("Review: %s PR #%d", event_label, self.pr_number),
      on_submit = function(body)
        local function on_complete(_, err)
          vim.schedule(function()
            if err then
              vim.notify("[gitlad] Failed to submit review: " .. err, vim.log.levels.ERROR)
              return
            end
            local msg = "[gitlad] Review submitted: " .. event_label
            if has_pending then
              msg = msg .. string.format(" (with %d comments)", #pending)
              self.review_state.pending_comments = {}
              self.review_state.pending_mode = false
            end
            vim.notify(msg, vim.log.levels.INFO)
            self:_fetch_review_threads()
          end)
        end

        vim.notify("[gitlad] Submitting review...", vim.log.levels.INFO)

        if has_pending and provider.submit_review_with_comments then
          provider:submit_review_with_comments(pr_node_id, event, body, pending, on_complete)
        else
          provider:submit_review(pr_node_id, event, body, on_complete)
        end
      end,
    })
  end

  local title = "Submit Review"
  if has_pending then
    title = string.format("Submit Review (%d pending)", #pending)
  end

  local review_popup = popup
    .builder()
    :name(title)
    :action("a", "Approve", function()
      do_submit("APPROVE", "Approve")
    end)
    :action("r", "Request changes", function()
      do_submit("REQUEST_CHANGES", "Request changes")
    end)
    :action("c", "Comment", function()
      do_submit("COMMENT", "Comment")
    end)
    :build()

  review_popup:show()
end

--- Toggle pending review mode.
--- In pending mode, `c` adds comments to a local list instead of posting immediately.
--- Use `R` to submit the pending review as a batch.
function DiffView:toggle_pending_mode()
  if not self.review_state then
    vim.notify("[gitlad] No review state available", vim.log.levels.WARN)
    return
  end

  self.review_state.pending_mode = not self.review_state.pending_mode
  local mode = self.review_state.pending_mode and "ON" or "OFF"
  local count = #self.review_state.pending_comments

  local msg = string.format("[gitlad] Pending review mode: %s", mode)
  if count > 0 then
    msg = msg .. string.format(" (%d comments)", count)
  end
  vim.notify(msg, vim.log.levels.INFO)

  -- Re-apply overlays to show/hide pending indicators
  local file_pairs = self.diff_spec.file_pairs
  if self.selected_file >= 1 and self.selected_file <= #file_pairs then
    self:_apply_review_overlays(file_pairs[self.selected_file].new_path)
  end
end

--- Show a message in the diff buffers when there are no changes.
function DiffView:_show_empty_message()
  local msg = { "", "  No changes" }

  local buffers
  if self.three_way and self.buffer_triple then
    buffers = self.buffer_triple:get_buffers()
  elseif self.buffer_pair then
    buffers = { self.buffer_pair.left_bufnr, self.buffer_pair.right_bufnr }
  else
    return
  end

  for _, bufnr in ipairs(buffers) do
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, msg)
    vim.bo[bufnr].modifiable = false
  end
end

--- Set up keymaps on diff buffers (2 or 3 depending on mode).
function DiffView:_setup_keymaps()
  local buffers
  if self.three_way and self.buffer_triple then
    buffers = self.buffer_triple:get_buffers()
  else
    buffers = { self.buffer_pair.left_bufnr, self.buffer_pair.right_bufnr }
  end

  -- Set up BufWriteCmd for editable buffers
  local editable_buffers = {}
  if self.three_way and self.buffer_triple then
    local mode = self.buffer_triple._editable
    if mode == "mid_only" then
      editable_buffers = { self.buffer_triple.mid_bufnr }
    elseif mode == "mid_and_right" then
      editable_buffers = { self.buffer_triple.mid_bufnr, self.buffer_triple.right_bufnr }
    end
  elseif self.buffer_pair and is_editable_source(self.diff_spec.source.type) then
    editable_buffers = { self.buffer_pair.right_bufnr }
  end
  for _, ebuf in ipairs(editable_buffers) do
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = ebuf,
      callback = function()
        self:_do_save(ebuf)
      end,
    })
  end

  for _, bufnr in ipairs(buffers) do
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

    -- PR commit navigation (only active in PR mode)
    keymap.set(bufnr, "n", "<C-n>", function()
      self:next_commit()
    end, "Next commit (PR mode)")

    keymap.set(bufnr, "n", "<C-p>", function()
      self:prev_commit()
    end, "Previous commit (PR mode)")

    -- Review thread navigation (PR mode only)
    keymap.set(bufnr, "n", "]t", function()
      self:goto_next_thread()
    end, "Next review thread")

    keymap.set(bufnr, "n", "[t", function()
      self:goto_prev_thread()
    end, "Previous review thread")

    keymap.set(bufnr, "n", "<Tab>", function()
      self:toggle_thread_at_cursor()
    end, "Toggle review thread")

    -- Review comment actions (PR mode only)
    keymap.set(bufnr, "n", "c", function()
      self:add_review_comment()
    end, "Add review comment")

    keymap.set(bufnr, "n", "r", function()
      self:reply_to_thread()
    end, "Reply to review thread")

    keymap.set(bufnr, "n", "R", function()
      self:submit_review()
    end, "Submit review")

    keymap.set(bufnr, "n", "P", function()
      self:toggle_pending_mode()
    end, "Toggle pending review mode")
  end
end

--- Handle save for an editable diff buffer.
--- Strips filler lines, routes to the correct save target, then refreshes.
---@param bufnr number The buffer being saved
function DiffView:_do_save(bufnr)
  local source_type = self.diff_spec.source.type
  local repo_root = self.diff_spec.repo_root
  local file_pairs = self.diff_spec.file_pairs
  if self.selected_file < 1 or self.selected_file > #file_pairs then
    return
  end
  local path = file_pairs[self.selected_file].new_path

  -- Determine save target based on source type and which buffer
  local save_fn
  if self.three_way and self.buffer_triple then
    local lines = self.buffer_triple:get_real_lines(bufnr)
    if bufnr == self.buffer_triple.mid_bufnr then
      if source_type == "merge" then
        -- Merge: mid buffer = WORKTREE (save to disk)
        save_fn = function(cb)
          save_mod.save_worktree(repo_root, path, lines, cb)
        end
      else
        -- Three-way staging: mid buffer = INDEX
        save_fn = function(cb)
          save_mod.save_index(repo_root, path, lines, cb)
        end
      end
    elseif bufnr == self.buffer_triple.right_bufnr then
      -- Right buffer = WORKTREE
      save_fn = function(cb)
        save_mod.save_worktree(repo_root, path, lines, cb)
      end
    end
  elseif self.buffer_pair then
    local lines = self.buffer_pair:get_real_lines(bufnr)
    if source_type == "staged" then
      -- Right buffer saves to INDEX
      save_fn = function(cb)
        save_mod.save_index(repo_root, path, lines, cb)
      end
    else
      -- unstaged/worktree: right buffer saves to WORKTREE (disk)
      save_fn = function(cb)
        save_mod.save_worktree(repo_root, path, lines, cb)
      end
    end
  end

  if not save_fn then
    return
  end

  save_fn(function(err)
    vim.schedule(function()
      if self._closed then
        return
      end
      if err then
        vim.notify("[gitlad] Save failed: " .. err, vim.log.levels.ERROR)
        return
      end
      -- Mark buffer as saved
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.bo[bufnr].modified = false
      end
      vim.notify("[gitlad] Saved " .. path, vim.log.levels.INFO)
      -- Refresh to re-diff and re-align
      self:refresh()
    end)
  end)
end

--- Check if any buffer in the view has unsaved changes.
---@return boolean
function DiffView:_has_unsaved_changes()
  if self.three_way and self.buffer_triple then
    return self.buffer_triple:has_unsaved_changes()
  elseif self.buffer_pair then
    return self.buffer_pair:has_unsaved_changes()
  end
  return false
end

--- Prompt the user about unsaved changes.
--- Returns true if the user wants to proceed (discard), false if they want to cancel.
---@param action string Description of what will happen (e.g., "switch files", "close")
---@return boolean proceed
function DiffView:_prompt_unsaved(action)
  local choice = vim.fn.confirm(
    string.format("Buffer has unsaved changes. %s anyway?", action),
    "&Save\n&Discard\n&Cancel",
    3
  )
  if choice == 1 then
    -- Save first, then proceed
    -- Save all modified editable buffers
    if self.three_way and self.buffer_triple then
      if self.buffer_triple.mid_bufnr and vim.bo[self.buffer_triple.mid_bufnr].modified then
        self:_do_save(self.buffer_triple.mid_bufnr)
      end
      if self.buffer_triple.right_bufnr and vim.bo[self.buffer_triple.right_bufnr].modified then
        self:_do_save(self.buffer_triple.right_bufnr)
      end
    elseif self.buffer_pair and self.buffer_pair.right_bufnr then
      if vim.bo[self.buffer_pair.right_bufnr].modified then
        self:_do_save(self.buffer_pair.right_bufnr)
      end
    end
    return true
  elseif choice == 2 then
    -- Discard and proceed
    -- Reset modified flag on all editable buffers
    if self.three_way and self.buffer_triple then
      if
        self.buffer_triple.mid_bufnr and vim.api.nvim_buf_is_valid(self.buffer_triple.mid_bufnr)
      then
        vim.bo[self.buffer_triple.mid_bufnr].modified = false
      end
      if
        self.buffer_triple.right_bufnr and vim.api.nvim_buf_is_valid(self.buffer_triple.right_bufnr)
      then
        vim.bo[self.buffer_triple.right_bufnr].modified = false
      end
    elseif
      self.buffer_pair
      and self.buffer_pair.right_bufnr
      and vim.api.nvim_buf_is_valid(self.buffer_pair.right_bufnr)
    then
      vim.bo[self.buffer_pair.right_bufnr].modified = false
    end
    return true
  else
    -- Cancel
    return false
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
  elseif source.type == "pr" then
    src.produce_pr(repo_root, source.pr_info, source.selected_commit, on_result)
  elseif source.type == "three_way" then
    src.produce_three_way(repo_root, on_result)
  elseif source.type == "merge" then
    src.produce_merge(repo_root, on_result)
  end

  -- Also re-fetch review threads on refresh
  if self.provider and self.pr_number then
    self:_fetch_review_threads()
  end
end

--- Close the entire diff view, cleaning up all resources.
---@param opts? { force?: boolean } Options (force skips unsaved changes prompt)
function DiffView:close(opts)
  if self._closed then
    return
  end

  -- Guard: prompt if closing with unsaved changes (unless forced)
  opts = opts or {}
  if not opts.force and self:_has_unsaved_changes() then
    if not self:_prompt_unsaved("Close") then
      return
    end
  end

  self._closed = true

  -- Remove autocmd
  if self._autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self._autocmd_id)
    self._autocmd_id = nil
  end

  -- Destroy panel and buffer pair/triple
  if self.panel then
    self.panel:destroy()
  end
  if self.buffer_pair then
    self.buffer_pair:destroy()
  end
  if self.buffer_triple then
    self.buffer_triple:destroy()
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

  -- Destroy panel and buffer pair/triple (buffers may already be gone)
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
  if self.buffer_triple then
    pcall(function()
      self.buffer_triple:destroy()
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
---@param opts? { initial_file?: string, provider?: ForgeProvider, pr_number?: number } Options
---@return DiffView
function M.open(diff_spec, opts)
  opts = opts or {}

  -- Close any existing diff view
  if active_view then
    active_view:close()
  end

  local view = DiffView._new(diff_spec)
  view.provider = opts.provider or nil
  view.pr_number = opts.pr_number or nil

  -- Use 3-way layout for three_way/merge sources
  local source_type = diff_spec.source.type
  if source_type == "three_way" or source_type == "merge" then
    view.three_way = true
    view:_setup_layout_three_way()
  else
    view:_setup_layout()
  end

  view:_render_initial(opts.initial_file)

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

--- Expose _find_file_index for testing
---@param file_pairs DiffFilePair[] File pairs to search
---@param path string File path to match
---@return number|nil index 1-based index
M._find_file_index = DiffView._find_file_index

return M
