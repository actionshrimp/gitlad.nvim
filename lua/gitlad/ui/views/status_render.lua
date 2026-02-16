---@mod gitlad.ui.views.status_render Status buffer render module
---@brief [[
--- Extracted render functionality for the status buffer.
--- Provides the render() method and related helpers.
---@brief ]]

local M = {}

local config = require("gitlad.config")
local git = require("gitlad.git")
local hl = require("gitlad.ui.hl")
local log_list = require("gitlad.ui.components.log_list")
local path_utils = require("gitlad.utils.path")
local sections = require("gitlad.ui.views.status_sections")
local signs_util = require("gitlad.ui.utils.signs")

-- Namespace for sign column indicators
local ns_signs = vim.api.nvim_create_namespace("gitlad_signs")

-- Sections that can be collapsed (file sections, commit sections, stashes, submodules, worktrees)
local COLLAPSIBLE_SECTIONS = {
  -- File sections (top-level sections like magit)
  untracked = true,
  unstaged = true,
  staged = true,
  conflicted = true,
  -- Commit sections
  unpulled_upstream = true,
  unpushed_upstream = true,
  unpulled_push = true,
  unpushed_push = true,
  recent = true,
  -- Rebase sequence
  rebase_sequence = true,
  -- Other sections
  stashes = true,
  submodules = true,
  worktrees = true,
}

--- Get the cache key for a file's diff
---@param path string
---@param section string
---@return string
local function diff_cache_key(path, section)
  return section .. ":" .. path
end

--- Update just the status indicator line (called by spinner animation)
---@param self StatusBuffer
local function update_status_line(self)
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end
  if not self.status_line_num then
    return
  end

  -- Skip buffer modification during visual/select mode to avoid disrupting
  -- active visual selections (buffer changes can exit visual mode on some
  -- Neovim versions)
  local mode = vim.fn.mode()
  if mode:find("[vVsS\22\19]") then
    return
  end

  local line_idx = self.status_line_num - 1 -- 0-indexed
  local new_text = self.spinner:get_display()

  -- Get current line length for in-place text replacement
  local current_lines = vim.api.nvim_buf_get_lines(self.bufnr, line_idx, line_idx + 1, false)
  local old_len = current_lines[1] and #current_lines[1] or 0

  -- Use nvim_buf_set_text for in-place modification (more stable for extmarks than set_lines)
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_text(self.bufnr, line_idx, 0, line_idx, old_len, { new_text })
  vim.bo[self.bufnr].modifiable = false

  -- Update just the text highlight (leaves background intact to avoid flicker)
  local ns_status = vim.api.nvim_create_namespace("gitlad_status")
  hl.update_status_line_text(self.bufnr, ns_status, line_idx, new_text)
end

--- Place expand/collapse signs in the sign column
---@param self StatusBuffer
local function place_signs(self)
  signs_util.place_expand_signs(self.bufnr, self.sign_lines, ns_signs)
end

--- Render the status buffer
---@param self StatusBuffer
local function render(self)
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  -- Defer render during visual/select mode to avoid disrupting active
  -- selections (buffer modifications can exit visual mode on some Neovim versions)
  local mode = vim.fn.mode()
  if mode:find("[vVsS\22\19]") then
    if not self._render_deferred then
      self._render_deferred = true
      vim.defer_fn(function()
        self._render_deferred = false
        render(self)
      end, 100)
    end
    return
  end

  local status = self.repo_state.status
  if not status then
    -- Show spinner with full-buffer loading background during initial load
    local loading_line = self.spinner:get_display()
    vim.bo[self.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { loading_line })
    vim.bo[self.bufnr].modifiable = false

    -- Apply loading background to the whole buffer
    local ns_status = vim.api.nvim_create_namespace("gitlad_status")
    hl.clear(self.bufnr, ns_status)
    hl.apply_status_line_highlight(self.bufnr, ns_status, 0, loading_line)

    self.status_line_num = 1
    return
  end

  local cfg = config.get()
  local show_tags = cfg.show_tags_in_refs
  local lines = {}
  self.line_map = {} -- Reset line map
  self.section_lines = {} -- Reset section lines
  self.sign_lines = {} -- Reset sign lines

  -- Helper to add a section header and track its line number
  -- Returns true if section is expanded (content should be rendered)
  local function add_section_header(name, section, count)
    local is_collapsed = self.collapsed_sections[section]
    table.insert(lines, string.format("%s (%d)", name, count))
    self.section_lines[#lines] = { name = name, section = section }
    -- Add sign for collapsible sections
    if COLLAPSIBLE_SECTIONS[section] then
      self.sign_lines[#lines] = { expanded = not is_collapsed }
    end
    return not is_collapsed
  end

  -- Helper to add a file entry and track its line number
  local function add_file_line(entry, section, sign, status_char, use_display)
    local display = use_display
        and entry.orig_path
        and path_utils.format_rename(entry.orig_path, entry.path)
      or entry.path

    -- Check if this is a submodule entry (uses different cache key)
    local is_submodule_entry = entry.submodule and entry.submodule:sub(1, 1) == "S"
    local key = is_submodule_entry and ("submodule:" .. entry.path)
      or diff_cache_key(entry.path, section)
    local expansion_state = self.expanded_files[key]
    -- Determine if file is expanded at all (true or table means some level of expansion)
    local is_expanded = expansion_state == true or type(expansion_state) == "table"

    -- Format without expand indicator (it goes in sign column)
    local line_text = status_char and string.format("%s %s %s", sign, status_char, display)
      or string.format("%s   %s", sign, display)
    table.insert(lines, line_text)
    self.line_map[#lines] = { type = "file", path = entry.path, section = section, entry = entry }
    self.sign_lines[#lines] = { expanded = is_expanded }

    -- Add diff lines if expanded
    if is_expanded and self.diff_cache[key] then
      local diff_data = self.diff_cache[key]

      -- Handle submodule diffs (SHA diff format)
      if diff_data.is_submodule then
        table.insert(lines, "-" .. diff_data.old_sha)
        self.line_map[#lines] = { type = "submodule_diff", diff_type = "delete" }
        table.insert(lines, "+" .. diff_data.new_sha)
        self.line_map[#lines] = { type = "submodule_diff", diff_type = "add" }
      else
        -- Normal file diff with per-hunk expansion support
        -- expansion_state can be:
        --   true = all hunks expanded
        --   {} = headers only (no hunks expanded)
        --   { [n] = true } = specific hunks expanded
        local is_fully_expanded = expansion_state == true
        local hunk_expansion = type(expansion_state) == "table" and expansion_state or {}

        for hunk_index, hunk in ipairs(diff_data.hunks) do
          local hunk_is_expanded = is_fully_expanded or hunk_expansion[hunk_index]

          -- Always show the hunk header (@@ line)
          table.insert(lines, hunk.header)
          self.line_map[#lines] = {
            type = "file",
            path = entry.path,
            section = section,
            entry = entry,
            hunk_index = hunk_index,
            is_hunk_header = true,
          }
          self.sign_lines[#lines] = { expanded = hunk_is_expanded }

          -- Show hunk content only if this hunk is expanded
          if hunk_is_expanded then
            for _, content_line in ipairs(hunk.lines) do
              table.insert(lines, content_line)
              self.line_map[#lines] = {
                type = "file",
                path = entry.path,
                section = section,
                entry = entry,
                hunk_index = hunk_index,
              }
            end
          end
        end
      end
    end
  end

  -- Track commit section results for highlighting
  local commit_section_results = {}

  -- Helper to render a commit section using log_list component
  local function add_commit_section(title, commits, section_type)
    if #commits == 0 then
      return
    end

    local is_collapsed = self.collapsed_sections[section_type]
    -- No indicator in text - it goes in sign column
    table.insert(lines, string.format("%s (%d)", title, #commits))
    self.section_lines[#lines] = { name = title, section = section_type }
    self.sign_lines[#lines] = { expanded = not is_collapsed }

    -- Only render commits if section is not collapsed
    if not is_collapsed then
      local start_line = #lines -- 0-indexed for highlighting
      local result = log_list.render(commits, self.expanded_commits, {
        indent = 0,
        section = section_type,
        show_tags = show_tags,
      })

      for i, line in ipairs(result.lines) do
        table.insert(lines, line)
        local info = result.line_info[i]
        if info then
          -- Commits now tracked in line_map with CommitLineInfo
          self.line_map[#lines] = info
        end
      end

      -- Track for later highlighting
      table.insert(commit_section_results, { start_line = start_line, result = result })
    end
    table.insert(lines, "")
  end

  -- Status indicator line at the very top (shows spinner when refreshing, placeholder when idle)
  table.insert(lines, self.spinner:get_display())
  self.status_line_num = #lines -- Always line 1

  -- Header
  local head_line = "Head:     " .. status.branch
  if status.head_commit_msg then
    head_line = head_line .. "  " .. status.head_commit_msg
  end
  table.insert(lines, head_line)

  -- Merge (upstream) line
  if status.upstream then
    local merge_line = "Merge:    " .. status.upstream
    if status.merge_commit_msg then
      merge_line = merge_line .. "  " .. status.merge_commit_msg
    end
    if status.ahead > 0 or status.behind > 0 then
      merge_line = merge_line .. string.format(" [+%d/-%d]", status.ahead, status.behind)
    end
    table.insert(lines, merge_line)
  end

  -- Push line (only if different from merge)
  if status.push_remote then
    local push_line = "Push:     " .. status.push_remote
    if status.push_commit_msg then
      push_line = push_line .. "  " .. status.push_commit_msg
    end
    if status.push_ahead > 0 or status.push_behind > 0 then
      push_line = push_line .. string.format(" [+%d/-%d]", status.push_ahead, status.push_behind)
    end
    table.insert(lines, push_line)
  end

  -- Sequencer state (cherry-pick/revert/rebase/merge in progress)
  if status.cherry_pick_in_progress then
    local short_oid = status.sequencer_head_oid and status.sequencer_head_oid:sub(1, 7) or "unknown"
    local seq_line = "Cherry-picking: " .. short_oid
    if status.sequencer_head_subject then
      seq_line = seq_line .. " " .. status.sequencer_head_subject
    end
    table.insert(lines, seq_line)
  elseif status.revert_in_progress then
    local short_oid = status.sequencer_head_oid and status.sequencer_head_oid:sub(1, 7) or "unknown"
    local seq_line = "Reverting: " .. short_oid
    if status.sequencer_head_subject then
      seq_line = seq_line .. " " .. status.sequencer_head_subject
    end
    table.insert(lines, seq_line)
  elseif status.rebase_in_progress then
    -- Blank line before the rebase section (separates from Head/Merge/Push header)
    table.insert(lines, "")

    -- Full rebase sequence section (magit-style)
    local rebase_branch = status.rebase_head_name or status.branch or "unknown"
    local rebase_target = status.rebase_onto_name or (status.rebase_onto_abbrev or "unknown")
    local rebase_header = string.format("Rebasing %s onto %s", rebase_branch, rebase_target)
    table.insert(lines, rebase_header)
    self.section_lines[#lines] = { name = rebase_header, section = "rebase_sequence" }
    self.sign_lines[#lines] = { expanded = not self.collapsed_sections["rebase_sequence"] }

    if not self.collapsed_sections["rebase_sequence"] then
      -- 1. Todo lines (pending actions, in original order - first item is next to be applied)
      if status.rebase_todo then
        for _, entry in ipairs(status.rebase_todo) do
          local todo_line
          if entry.action == "break" then
            todo_line = "break"
          elseif
            entry.action == "exec"
            or entry.action == "label"
            or entry.action == "reset"
            or entry.action == "update-ref"
          then
            todo_line = string.format("%s %s", entry.action, entry.subject or "")
          else
            todo_line =
              string.format("%s %s %s", entry.action, entry.hash or "", entry.subject or "")
          end
          table.insert(lines, todo_line)
          self.line_map[#lines] = {
            type = "rebase_commit",
            action = entry.action,
            hash = entry.hash,
            subject = entry.subject,
            rebase_state = "todo",
          }
        end
      end

      -- 2. Stopped commit (if paused at conflict/edit)
      if status.rebase_stopped_sha then
        local stopped_abbrev = status.rebase_stopped_sha:sub(1, 7)
        -- Find the subject from the done file entries
        local stopped_subject = ""
        if status.rebase_done then
          for i = #status.rebase_done, 1, -1 do
            local entry = status.rebase_done[i]
            if entry.hash and entry.hash:sub(1, 7) == stopped_abbrev then
              stopped_subject = entry.subject or ""
              break
            end
          end
        end
        local stop_line = string.format("stop %s %s", stopped_abbrev, stopped_subject)
        table.insert(lines, stop_line)
        self.line_map[#lines] = {
          type = "rebase_commit",
          action = "stop",
          hash = stopped_abbrev,
          subject = stopped_subject,
          rebase_state = "stop",
        }
      end

      -- 3. Done commits (from git log onto..HEAD, most recent first)
      -- Skip the stopped commit (already shown as "stop" above)
      if status.rebase_done_commits and #status.rebase_done_commits > 0 then
        local stopped_sha = status.rebase_stopped_sha
        for i = #status.rebase_done_commits, 1, -1 do
          local commit = status.rebase_done_commits[i]
          -- Skip if this is the stopped commit (already shown as "stop")
          if not stopped_sha or not commit.hash:find(stopped_sha, 1, true) then
            local done_line = string.format("done %s %s", commit.abbrev, commit.subject)
            table.insert(lines, done_line)
            self.line_map[#lines] = {
              type = "rebase_commit",
              action = "done",
              hash = commit.abbrev,
              full_hash = commit.hash,
              subject = commit.subject,
              rebase_state = "done",
              -- Only mark as HEAD if there's no stopped commit (stop line is HEAD otherwise)
              is_head = not stopped_sha and (i == #status.rebase_done_commits),
            }
          end
        end
      end

      -- 4. Onto line
      if status.rebase_onto_abbrev then
        local onto_line =
          string.format("onto %s %s", status.rebase_onto_abbrev, status.rebase_onto_subject or "")
        table.insert(lines, onto_line)
        self.line_map[#lines] = {
          type = "rebase_commit",
          action = "onto",
          hash = status.rebase_onto_abbrev,
          full_hash = status.rebase_onto,
          subject = status.rebase_onto_subject,
          rebase_state = "onto",
        }
      end
    end
  elseif status.merge_in_progress then
    local short_oid = status.merge_head_oid and status.merge_head_oid:sub(1, 7) or "unknown"
    local merge_line = "Merging: " .. short_oid
    if status.merge_head_subject then
      merge_line = merge_line .. " " .. status.merge_head_subject
    end
    table.insert(lines, merge_line)
  elseif status.am_in_progress then
    local am_line = "Applying patches"
    if status.am_current_patch and status.am_last_patch then
      am_line = am_line .. ": " .. status.am_current_patch .. "/" .. status.am_last_patch
    end
    am_line = am_line .. " (resolve conflicts and press 'w' to continue)"
    table.insert(lines, am_line)
  end

  table.insert(lines, "")

  -- === Configurable sections ===
  -- Build render context for section functions
  local render_ctx = {
    self = self,
    status = status,
    cfg = cfg,
    lines = lines,
    add_section_header = add_section_header,
    add_file_line = add_file_line,
    add_commit_section = add_commit_section,
    show_tags = show_tags,
  }

  -- Get configured sections (or defaults)
  local section_list = sections.get_sections()

  -- Track if any file sections were rendered (for "Nothing to commit" message)
  local rendered_file_sections = false
  local file_section_names = { untracked = true, unstaged = true, staged = true, conflicted = true }

  -- Render each section in configured order
  for _, section_entry in ipairs(section_list) do
    local name, opts = sections.normalize_section(section_entry)
    local def = sections.SECTION_DEFS[name]
    if def then
      local lines_before = #lines
      def.render(render_ctx, opts)
      -- Track if file sections rendered content
      if file_section_names[name] and #lines > lines_before then
        rendered_file_sections = true
      end
    end
  end

  -- Clean working tree message (only if no file sections rendered)
  if not rendered_file_sections and not sections.has_file_changes(status) then
    table.insert(lines, "Nothing to commit, working tree clean")
    table.insert(lines, "")
  end

  -- Help line
  table.insert(lines, "Press ? for help")

  -- Allow modification while updating buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Determine if upstream is a local branch (remote = ".")
  local local_upstream = false
  if status.upstream and status.branch then
    local upstream_remote =
      git.config_get("branch." .. status.branch .. ".remote", { cwd = self.repo_state.repo_root })
    local_upstream = upstream_remote == "."
  end

  -- Apply syntax highlighting
  hl.apply_status_highlights(self.bufnr, lines, self.line_map, self.section_lines, {
    local_upstream = local_upstream,
  })

  -- Apply full-buffer background during initial load for visual effect
  -- Once loading completes, only the status line (line 1) keeps the background
  if not self.initial_load_complete and self.spinner:is_spinning() then
    local ns_status = vim.api.nvim_create_namespace("gitlad_status")
    hl.apply_loading_background(self.bufnr, ns_status, #lines)
  end

  -- Apply commit ref highlighting for commit sections
  for _, section in ipairs(commit_section_results) do
    log_list.apply_highlights(self.bufnr, section.start_line, section.result)
  end

  -- Apply treesitter highlighting to expanded diffs
  hl.apply_diff_treesitter_highlights(self.bufnr, lines, self.line_map, self.diff_cache)

  -- Place expand/collapse indicators in sign column
  place_signs(self)

  -- Position cursor on pending target (e.g., after unstaging a file)
  if self.pending_cursor_target then
    local target = self.pending_cursor_target
    self.pending_cursor_target = nil
    for line_num, info in pairs(self.line_map) do
      if
        info.path == target.path
        and info.section == target.section
        and info.type == "file"
        and not info.hunk_index
      then
        -- Only set cursor if we're in the right window
        if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
          vim.api.nvim_win_set_cursor(self.winnr, { line_num, 0 })
        end
        break
      end
    end
  end

  -- Make buffer non-modifiable to prevent accidental edits
  vim.bo[self.bufnr].modifiable = false
end

--- Attach render methods to StatusBuffer class
---@param StatusBuffer table The StatusBuffer class
function M.setup(StatusBuffer)
  StatusBuffer._update_status_line = update_status_line
  StatusBuffer._place_signs = place_signs
  StatusBuffer.render = render
end

-- Export constants for use by other modules
M.COLLAPSIBLE_SECTIONS = COLLAPSIBLE_SECTIONS
M.diff_cache_key = diff_cache_key

return M
