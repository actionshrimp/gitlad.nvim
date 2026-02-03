---@mod gitlad.ui.hl_status Status buffer highlighting
---@brief [[
--- Status buffer highlighting functions for gitlad.
---@brief ]]

local M = {}

-- Map status characters to highlight groups
local status_char_hl = {
  A = "GitladFileAdded",
  M = "GitladFileModified",
  D = "GitladFileDeleted",
  R = "GitladFileRenamed",
  C = "GitladFileCopied",
  U = "GitladFileModified", -- Updated but unmerged
  T = "GitladFileModified", -- Type changed
}

-- Map section names to highlight groups
local section_hl = {
  -- File sections
  staged = "GitladSectionStaged",
  unstaged = "GitladSectionUnstaged",
  untracked = "GitladSectionUntracked",
  conflicted = "GitladSectionConflicted",
  -- Stash, submodule, and worktree sections
  stashes = "GitladSectionStashes",
  submodules = "GitladSectionSubmodules",
  worktrees = "GitladSectionWorktrees",
  -- Commit sections
  unpulled_upstream = "GitladSectionUnpulled",
  unpushed_upstream = "GitladSectionUnpushed",
  unpulled_push = "GitladSectionUnpulled",
  unpushed_push = "GitladSectionUnpushed",
  recent = "GitladSectionRecent",
}

--- Apply highlight to a status indicator line (full render)
--- Used during full render to set up both background and text highlights
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_idx number 0-indexed line number
---@param line string The line content
---@param hl_module table Reference to the hl module for set/set_line functions
function M.apply_status_line_highlight(bufnr, ns, line_idx, line, hl_module)
  -- Clear any existing highlight on this line
  vim.api.nvim_buf_clear_namespace(bufnr, ns, line_idx, line_idx + 1)

  -- Apply faint background to the entire line (lower priority)
  hl_module.set_line(bufnr, ns, line_idx, "GitladStatusLineBackground", { priority = 50 })

  -- Check if this is the spinner (refreshing), stale, or idle state
  local is_spinning = line:match("Refreshing")
  local is_stale = line:match("Stale")
  local hl_group = is_spinning and "GitladStatusSpinner"
    or is_stale and "GitladStatusStale"
    or "GitladStatusIdle"
  -- Apply text highlight on top (higher priority)
  hl_module.set(bufnr, ns, line_idx, 0, #line, hl_group, { priority = 60 })
end

--- Update just the text highlight on the status line (spinner animation)
--- Does not touch the background to avoid visual flicker during animation
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_idx number 0-indexed line number
---@param line string The line content
---@param hl_module table Reference to the hl module for set function
function M.update_status_line_text(bufnr, ns, line_idx, line, hl_module)
  -- Get all extmarks on this line
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    ns,
    { line_idx, 0 },
    { line_idx, -1 },
    { details = true }
  )

  -- Remove only text highlights (those with hl_group, not line_hl_group)
  for _, mark in ipairs(marks) do
    local details = mark[4]
    if details.hl_group and not details.line_hl_group then
      vim.api.nvim_buf_del_extmark(bufnr, ns, mark[1])
    end
  end

  -- Apply new text highlight
  local is_spinning = line:match("Refreshing")
  local is_stale = line:match("Stale")
  local hl_group = is_spinning and "GitladStatusSpinner"
    or is_stale and "GitladStatusStale"
    or "GitladStatusIdle"
  hl_module.set(bufnr, ns, line_idx, 0, #line, hl_group, { priority = 60 })
end

--- Apply loading background to all lines (during initial load)
--- This creates a visual effect where the entire buffer has the faint background,
--- which transitions to just the first line once loading completes.
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_count number Total number of lines in buffer
---@param hl_module table Reference to the hl module for set_line function
function M.apply_loading_background(bufnr, ns, line_count, hl_module)
  for i = 0, line_count - 1 do
    hl_module.set_line(bufnr, ns, i, "GitladStatusLineBackground", { priority = 50 })
  end
end

--- Apply highlights to the status buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
---@param line_map table<number, LineInfo> Map of line numbers to file info (1-indexed)
---@param section_lines table<number, SectionInfo> Map of line numbers to section info (1-indexed)
---@param ns_status number Status namespace
---@param ns_diff_markers number Diff markers namespace
---@param hl_module table Reference to the hl module for set/set_line/clear functions
function M.apply_status_highlights(
  bufnr,
  lines,
  line_map,
  section_lines,
  ns_status,
  ns_diff_markers,
  hl_module
)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous highlights
  hl_module.clear(bufnr, ns_status)
  hl_module.clear(bufnr, ns_diff_markers)

  for i, line in ipairs(lines) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Head line: "Head:     branch  commit_msg"
    if line:match("^Head:") then
      -- Highlight "Head:" label
      hl_module.set(bufnr, ns_status, line_idx, 0, 5, "GitladHead")
      -- Find and highlight branch name (muted red for local branch)
      local branch_start = line:find("%S", 11) -- After "Head:     "
      if branch_start then
        local branch_end = line:find("%s", branch_start)
        if branch_end then
          hl_module.set(
            bufnr,
            ns_status,
            line_idx,
            branch_start - 1,
            branch_end - 1,
            "GitladRefCombined"
          )
          -- Rest is commit message
          local msg_start = line:find("%S", branch_end)
          if msg_start then
            hl_module.set(bufnr, ns_status, line_idx, msg_start - 1, #line, "GitladCommitMsg")
          end
        else
          -- Branch name goes to end of line
          hl_module.set(bufnr, ns_status, line_idx, branch_start - 1, #line, "GitladRefCombined")
        end
      end

      -- Merge line: "Merge:    remote/branch  commit_msg [+n/-n]"
    elseif line:match("^Merge:") then
      hl_module.set(bufnr, ns_status, line_idx, 0, 6, "GitladMerge")
      local remote_start = line:find("%S", 11)
      if remote_start then
        local remote_end = line:find("%s", remote_start)
        if remote_end then
          local ref_name = line:sub(remote_start, remote_end - 1)
          -- Find ahead/behind indicator to determine if in sync
          local ahead_behind = line:match("%[%+%d+/%-?%d+%]")
          local is_in_sync = not ahead_behind -- No indicator means in sync

          -- Highlight the ref: combined (green prefix + red name) if in sync, else all green
          local slash_pos = ref_name:find("/")
          if is_in_sync and slash_pos then
            -- In sync: green prefix + muted red branch name
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              remote_start - 1,
              remote_start - 1 + slash_pos,
              "GitladRefRemote"
            )
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              remote_start - 1 + slash_pos,
              remote_end - 1,
              "GitladRefCombined"
            )
          else
            -- Not in sync or no slash: all green
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              remote_start - 1,
              remote_end - 1,
              "GitladRefRemote"
            )
          end

          if ahead_behind then
            local ab_start = line:find("%[%+%d+/%-?%d+%]")
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              ab_start - 1,
              ab_start - 1 + #ahead_behind,
              "GitladAheadBehind"
            )
            -- Commit message is between remote and ahead/behind
            local msg_start = line:find("%S", remote_end)
            if msg_start and msg_start < ab_start then
              hl_module.set(
                bufnr,
                ns_status,
                line_idx,
                msg_start - 1,
                ab_start - 2,
                "GitladCommitMsg"
              )
            end
          else
            -- Commit message goes to end
            local msg_start = line:find("%S", remote_end)
            if msg_start then
              hl_module.set(bufnr, ns_status, line_idx, msg_start - 1, #line, "GitladCommitMsg")
            end
          end
        else
          hl_module.set(bufnr, ns_status, line_idx, remote_start - 1, #line, "GitladRefRemote")
        end
      end

      -- Push line: "Push:     remote/branch  commit_msg [+n/-n]"
    elseif line:match("^Push:") then
      hl_module.set(bufnr, ns_status, line_idx, 0, 5, "GitladPush")
      local remote_start = line:find("%S", 11)
      if remote_start then
        local remote_end = line:find("%s", remote_start)
        if remote_end then
          local ref_name = line:sub(remote_start, remote_end - 1)
          -- Find ahead/behind indicator to determine if in sync
          local ahead_behind = line:match("%[%+%d+/%-?%d+%]")
          local is_in_sync = not ahead_behind -- No indicator means in sync

          -- Highlight the ref: combined (green prefix + red name) if in sync, else all green
          local slash_pos = ref_name:find("/")
          if is_in_sync and slash_pos then
            -- In sync: green prefix + muted red branch name
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              remote_start - 1,
              remote_start - 1 + slash_pos,
              "GitladRefRemote"
            )
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              remote_start - 1 + slash_pos,
              remote_end - 1,
              "GitladRefCombined"
            )
          else
            -- Not in sync or no slash: all green
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              remote_start - 1,
              remote_end - 1,
              "GitladRefRemote"
            )
          end

          if ahead_behind then
            local ab_start = line:find("%[%+%d+/%-?%d+%]")
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              ab_start - 1,
              ab_start - 1 + #ahead_behind,
              "GitladAheadBehind"
            )
            local msg_start = line:find("%S", remote_end)
            if msg_start and msg_start < ab_start then
              hl_module.set(
                bufnr,
                ns_status,
                line_idx,
                msg_start - 1,
                ab_start - 2,
                "GitladCommitMsg"
              )
            end
          else
            local msg_start = line:find("%S", remote_end)
            if msg_start then
              hl_module.set(bufnr, ns_status, line_idx, msg_start - 1, #line, "GitladCommitMsg")
            end
          end
        else
          hl_module.set(bufnr, ns_status, line_idx, remote_start - 1, #line, "GitladRefRemote")
        end
      end

      -- Status indicator line is always on line 0 (first line of buffer)
    elseif line_idx == 0 then
      M.apply_status_line_highlight(bufnr, ns_status, line_idx, line, hl_module)

      -- Section headers: "Staged (n)", "Unstaged (n)", "Unmerged into X (n)", etc.
      -- Expand indicators are now in sign column, not in text
    elseif section_lines[i] then
      local section_info = section_lines[i]
      local hl_group = section_hl[section_info.section]
      if hl_group then
        hl_module.set(bufnr, ns_status, line_idx, 0, #line, hl_group)
      end

      -- File entries: "● M path" or "●   path"
      -- Expand indicators are now in sign column, not in text
      -- Note: line_map may also contain commit entries (with type="commit"), so check for path
    elseif line_map[i] and line_map[i].path and not line_map[i].hunk_index then
      -- This is a file entry line (not a diff line)
      local file_info = line_map[i]
      local section = file_info.section

      -- Find the path in the line
      local path = file_info.path
      local path_start = line:find(vim.pesc(path), 1, true)
      if path_start then
        hl_module.set(
          bufnr,
          ns_status,
          line_idx,
          path_start - 1,
          path_start - 1 + #path,
          "GitladFilePath"
        )
      end

      -- Find and highlight status character (A, M, D, etc.)
      -- Status char appears after the sign and before the path
      local status_char_match = line:match("%s([AMDRCTU])%s")
      if status_char_match then
        -- Find exact position of the status character
        for j = 1, #line do
          if
            line:sub(j, j) == status_char_match
            and line:sub(j - 1, j - 1):match("%s")
            and line:sub(j + 1, j + 1):match("%s")
          then
            hl_module.set(
              bufnr,
              ns_status,
              line_idx,
              j - 1,
              j,
              status_char_hl[status_char_match] or "GitladFileStatus"
            )
            break
          end
        end
      end

      -- Highlight based on section for the sign
      if section == "staged" then
        -- Find sign position at start of line
        local sign_pos = line:find("[●○✦]")
        if sign_pos then
          hl_module.set(bufnr, ns_status, line_idx, sign_pos - 1, sign_pos + 2, "GitladFileAdded") -- UTF-8 chars are 3 bytes
        end
      elseif section == "untracked" then
        local sign_pos = line:find("[●○✦]")
        if sign_pos then
          hl_module.set(
            bufnr,
            ns_status,
            line_idx,
            sign_pos - 1,
            sign_pos + 2,
            "GitladSectionUntracked"
          )
        end
      end

      -- Diff lines (expanded file content)
      -- Match lines with hunk_index OR untracked file content (no hunk headers)
    elseif
      line_map[i]
      and (line_map[i].hunk_index or (line_map[i].section == "untracked" and line:match("^%+")))
    then
      -- This is a diff line - format: "@@ ..." or "+..." or "-..." or " context"
      local first_char = line:sub(1, 1)

      if line:match("^@@") then
        -- Hunk header line - use text highlight for the whole line
        -- Priority 150 to override treesitter (125) since headers aren't code
        hl_module.set(
          bufnr,
          ns_diff_markers,
          line_idx,
          0,
          #line,
          "GitladDiffHeader",
          { priority = 150 }
        )
      elseif first_char == "+" then
        -- Added line - use line background for diff color
        -- Priority 100 for background, treesitter (125) overrides for syntax colors
        hl_module.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffAdd", { priority = 100 })
        -- Highlight the + sign - priority 150 to stay visible over treesitter
        hl_module.set(
          bufnr,
          ns_diff_markers,
          line_idx,
          0,
          1,
          "GitladDiffAddSign",
          { priority = 150 }
        )
      elseif first_char == "-" then
        -- Deleted line - use line background for diff color
        -- Priority 100 for background, treesitter (125) overrides for syntax colors
        hl_module.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffDelete", { priority = 100 })
        -- Highlight the - sign - priority 150 to stay visible over treesitter
        hl_module.set(
          bufnr,
          ns_diff_markers,
          line_idx,
          0,
          1,
          "GitladDiffDeleteSign",
          { priority = 150 }
        )
      end
      -- Context lines (starting with space) don't need special highlighting

      -- Submodule SHA diff lines
    elseif line_map[i] and line_map[i].type == "submodule_diff" then
      if line_map[i].diff_type == "add" then
        hl_module.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffAdd", { priority = 100 })
        hl_module.set(
          bufnr,
          ns_diff_markers,
          line_idx,
          0,
          1,
          "GitladDiffAddSign",
          { priority = 150 }
        )
      elseif line_map[i].diff_type == "delete" then
        hl_module.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffDelete", { priority = 100 })
        hl_module.set(
          bufnr,
          ns_diff_markers,
          line_idx,
          0,
          1,
          "GitladDiffDeleteSign",
          { priority = 150 }
        )
      end

      -- Commit lines in unpulled/unpushed sections: "hash subject" (no indent)
    elseif line:match("^%x%x%x%x%x%x%x") then
      -- Commit line format: "abcdef1 commit message"
      hl_module.set(bufnr, ns_status, line_idx, 0, 7, "GitladCommitHash")
      if #line > 8 then
        hl_module.set(bufnr, ns_status, line_idx, 8, #line, "GitladCommitMsg")
      end

      -- Stash entries: "  stash@{N} message"
    elseif line_map[i] and line_map[i].type == "stash" then
      -- Highlight stash ref (e.g., "stash@{0}")
      local ref_start, ref_end = line:find("stash@{%d+}")
      if ref_start then
        hl_module.set(bufnr, ns_status, line_idx, ref_start - 1, ref_end, "GitladStashRef")
        -- Message is everything after the ref
        if ref_end < #line then
          hl_module.set(bufnr, ns_status, line_idx, ref_end + 1, #line, "GitladStashMessage")
        end
      end

      -- Submodule entries: "  + path/to/submodule (info)" or "    path/to/submodule (info)"
    elseif line_map[i] and line_map[i].type == "submodule" then
      -- Find the status indicator if present (+, -, U)
      local status_match = line:match("^%s+([%+%-U])")
      if status_match then
        local status_start = line:find("[%+%-U]")
        if status_start then
          hl_module.set(
            bufnr,
            ns_status,
            line_idx,
            status_start - 1,
            status_start,
            "GitladSubmoduleStatus"
          )
        end
      end
      -- Find path (before the parentheses)
      local path_start, path_end = line:find("[%w/_%-%.]+%s+%(")
      if path_start then
        -- Adjust to not include the space and paren
        local actual_end = line:find("%s+%(", path_start) or path_end
        hl_module.set(
          bufnr,
          ns_status,
          line_idx,
          path_start - 1,
          actual_end - 1,
          "GitladSubmodulePath"
        )
      end
      -- Find info in parentheses
      local info_start, info_end = line:find("%(.-%)$")
      if info_start then
        hl_module.set(bufnr, ns_status, line_idx, info_start - 1, info_end, "GitladSubmoduleInfo")
      end

      -- Worktree entries: "  * branch  ~/path" or "  L branch  ~/path" or "    branch  ~/path"
    elseif line_map[i] and line_map[i].type == "worktree" then
      -- Check for indicator (* for current, L for locked)
      local indicator = line:match("^%s+([%*L])%s")
      if indicator then
        local ind_start = line:find("[%*L]")
        if ind_start then
          local hl_group = indicator == "*" and "GitladWorktreeCurrent" or "GitladWorktreeLocked"
          hl_module.set(bufnr, ns_status, line_idx, ind_start - 1, ind_start, hl_group)
        end
      end
      -- Find branch name (after indicator/spaces, before double space and path)
      -- Pattern: leading spaces, optional indicator + space, then branch name, then double space, then path
      local branch_match = line:match("^%s+[%*L ]%s([^%s]+)")
      if branch_match then
        local branch_start = line:find(branch_match, 1, true)
        if branch_start then
          hl_module.set(
            bufnr,
            ns_status,
            line_idx,
            branch_start - 1,
            branch_start - 1 + #branch_match,
            "GitladWorktreeBranch"
          )
        end
      end
      -- Find path (after double space, starts with ~/ or /)
      local path_start = line:find("%s%s[~/]")
      if path_start then
        -- Skip the double space
        local actual_path_start = path_start + 2
        hl_module.set(
          bufnr,
          ns_status,
          line_idx,
          actual_path_start - 1,
          #line,
          "GitladWorktreePath"
        )
      end

      -- Help line
    elseif line:match("^Press %? for help") then
      hl_module.set(bufnr, ns_status, line_idx, 0, #line, "GitladHelpText")
    end
  end
end

--- Apply highlights to the history buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
---@param ns_history number History namespace
---@param hl_module table Reference to the hl module for set/clear functions
function M.apply_history_highlights(bufnr, lines, ns_history, hl_module)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous highlights
  hl_module.clear(bufnr, ns_history)

  for i, line in ipairs(lines) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Entry header: "✓ [HH:MM:SS] git command (Nms)" or "✗ [...]"
    if line:match("^[✓✗]%s+%[") then
      -- Success/failure icon (first character, but UTF-8 so 3 bytes)
      if line:match("^✓") then
        hl_module.set(bufnr, ns_history, line_idx, 0, 3, "GitladHistorySuccess")
      elseif line:match("^✗") then
        hl_module.set(bufnr, ns_history, line_idx, 0, 3, "GitladHistoryFailure")
      end

      -- Time: [HH:MM:SS]
      local time_start = line:find("%[")
      local time_end = line:find("%]")
      if time_start and time_end then
        hl_module.set(bufnr, ns_history, line_idx, time_start - 1, time_end, "GitladHistoryTime")
      end

      -- Command: "git command"
      local cmd_start = line:find("git%s")
      if cmd_start then
        local cmd_end = line:find("%s%(", cmd_start)
        if cmd_end then
          hl_module.set(
            bufnr,
            ns_history,
            line_idx,
            cmd_start - 1,
            cmd_end - 1,
            "GitladHistoryCommand"
          )
        end
      end

      -- Duration: "(Nms)"
      local dur_start = line:find("%(")
      local dur_end = line:find("%)$")
      if dur_start and dur_end then
        hl_module.set(bufnr, ns_history, line_idx, dur_start - 1, dur_end, "GitladHistoryDuration")
      end

      -- Label lines in expanded entries: "  cwd:", "  exit:", "  cmd:", "  stdout:", "  stderr:"
    elseif line:match("^%s%s[a-z]+:") then
      local label_end = line:find(":")
      if label_end then
        hl_module.set(bufnr, ns_history, line_idx, 2, label_end, "Comment")
      end

      -- Title line
    elseif line:match("^Git Command History") then
      hl_module.set(bufnr, ns_history, line_idx, 0, #line, "Title")

      -- Help line
    elseif line:match("^Press") then
      hl_module.set(bufnr, ns_history, line_idx, 0, #line, "GitladHelpText")
    end
  end
end

--- Apply highlights to a popup buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
---@param switches table[] Switch definitions
---@param options table[] Option definitions
---@param actions table[] Action definitions
---@param action_positions? table<number, table<string, {col: number, len: number}>> Optional position metadata
---@param config_vars? table[] Config variable definitions
---@param config_positions? table<number, table<string, table>> Optional config position metadata
---@param ns_popup number Popup namespace
---@param hl_module table Reference to the hl module for set/clear functions
function M.apply_popup_highlights(
  bufnr,
  lines,
  switches,
  options,
  actions,
  action_positions,
  config_vars,
  config_positions,
  ns_popup,
  hl_module
)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous highlights
  hl_module.clear(bufnr, ns_popup)

  -- Build lookup for action keys
  local action_keys = {}
  for _, act in ipairs(actions) do
    if act.type == "action" and act.key then
      action_keys[act.key] = true
    end
  end

  -- Build lookup for switch keys
  local switch_keys = {}
  for _, sw in ipairs(switches) do
    switch_keys[sw.key] = sw.enabled
  end

  -- Build lookup for option keys
  local option_keys = {}
  for _, opt in ipairs(options) do
    option_keys[opt.key] = true
  end

  for i, line in ipairs(lines) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Section headings: "Arguments" or action group headings (no leading space, no key pattern)
    -- For multi-column, headings can appear anywhere but still start with capital letter
    -- Check for heading pattern: starts with capital, followed by lowercase (word boundary)
    local is_heading = false
    -- Check at start of line
    if line:match("^[A-Z][a-z]") then
      is_heading = true
      -- Find the end of the heading (next whitespace or end of line for single-column,
      -- or check for column pattern)
      local heading_end = line:find("%s%s%s%s") or #line
      hl_module.set(bufnr, ns_popup, line_idx, 0, heading_end, "GitladPopupHeading")
    end
    -- Check for headings in additional columns (after significant whitespace)
    for match_start, heading in line:gmatch("()%s%s%s%s([A-Z][a-z]+)") do
      local heading_start = match_start + 3 -- After the 4-space gap
      local heading_len = #heading
      hl_module.set(
        bufnr,
        ns_popup,
        line_idx,
        heading_start,
        heading_start + heading_len,
        "GitladPopupHeading"
      )
    end

    -- Switch line: " *-a description (--flag)" or "  -a description"
    if line:match("^%s[%*%s]%-") then
      -- Check if enabled (has *)
      if line:match("^%s%*%-") then
        hl_module.set(bufnr, ns_popup, line_idx, 1, 2, "GitladPopupSwitchEnabled")
      end
      -- Highlight the -key part
      local key_start = line:find("%-")
      if key_start then
        hl_module.set(
          bufnr,
          ns_popup,
          line_idx,
          key_start - 1,
          key_start + 1,
          "GitladPopupSwitchKey"
        )
      end
      -- Highlight the (--flag) part at the end
      local cli_start = line:find("%(%-%-")
      if cli_start then
        hl_module.set(bufnr, ns_popup, line_idx, cli_start - 1, #line, "GitladPopupValue")
      end

      -- Option line: "  =a description (--opt=value)"
    elseif line:match("^%s%s=") then
      -- Highlight the =key part
      local eq_pos = line:find("=")
      if eq_pos then
        hl_module.set(bufnr, ns_popup, line_idx, eq_pos - 1, eq_pos + 1, "GitladPopupOptionKey")
      end
      -- Highlight the (--opt=value) part at the end
      local cli_start = line:find("%(%-%-")
      if cli_start then
        hl_module.set(bufnr, ns_popup, line_idx, cli_start - 1, #line, "GitladPopupValue")
      end

      -- Action lines - use position metadata if available, otherwise pattern match
    end

    -- Config var highlighting - use position metadata
    local config_line_positions = config_positions and config_positions[i]
    if config_line_positions then
      for key, pos in pairs(config_line_positions) do
        -- Highlight the key
        hl_module.set(bufnr, ns_popup, line_idx, pos.col, pos.col + pos.len, "GitladPopupConfigKey")

        -- Find and highlight the label (config key path after the key)
        -- Pattern: " k label value" - label starts after "k "
        local label_start = pos.col + pos.len + 1 -- After key and space
        local label = pos.config_key
        if label then
          -- Find where the label ends in the line (before the value)
          local label_end = label_start + #label
          if label_end <= #line then
            hl_module.set(
              bufnr,
              ns_popup,
              line_idx,
              label_start,
              label_end,
              "GitladPopupConfigLabel"
            )
          end

          -- Highlight the value portion
          -- Value starts after the label and some spacing
          local value_start_pattern = line:sub(label_end + 1):match("^%s*()")
          if value_start_pattern then
            local value_start = label_end + value_start_pattern - 1
            local value_text = line:sub(value_start + 1)

            if value_text == "unset" then
              hl_module.set(bufnr, ns_popup, line_idx, value_start, #line, "GitladPopupConfigUnset")
            elseif value_text:match("^%[") then
              -- Choice format: [opt1|opt2|default:X] or [remote1|remote2|fallback:value]
              -- Highlight the whole thing as choice, then highlight active value
              hl_module.set(
                bufnr,
                ns_popup,
                line_idx,
                value_start,
                #line,
                "GitladPopupConfigChoice"
              )

              -- Find and highlight the active choice
              if pos.var_type == "remote_cycle" and pos.remote_choices then
                -- For remote_cycle, determine effective value (current or fallback)
                local effective_value = pos.current_value
                if (effective_value == nil or effective_value == "") and pos.fallback_value then
                  -- Value comes from fallback - highlight the fallback annotation
                  local fallback_annotation = pos.fallback .. ":" .. pos.fallback_value
                  local annot_start, annot_end = value_text:find(fallback_annotation, 1, true)
                  if annot_start then
                    hl_module.set(
                      bufnr,
                      ns_popup,
                      line_idx,
                      value_start + annot_start - 1,
                      value_start + annot_end,
                      "GitladPopupConfigActive"
                    )
                  end
                elseif effective_value and effective_value ~= "" then
                  -- Value is explicitly set, highlight it
                  local choice_start, choice_end = value_text:find(effective_value, 1, true)
                  if choice_start then
                    hl_module.set(
                      bufnr,
                      ns_popup,
                      line_idx,
                      value_start + choice_start - 1,
                      value_start + choice_end,
                      "GitladPopupConfigActive"
                    )
                  end
                end
              elseif pos.choices then
                -- Standard cycle type
                local current = pos.current_value
                for _, choice in ipairs(pos.choices) do
                  local choice_to_find = choice
                  if choice == "" then
                    choice_to_find = pos.default_display or "default"
                  end
                  if (choice == "" and (current == nil or current == "")) or choice == current then
                    -- Find this choice in the value text and highlight it
                    local choice_start, choice_end = value_text:find(choice_to_find, 1, true)
                    if choice_start then
                      hl_module.set(
                        bufnr,
                        ns_popup,
                        line_idx,
                        value_start + choice_start - 1,
                        value_start + choice_end,
                        "GitladPopupConfigActive"
                      )
                    end
                    break
                  end
                end
              end
            else
              -- Plain text value
              hl_module.set(bufnr, ns_popup, line_idx, value_start, #line, "GitladPopupConfigValue")
            end
          end
        end
      end
    end

    -- Always check position metadata for action highlighting (works for multi-column)
    -- This is separate from heading detection because a line can have both a heading
    -- in one column and actions in another column
    local line_positions = action_positions and action_positions[i]
    if line_positions then
      -- Use precise position metadata
      for key, pos in pairs(line_positions) do
        hl_module.set(bufnr, ns_popup, line_idx, pos.col, pos.col + pos.len, "GitladPopupActionKey")
      end
    elseif not is_heading then
      -- Fallback: pattern match for action keys (single column only)
      for key, _ in pairs(action_keys) do
        -- Escape special pattern characters in the key
        local escaped_key = key:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
        local pattern = "^%s" .. escaped_key .. "%s"
        if line:match(pattern) then
          -- Key starts at position 1 (after leading space), length is #key
          hl_module.set(bufnr, ns_popup, line_idx, 1, 1 + #key, "GitladPopupActionKey")
          break
        end
      end
    end
  end
end

return M
