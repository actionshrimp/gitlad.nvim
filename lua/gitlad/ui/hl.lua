---@mod gitlad.ui.hl Highlight system for gitlad
---@brief [[
--- Provides syntax highlighting for status buffer, history view, and popups.
--- Uses extmarks for precise, layerable highlighting.
---
--- This module re-exports operations from submodules:
--- - hl_status: status buffer, history, and popup highlighting
--- - hl_diff: treesitter-based diff content highlighting
---@brief ]]

local M = {}

-- Import submodules
local hl_status = require("gitlad.ui.hl_status")
local hl_diff = require("gitlad.ui.hl_diff")

--- Get the foreground color from a highlight group
---@param group string Highlight group name
---@return string|nil fg Hex color string or nil
local function get_fg_from_group(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if ok and hl and hl.fg then
    return string.format("#%06x", hl.fg)
  end
  return nil
end

--- Create a bold section header highlight, inheriting color from a base group
---@param base_group string The group to inherit foreground from
---@param fallback_fg string Fallback color if base group has no foreground
---@return table highlight definition
local function bold_section_hl(base_group, fallback_fg)
  local fg = get_fg_from_group(base_group) or fallback_fg
  return { bold = true, fg = fg }
end

-- Namespaces for extmark highlighting
local ns_status = vim.api.nvim_create_namespace("gitlad_status")
local ns_diff_lang = vim.api.nvim_create_namespace("gitlad_diff_lang")
local ns_diff_markers = vim.api.nvim_create_namespace("gitlad_diff_markers")
local ns_history = vim.api.nvim_create_namespace("gitlad_history")
local ns_popup = vim.api.nvim_create_namespace("gitlad_popup")

-- Highlight group definitions
-- Each group links to a standard vim group for colorscheme compatibility
local highlight_groups = {
  -- Status UI - headers
  GitladHead = { link = "Title" },
  GitladMerge = { link = "Title" },
  GitladPush = { link = "Title" },
  GitladBranch = { link = "Identifier" },
  GitladRemote = { link = "String" },
  GitladAheadBehind = { link = "Number" },
  GitladCommitHash = { link = "Constant" },
  GitladCommitMsg = { link = "Comment" },
  GitladCommitAuthor = { link = "String" },
  GitladCommitDate = { link = "Comment" },
  GitladCommitBody = { link = "Normal" },

  -- Ref highlighting (branches, tags on commits)
  GitladRefLocal = { link = "diffRemoved" }, -- Muted red for local branches
  GitladRefRemote = { link = "DiagnosticOk" }, -- Green for remote branches
  GitladRefCombined = { link = "diffRemoved" }, -- Muted red for local part of combined refs
  GitladRefTag = { link = "Type" }, -- Tags (typically yellow/gold)
  GitladRefHead = { link = "DiagnosticWarn" }, -- HEAD indicator (orange)
  GitladRefSeparator = { link = "Comment" }, -- Parentheses and commas

  -- Section headers - all use a single common style (like magit/neogit)
  -- GitladSectionHeader is the base, all others link to it
  GitladSectionHeader = { link = "Title" },
  GitladSectionStaged = { link = "GitladSectionHeader" },
  GitladSectionUnstaged = { link = "GitladSectionHeader" },
  GitladSectionUntracked = { link = "GitladSectionHeader" },
  GitladSectionConflicted = { link = "GitladSectionHeader" },
  GitladSectionUnpulled = { link = "GitladSectionHeader" },
  GitladSectionUnpushed = { link = "GitladSectionHeader" },
  GitladSectionRecent = { link = "GitladSectionHeader" },
  GitladSectionStashes = { link = "GitladSectionHeader" },
  GitladSectionSubmodules = { link = "GitladSectionHeader" },
  GitladSectionWorktrees = { link = "GitladSectionHeader" },

  -- Stash entries
  GitladStashRef = { link = "Constant" },
  GitladStashMessage = { link = "Comment" },

  -- Submodule entries
  GitladSubmodulePath = { link = "Directory" },
  GitladSubmoduleStatus = { link = "Special" },
  GitladSubmoduleInfo = { link = "Comment" },

  -- Worktree entries
  GitladWorktreeBranch = { link = "Identifier" },
  GitladWorktreePath = { link = "Comment" },
  GitladWorktreeCurrent = { link = "DiagnosticOk" }, -- * indicator for current worktree
  GitladWorktreeLocked = { link = "DiagnosticWarn" }, -- L indicator for locked worktree
  GitladWorktreePending = { link = "DiagnosticInfo" }, -- Spinner for pending worktree operation

  -- File entries
  GitladFileAdded = { link = "DiffAdd" },
  GitladFileModified = { link = "DiffChange" },
  GitladFileDeleted = { link = "DiffDelete" },
  GitladFileRenamed = { link = "DiffChange" },
  GitladFileCopied = { link = "DiffAdd" },
  GitladFilePath = { link = "Directory" },
  GitladFileStatus = { link = "Special" },
  GitladExpandIndicator = { link = "Comment" },

  -- Diff content - line backgrounds for layered highlighting
  -- These define background colors that work with syntax highlighting on top
  GitladDiffHeader = { link = "DiffText" },
  GitladDiffAdd = { bg = "#2a4a2a" }, -- Dark green background
  GitladDiffDelete = { bg = "#4a2a2a" }, -- Dark red background
  GitladDiffContext = { link = "Normal" },
  GitladDiffNoParser = { link = "Comment" },
  -- Foreground-only variants for the +/- markers
  GitladDiffAddSign = { fg = "#4ade80" }, -- Green for + sign
  GitladDiffDeleteSign = { fg = "#f87171" }, -- Red for - sign

  -- History view
  GitladHistorySuccess = { link = "DiagnosticOk" },
  GitladHistoryFailure = { link = "DiagnosticError" },
  GitladHistoryTime = { link = "Comment" },
  GitladHistoryCommand = { link = "Title" },
  GitladHistoryDuration = { link = "Comment" },
  GitladHistoryLabel = { link = "Comment" },
  GitladHistoryPath = { link = "Directory" },
  GitladHistoryExitSuccess = { link = "DiagnosticOk" },
  GitladHistoryExitFailure = { link = "DiagnosticError" },
  GitladHistoryStdout = { link = "Normal" },
  GitladHistoryStderr = { link = "WarningMsg" },

  -- Popup
  GitladPopupHeading = { link = "Title" },
  GitladPopupSwitchKey = { link = "Special" },
  GitladPopupSwitchEnabled = { link = "DiagnosticOk" },
  GitladPopupOptionKey = { link = "Keyword" },
  GitladPopupActionKey = { link = "Keyword" },
  GitladPopupDescription = { link = "Normal" },
  GitladPopupValue = { link = "String" },

  -- Popup config section
  GitladPopupConfigKey = { link = "Keyword" },
  GitladPopupConfigLabel = { link = "Comment" },
  GitladPopupConfigValue = { link = "String" },
  GitladPopupConfigUnset = { link = "Comment", italic = true },
  GitladPopupConfigChoice = { link = "Type" },
  GitladPopupConfigActive = { link = "DiagnosticOk" },

  -- Help text
  GitladHelpText = { link = "Comment" },

  -- Status indicator (spinner/idle/stale)
  GitladStatusSpinner = { link = "DiagnosticInfo" },
  GitladStatusIdle = { link = "Comment" },
  GitladStatusStale = { link = "DiagnosticWarn" }, -- Warning color for stale indicator
  GitladStatusLineBackground = { bg = "#2a2a2a" }, -- Faint grey background for status line

  -- Output viewer (streaming command output)
  GitladOutputSuccess = { link = "DiagnosticOk" },
  GitladOutputFailure = { link = "DiagnosticError" },
  GitladOutputSpinner = { link = "DiagnosticInfo" },
  GitladOutputCommand = { link = "Comment" },
  GitladOutputSeparator = { link = "Comment" },
  GitladOutputStderr = { link = "DiagnosticError" },

  -- Reflog action type highlights (matching magit color scheme)
  GitladReflogCommit = { link = "DiagnosticOk" }, -- Green: commit, merge, cherry-pick, initial
  GitladReflogAmend = { link = "Special" }, -- Magenta: amend, rebase, rewritten
  GitladReflogCheckout = { link = "DiagnosticInfo" }, -- Blue: checkout, branch
  GitladReflogReset = { link = "DiagnosticError" }, -- Red: reset, restart
  GitladReflogPull = { link = "DiagnosticHint" }, -- Cyan: pull, clone
  GitladReflogSelector = { link = "Comment" }, -- For HEAD@{0} selectors

  -- Blame view
  GitladBlameHash = { link = "Constant" },
  GitladBlameAuthor = { link = "String" },
  GitladBlameDate = { link = "Number" },
  GitladBlameSummary = { link = "Normal" },
  GitladBlameUncommitted = { link = "DiagnosticWarn" },
  GitladBlameBoundary = { link = "DiagnosticHint" },
  GitladBlameChunkEven = { link = "CursorLine" }, -- Universal alternating chunk background
  GitladBlameChunkOdd = {}, -- Default background (no change)

  -- Forge (GitHub PRs)
  GitladForgePRNumber = { link = "Constant" },
  GitladForgePRAuthor = { link = "String" },
  GitladForgePRAdditions = { link = "DiffAdd" },
  GitladForgePRDeletions = { link = "DiffDelete" },
  GitladForgePRApproved = { link = "DiagnosticOk" },
  GitladForgePRChangesRequested = { link = "DiagnosticError" },
  GitladForgePRReviewRequired = { link = "DiagnosticWarn" },
  GitladForgePRDraft = { link = "Comment" },
  GitladForgePRTitle = { link = "Title" },
  GitladForgeCommentAuthor = { link = "String" },
  GitladForgeCommentTimestamp = { link = "Comment" },
  GitladForgeLabel = { link = "Type" },

  -- Rebase sequence (matching magit-sequence faces)
  GitladSequencePick = { link = "Normal" }, -- Pending actions (default fg)
  GitladSequenceDone = { link = "Comment" }, -- Completed commits (muted)
  GitladSequenceHead = { link = "DiagnosticInfo" }, -- Current HEAD commit (blue)
  GitladSequenceOnto = { link = "Comment" }, -- Base "onto" commit (muted)
  GitladSequenceStop = { link = "DiagnosticOk" }, -- Stopped commit (green)
  GitladSequenceDrop = { link = "DiagnosticError" }, -- Dropped commit (red)
  GitladSectionRebase = { link = "GitladSectionHeader" }, -- Rebase section header
}

-- Section header definition: single style for all section headers (like magit/neogit)
-- We only need to define the base GitladSectionHeader; others link to it
local section_header_def = { "Title", "#61afef" }

--- Set up all highlight groups
--- Should be called once during plugin setup
function M.setup()
  -- First set up all base highlight groups
  for group, def in pairs(highlight_groups) do
    vim.api.nvim_set_hl(0, group, def)
  end

  -- Override the base section header with bold version
  -- All section-specific headers link to this, so they inherit the style
  local base_group, fallback_fg = section_header_def[1], section_header_def[2]
  vim.api.nvim_set_hl(0, "GitladSectionHeader", bold_section_hl(base_group, fallback_fg))
end

--- Get namespace IDs for external use
---@return table<string, number>
function M.get_namespaces()
  return {
    status = ns_status,
    diff_lang = ns_diff_lang,
    diff_markers = ns_diff_markers,
    history = ns_history,
    popup = ns_popup,
  }
end

--- Clear all highlights from a buffer for a given namespace
---@param bufnr number Buffer number
---@param namespace number|string Namespace ID or name ("status", "diff_lang", "diff_markers", "history", "popup")
function M.clear(bufnr, namespace)
  local ns = namespace
  if type(namespace) == "string" then
    local namespaces = M.get_namespaces()
    ns = namespaces[namespace]
    if not ns then
      return
    end
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Set an extmark highlight on a buffer
---@param bufnr number Buffer number
---@param namespace number Namespace ID
---@param line number 0-indexed line number
---@param col_start number 0-indexed start column
---@param col_end number 0-indexed end column
---@param hl_group string Highlight group name
---@param opts? table Additional extmark options
function M.set(bufnr, namespace, line, col_start, col_end, hl_group, opts)
  opts = opts or {}
  local extmark_opts = vim.tbl_extend("force", {
    end_col = col_end,
    hl_group = hl_group,
  }, opts)
  vim.api.nvim_buf_set_extmark(bufnr, namespace, line, col_start, extmark_opts)
end

--- Set a line highlight (entire line)
---@param bufnr number Buffer number
---@param namespace number Namespace ID
---@param line number 0-indexed line number
---@param hl_group string Highlight group name
---@param opts? table Additional extmark options
function M.set_line(bufnr, namespace, line, hl_group, opts)
  opts = opts or {}
  local extmark_opts = vim.tbl_extend("force", {
    line_hl_group = hl_group,
  }, opts)
  vim.api.nvim_buf_set_extmark(bufnr, namespace, line, 0, extmark_opts)
end

--- Add virtual text at the end of a line
---@param bufnr number Buffer number
---@param namespace number Namespace ID
---@param line number 0-indexed line number
---@param text string Virtual text to display
---@param hl_group string Highlight group name
function M.add_virtual_text(bufnr, namespace, line, text, hl_group)
  vim.api.nvim_buf_set_extmark(bufnr, namespace, line, 0, {
    virt_text = { { text, hl_group } },
    virt_text_pos = "eol",
  })
end

-- =============================================================================
-- Re-exported functions from hl_diff (language detection utilities)
-- =============================================================================

--- Get the treesitter language for a file path
---@param path string File path
---@return string|nil lang Language name or nil if unknown
M.get_lang_for_path = hl_diff.get_lang_for_path

--- Check if a treesitter parser is available for a language
---@param lang string Language name
---@return boolean
M.parser_available = hl_diff.parser_available

--- Get highlight query for a language
---@param lang string Language name
---@return vim.treesitter.Query|nil query
M.get_highlight_query = hl_diff.get_highlight_query

-- =============================================================================
-- Wrapper functions that pass hl module reference to submodules
-- =============================================================================

--- Apply highlight to a status indicator line (full render)
--- Used during full render to set up both background and text highlights
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_idx number 0-indexed line number
---@param line string The line content
function M.apply_status_line_highlight(bufnr, ns, line_idx, line)
  hl_status.apply_status_line_highlight(bufnr, ns, line_idx, line, M)
end

--- Update just the text highlight on the status line (spinner animation)
--- Does not touch the background to avoid visual flicker during animation
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_idx number 0-indexed line number
---@param line string The line content
function M.update_status_line_text(bufnr, ns, line_idx, line)
  hl_status.update_status_line_text(bufnr, ns, line_idx, line, M)
end

--- Apply loading background to all lines (during initial load)
--- This creates a visual effect where the entire buffer has the faint background,
--- which transitions to just the first line once loading completes.
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_count number Total number of lines in buffer
function M.apply_loading_background(bufnr, ns, line_count)
  hl_status.apply_loading_background(bufnr, ns, line_count, M)
end

--- Apply highlights to the status buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
---@param line_map table<number, LineInfo> Map of line numbers to file info (1-indexed)
---@param section_lines table<number, SectionInfo> Map of line numbers to section info (1-indexed)
---@param opts? { local_upstream?: boolean } Optional rendering hints
function M.apply_status_highlights(bufnr, lines, line_map, section_lines, opts)
  hl_status.apply_status_highlights(
    bufnr,
    lines,
    line_map,
    section_lines,
    ns_status,
    ns_diff_markers,
    M,
    opts
  )
end

--- Apply treesitter syntax highlighting to diff content
--- This layers syntax highlighting on top of diff backgrounds
---@param bufnr number Buffer number
---@param diff_lines string[] The diff content lines (with +/- prefixes)
---@param start_line number 0-indexed line number where diff starts in buffer
---@param file_path string Path to the file (for language detection)
---@return boolean success Whether highlighting was applied
function M.highlight_diff_content(bufnr, diff_lines, start_line, file_path)
  return hl_diff.highlight_diff_content(bufnr, diff_lines, start_line, file_path, ns_diff_lang, M)
end

--- Apply treesitter highlighting to all expanded diffs in a status buffer
--- Call this after apply_status_highlights with the diff cache
---@param bufnr number Buffer number
---@param lines string[] The rendered buffer lines
---@param line_map table<number, LineInfo> Map of line numbers to file info (1-indexed)
---@param diff_cache table<string, DiffData> Map of cache keys to diff data
function M.apply_diff_treesitter_highlights(bufnr, lines, line_map, diff_cache)
  hl_diff.apply_diff_treesitter_highlights(bufnr, lines, line_map, diff_cache, ns_diff_lang, M)
end

--- Apply highlights to the history buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
function M.apply_history_highlights(bufnr, lines)
  hl_status.apply_history_highlights(bufnr, lines, ns_history, M)
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
function M.apply_popup_highlights(
  bufnr,
  lines,
  switches,
  options,
  actions,
  action_positions,
  config_vars,
  config_positions
)
  hl_status.apply_popup_highlights(
    bufnr,
    lines,
    switches,
    options,
    actions,
    action_positions,
    config_vars,
    config_positions,
    ns_popup,
    M
  )
end

return M
