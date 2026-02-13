---@mod gitlad.ui.views.status_keymaps Status buffer keymaps module
---@brief [[
--- Extracted keymap functionality for the status buffer.
--- Provides the _setup_keymaps() method.
---@brief ]]

local M = {}

local history_view = require("gitlad.ui.views.history")
local keymap = require("gitlad.utils.keymap")
local log_list = require("gitlad.ui.components.log_list")

--- Get the file path at the current cursor position
---@param self StatusBuffer
---@return string|nil path
---@return string|nil section "staged"|"unstaged"|"untracked"|"conflicted"
---@return number|nil hunk_index Index of hunk if on a diff line
---@return GitStatusEntry|nil entry The full status entry (for accessing orig_path etc.)
local function get_current_file(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.path then
    return info.path, info.section, info.hunk_index, info.entry
  end

  return nil, nil, nil, nil
end

--- Get the commit at the current cursor position
---@param self StatusBuffer
---@return GitCommitInfo|nil commit
---@return string|nil section The commit section type
local function get_current_commit(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.type == "commit" then
    return info.commit, info.section
  end

  return nil, nil
end

--- Get the submodule at the current cursor position
--- Works for both the dedicated Submodules section and submodule files in unstaged/staged
---@param self StatusBuffer
---@return SubmoduleEntry|nil submodule
local function get_current_submodule(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if not info then
    return nil
  end

  -- Check if in dedicated Submodules section
  if info.type == "submodule" then
    return info.submodule
  end

  -- Check if it's a file entry that is a submodule (from unstaged/staged sections)
  if info.type == "file" and info.entry and info.entry.submodule then
    -- Try to find the full submodule entry from status.submodules for the SHA
    local status = self.repo_state.status
    local sha = ""
    local describe = nil
    if status and status.submodules then
      for _, sub in ipairs(status.submodules) do
        if sub.path == info.entry.path then
          sha = sub.sha
          describe = sub.describe
          break
        end
      end
    end

    -- Create a SubmoduleEntry-like object from the file entry
    return {
      path = info.entry.path,
      sha = sha,
      status = "modified",
      describe = describe,
    }
  end

  return nil
end

--- Get the stash at the current cursor position
---@param self StatusBuffer
---@return StashEntry|nil stash
local function get_current_stash(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.type == "stash" then
    return info.stash
  end

  return nil
end

--- Get the worktree at the current cursor position
---@param self StatusBuffer
---@return WorktreeEntry|nil worktree
local function get_current_worktree(self)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local info = self.line_map[line]
  if info and info.type == "worktree" then
    return info.worktree
  end

  return nil
end

--- Get selected commits (normal mode: single, visual mode: range)
---@param self StatusBuffer
---@return GitCommitInfo[] Selected commits
local function get_selected_commits(self)
  local mode = vim.fn.mode()
  if mode:match("[vV]") then
    -- Visual mode: get range
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "nx", false)
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    return log_list.get_commits_in_range(self.line_map, start_line, end_line)
  else
    -- Normal mode: single commit
    local commit = get_current_commit(self)
    if commit then
      return { commit }
    end
  end
  return {}
end

--- Get selected submodule paths (visual mode)
---@param self StatusBuffer
---@return string[] Selected submodule paths
local function get_selected_submodule_paths(self)
  local mode = vim.fn.mode()
  if not mode:match("[vV]") then
    return {}
  end

  -- Exit visual mode to get marks
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  local paths = {}
  for line = start_line, end_line do
    local info = self.line_map[line]
    if info then
      -- Check dedicated Submodules section
      if info.type == "submodule" then
        table.insert(paths, info.submodule.path)
      -- Check file entries that are submodules (from unstaged/staged sections)
      elseif info.type == "file" and info.entry and info.entry.submodule then
        table.insert(paths, info.entry.path)
      end
    end
  end

  return paths
end

--- Get diff context for current cursor position
---@param self StatusBuffer
---@return DiffContext
local function get_diff_context(self)
  local file_path, section = get_current_file(self)
  local commit = get_current_commit(self)
  local stash = get_current_stash(self)
  return { file_path = file_path, section = section, commit = commit, stash = stash }
end

--- Yank section value to clipboard (commit hash, file path, or stash name)
---@param self StatusBuffer
local function yank_section_value(self)
  -- Try commit first
  local commit = get_current_commit(self)
  if commit then
    vim.fn.setreg("+", commit.hash)
    vim.fn.setreg('"', commit.hash)
    vim.notify("[gitlad] Yanked: " .. commit.hash, vim.log.levels.INFO)
    return
  end

  -- Try file path
  local file_path = get_current_file(self)
  if file_path then
    vim.fn.setreg("+", file_path)
    vim.fn.setreg('"', file_path)
    vim.notify("[gitlad] Yanked: " .. file_path, vim.log.levels.INFO)
    return
  end

  -- Try stash
  local stash = get_current_stash(self)
  if stash then
    vim.fn.setreg("+", stash.name)
    vim.fn.setreg('"', stash.name)
    vim.notify("[gitlad] Yanked: " .. stash.name, vim.log.levels.INFO)
    return
  end

  vim.notify("[gitlad] Nothing to yank at cursor", vim.log.levels.INFO)
end

--- Set up buffer keymaps
---@param self StatusBuffer
local function setup_keymaps(self)
  local bufnr = self.bufnr

  -- Staging single file/hunk
  keymap.set(bufnr, "n", "s", function()
    self:_stage_current()
  end, "Stage file/hunk")
  keymap.set(bufnr, "n", "u", function()
    self:_unstage_current()
  end, "Unstage file/hunk")

  -- Visual mode staging (for partial hunk staging)
  keymap.set(bufnr, "v", "s", function()
    self:_stage_visual()
  end, "Stage selection")
  keymap.set(bufnr, "v", "u", function()
    self:_unstage_visual()
  end, "Unstage selection")

  -- Intent-to-add (for partial staging of untracked files)
  keymap.set(bufnr, "n", "gs", function()
    self:_stage_intent_current()
  end, "Stage intent (git add -N)")

  -- Staging all
  keymap.set(bufnr, "n", "S", function()
    self:_stage_all()
  end, "Stage all")
  keymap.set(bufnr, "n", "U", function()
    self:_unstage_all()
  end, "Unstage all")

  -- Discard (context-aware: drops stash when on stash entry)
  keymap.set(bufnr, "n", "x", function()
    local stash = get_current_stash(self)
    if stash then
      self:_stash_drop(stash)
    else
      self:_discard_current()
    end
  end, "Discard changes / Drop stash")
  keymap.set(bufnr, "v", "x", function()
    self:_discard_visual()
  end, "Discard selection")

  -- Refresh (gr to free up g prefix for vim motions like gg)
  keymap.set(bufnr, "n", "gr", function()
    self.repo_state:refresh_status(true)
  end, "Refresh status")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close status")

  -- Navigation (evil-collection-magit style: gj/gk for items, j/k for normal line movement)
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_file()
  end, "Next file/commit")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_file()
  end, "Previous file/commit")
  keymap.set(bufnr, "n", "<M-n>", function()
    self:_goto_next_section()
  end, "Next section")
  keymap.set(bufnr, "n", "<M-p>", function()
    self:_goto_prev_section()
  end, "Previous section")

  -- Visit file (RET opens file, or diffview for conflicts)
  keymap.set(bufnr, "n", "<CR>", function()
    self:_visit_file()
  end, "Visit file")

  -- Edit file (same as RET - matches magit's 'e' keybinding)
  keymap.set(bufnr, "n", "e", function()
    self:_visit_file()
  end, "Edit file")

  -- Diff toggle
  keymap.set(bufnr, "n", "<Tab>", function()
    self:_toggle_diff()
  end, "Toggle diff")

  -- Toggle all sections (magit-style Shift-Tab)
  keymap.set(bufnr, "n", "<S-Tab>", function()
    self:_toggle_all_sections()
  end, "Toggle all sections")

  -- Jump to specific visibility levels (magit-style: 1/2/3/4, scoped to cursor position)
  keymap.set(bufnr, "n", "1", function()
    self:_apply_scoped_visibility_level(1)
  end, "Show headers only (scoped)")
  keymap.set(bufnr, "n", "2", function()
    self:_apply_scoped_visibility_level(2)
  end, "Show items (scoped)")
  keymap.set(bufnr, "n", "3", function()
    self:_apply_scoped_visibility_level(3)
  end, "Show diffs (scoped)")
  keymap.set(bufnr, "n", "4", function()
    self:_apply_scoped_visibility_level(4)
  end, "Show all (scoped)")

  -- Git command history
  keymap.set(bufnr, "n", "$", function()
    history_view.open()
  end, "Show git command history")

  -- Help
  keymap.set(bufnr, "n", "?", function()
    local help_popup = require("gitlad.popups.help")
    help_popup.open(self)
  end, "Show help")

  -- Commit popup (passes commit at point for instant fixup/squash)
  keymap.set(bufnr, "n", "c", function()
    local commit_popup = require("gitlad.popups.commit")
    local commit = get_current_commit(self)
    local context = commit and { commit = commit.hash } or nil
    commit_popup.open(self.repo_state, context)
  end, "Commit popup")

  -- Push popup (evil-collection-magit style: p instead of P)
  keymap.set(bufnr, "n", "p", function()
    local push_popup = require("gitlad.popups.push")
    local commit = get_current_commit(self)
    local context = commit and { commit = commit.hash } or nil
    push_popup.open(self.repo_state, context)
  end, "Push popup")

  -- Fetch popup
  keymap.set(bufnr, "n", "f", function()
    local fetch_popup = require("gitlad.popups.fetch")
    fetch_popup.open(self.repo_state)
  end, "Fetch popup")

  -- Pull popup
  keymap.set(bufnr, "n", "F", function()
    local pull_popup = require("gitlad.popups.pull")
    pull_popup.open(self.repo_state)
  end, "Pull popup")

  -- Branch popup
  keymap.set(bufnr, "n", "b", function()
    local branch_popup = require("gitlad.popups.branch")
    branch_popup.open(self.repo_state)
  end, "Branch popup")

  -- Log popup
  keymap.set(bufnr, "n", "l", function()
    local log_popup = require("gitlad.popups.log")
    log_popup.open(self.repo_state)
  end, "Log popup")

  -- Diff popup
  keymap.set(bufnr, "n", "d", function()
    local diff_popup = require("gitlad.popups.diff")
    local context = get_diff_context(self)
    diff_popup.open(self.repo_state, context)
  end, "Diff popup")
  -- Yank bindings (evil-collection style: y prefix)
  -- yy is left to vim's default (yank line)
  keymap.set(bufnr, "n", "ys", function()
    yank_section_value(self)
  end, "Yank section value")
  keymap.set(bufnr, "n", "yr", function()
    local refs_popup = require("gitlad.popups.refs")
    refs_popup.open(self.repo_state)
  end, "Show references")

  -- Stash popup (passes stash at point for context-aware operations)
  keymap.set(bufnr, "n", "z", function()
    local stash_popup = require("gitlad.popups.stash")
    local stash = get_current_stash(self)
    local context = stash and { stash = stash } or nil
    stash_popup.open(self.repo_state, context)
  end, "Stash popup")

  -- Cherry-pick popup
  keymap.set(bufnr, "n", "A", function()
    local cherrypick_popup = require("gitlad.popups.cherrypick")
    local commit = get_current_commit(self)
    local context = commit and { commit = commit.hash } or nil
    cherrypick_popup.open(self.repo_state, context)
  end, "Cherry-pick popup")

  -- Revert popup (evil-collection-magit uses '_' - you're "subtracting" a commit)
  keymap.set(bufnr, "n", "_", function()
    local revert_popup = require("gitlad.popups.revert")
    local commit = get_current_commit(self)
    local context = commit and { commit = commit.hash } or nil
    revert_popup.open(self.repo_state, context)
  end, "Revert popup")

  -- Reset popup (neogit/evil-collection-magit style: X for destructive reset)
  keymap.set(bufnr, "n", "X", function()
    local reset_popup = require("gitlad.popups.reset")
    local commit = get_current_commit(self)
    local context = commit and { commit = commit.hash } or nil
    reset_popup.open(self.repo_state, context)
  end, "Reset popup")

  -- Rebase popup
  keymap.set(bufnr, "n", "r", function()
    local rebase_popup = require("gitlad.popups.rebase")
    local commit = get_current_commit(self)
    local context = commit and { commit = commit.hash } or nil
    rebase_popup.open(self.repo_state, context)
  end, "Rebase popup")

  -- Merge popup
  keymap.set(bufnr, "n", "m", function()
    local merge_popup = require("gitlad.popups.merge")
    merge_popup.open(self.repo_state)
  end, "Merge popup")

  -- Submodule popup (evil-collection-magit style: ' for submodule)
  keymap.set(bufnr, "n", "'", function()
    local submodule_popup = require("gitlad.popups.submodule")
    local submodule = get_current_submodule(self)
    local context = submodule and { submodule = submodule } or nil
    submodule_popup.open(self.repo_state, context)
  end, "Submodule popup")

  -- Visual mode submodule popup (for operations on selected submodules)
  keymap.set(bufnr, "v", "'", function()
    local submodule_popup = require("gitlad.popups.submodule")
    local paths = get_selected_submodule_paths(self)
    local context = #paths > 0 and { paths = paths } or nil
    submodule_popup.open(self.repo_state, context)
  end, "Submodule popup (selection)")

  -- Remote popup (magit style: M for remote management)
  keymap.set(bufnr, "n", "M", function()
    local remote_popup = require("gitlad.popups.remote")
    remote_popup.open(self.repo_state)
  end, "Remote popup")

  -- Patch popup (magit-style: W for format-patch / apply / save)
  keymap.set(bufnr, "n", "W", function()
    local patch_popup = require("gitlad.popups.patch")
    local file_path, section = get_current_file(self)
    local commit = get_current_commit(self)
    local context = {}
    if commit then
      context.commit = commit.hash
    end
    if file_path then
      context.file_path = file_path
      context.staged = section == "staged"
    end
    patch_popup.open(self.repo_state, next(context) and context or nil)
  end, "Patch popup")

  -- Apply patches popup (magit-style: w for git am)
  keymap.set(bufnr, "n", "w", function()
    local am_popup = require("gitlad.popups.am")
    am_popup.open(self.repo_state)
  end, "Apply patches popup")

  -- Worktree popup (evil-collection-magit style: Z default, % also works)
  local function open_worktree_popup()
    local worktree_popup = require("gitlad.popups.worktree")
    local worktree = get_current_worktree(self)
    local context = worktree and { worktree = worktree } or nil
    worktree_popup.open(self.repo_state, context)
  end
  keymap.set(bufnr, "n", "Z", open_worktree_popup, "Worktree popup")
  keymap.set(bufnr, "n", "%", open_worktree_popup, "Worktree popup")
end

--- Attach keymap methods to StatusBuffer class
---@param StatusBuffer table The StatusBuffer class
function M.setup(StatusBuffer)
  StatusBuffer._setup_keymaps = setup_keymaps
  StatusBuffer._get_current_file = get_current_file
  StatusBuffer._get_current_commit = get_current_commit
  StatusBuffer._get_current_submodule = get_current_submodule
  StatusBuffer._get_current_stash = get_current_stash
  StatusBuffer._get_current_worktree = get_current_worktree
  StatusBuffer._get_selected_commits = get_selected_commits
  StatusBuffer._get_selected_submodule_paths = get_selected_submodule_paths
  StatusBuffer._get_diff_context = get_diff_context
  StatusBuffer._yank_section_value = yank_section_value
end

return M
