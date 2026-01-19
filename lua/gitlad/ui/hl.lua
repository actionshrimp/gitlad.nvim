---@mod gitlad.ui.hl Highlight system for gitlad
---@brief [[
--- Provides syntax highlighting for status buffer, history view, and popups.
--- Uses extmarks for precise, layerable highlighting.
---@brief ]]

local M = {}

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

  -- Stash entries
  GitladStashRef = { link = "Constant" },
  GitladStashMessage = { link = "Comment" },

  -- Submodule entries
  GitladSubmodulePath = { link = "Directory" },
  GitladSubmoduleStatus = { link = "Special" },
  GitladSubmoduleInfo = { link = "Comment" },

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
  GitladHistoryCommand = { link = "Function" },
  GitladHistoryDuration = { link = "Number" },

  -- Popup
  GitladPopupHeading = { link = "Title" },
  GitladPopupSwitchKey = { link = "Special" },
  GitladPopupSwitchEnabled = { link = "DiagnosticOk" },
  GitladPopupOptionKey = { link = "Keyword" },
  GitladPopupActionKey = { link = "Keyword" },
  GitladPopupDescription = { link = "Normal" },
  GitladPopupValue = { link = "String" },

  -- Help text
  GitladHelpText = { link = "Comment" },

  -- Status indicator (spinner/idle)
  GitladStatusSpinner = { link = "DiagnosticInfo" },
  GitladStatusIdle = { link = "Comment" },
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
-- Language detection utilities
-- =============================================================================

-- Extension to language mapping
-- Extends/overrides vim.filetype.match for common cases
local extension_lang_map = {
  lua = "lua",
  py = "python",
  js = "javascript",
  ts = "typescript",
  tsx = "tsx",
  jsx = "javascript",
  rs = "rust",
  go = "go",
  rb = "ruby",
  c = "c",
  cpp = "cpp",
  h = "c",
  hpp = "cpp",
  java = "java",
  kt = "kotlin",
  swift = "swift",
  sh = "bash",
  bash = "bash",
  zsh = "zsh",
  fish = "fish",
  vim = "vim",
  json = "json",
  yaml = "yaml",
  yml = "yaml",
  toml = "toml",
  xml = "xml",
  html = "html",
  css = "css",
  scss = "scss",
  md = "markdown",
  sql = "sql",
  zig = "zig",
  ex = "elixir",
  exs = "elixir",
  erl = "erlang",
  hs = "haskell",
  ml = "ocaml",
  nix = "nix",
  tf = "terraform",
  dockerfile = "dockerfile",
}

--- Get the treesitter language for a file path
---@param path string File path
---@return string|nil lang Language name or nil if unknown
function M.get_lang_for_path(path)
  if not path or path == "" then
    return nil
  end

  -- Extract extension
  local ext = path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    -- Check our extension map first
    if extension_lang_map[ext] then
      return extension_lang_map[ext]
    end
  end

  -- Try vim.filetype.match for more obscure extensions
  local ft = vim.filetype.match({ filename = path })
  if ft then
    -- For most languages, filetype == treesitter language
    -- But some need mapping (e.g., "python" filetype works as-is)
    return ft
  end

  return nil
end

--- Check if a treesitter parser is available for a language
---@param lang string Language name
---@return boolean
function M.parser_available(lang)
  if not lang then
    return false
  end

  -- Try to get the language configuration
  local ok = pcall(vim.treesitter.language.inspect, lang)
  return ok
end

--- Get highlight query for a language
---@param lang string Language name
---@return vim.treesitter.Query|nil query
function M.get_highlight_query(lang)
  if not lang or not M.parser_available(lang) then
    return nil
  end

  local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if ok and query then
    return query
  end

  return nil
end

-- =============================================================================
-- Status view highlighting
-- =============================================================================

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
  -- Stash and submodule sections
  stashes = "GitladSectionStashes",
  submodules = "GitladSectionSubmodules",
  -- Commit sections
  unpulled_upstream = "GitladSectionUnpulled",
  unpushed_upstream = "GitladSectionUnpushed",
  unpulled_push = "GitladSectionUnpulled",
  unpushed_push = "GitladSectionUnpushed",
  recent = "GitladSectionRecent",
}

--- Apply highlight to a status indicator line
--- Used both during full render and during spinner animation updates
---@param bufnr number Buffer number
---@param ns number Namespace for extmarks
---@param line_idx number 0-indexed line number
---@param line string The line content
function M.apply_status_line_highlight(bufnr, ns, line_idx, line)
  -- Clear any existing highlight on this line
  vim.api.nvim_buf_clear_namespace(bufnr, ns, line_idx, line_idx + 1)

  -- Check if this is the spinner (refreshing) or idle state
  local is_spinning = line:match("Refreshing")
  local hl_group = is_spinning and "GitladStatusSpinner" or "GitladStatusIdle"
  M.set(bufnr, ns, line_idx, 0, #line, hl_group)
end

--- Apply highlights to the status buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
---@param line_map table<number, LineInfo> Map of line numbers to file info (1-indexed)
---@param section_lines table<number, SectionInfo> Map of line numbers to section info (1-indexed)
function M.apply_status_highlights(bufnr, lines, line_map, section_lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous highlights
  M.clear(bufnr, ns_status)
  M.clear(bufnr, ns_diff_markers)

  for i, line in ipairs(lines) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Head line: "Head:     branch  commit_msg"
    if line:match("^Head:") then
      -- Highlight "Head:" label
      M.set(bufnr, ns_status, line_idx, 0, 5, "GitladHead")
      -- Find and highlight branch name
      local branch_start = line:find("%S", 11) -- After "Head:     "
      if branch_start then
        local branch_end = line:find("%s", branch_start)
        if branch_end then
          M.set(bufnr, ns_status, line_idx, branch_start - 1, branch_end - 1, "GitladBranch")
          -- Rest is commit message
          local msg_start = line:find("%S", branch_end)
          if msg_start then
            M.set(bufnr, ns_status, line_idx, msg_start - 1, #line, "GitladCommitMsg")
          end
        else
          -- Branch name goes to end of line
          M.set(bufnr, ns_status, line_idx, branch_start - 1, #line, "GitladBranch")
        end
      end

      -- Merge line: "Merge:    remote/branch  commit_msg [+n/-n]"
    elseif line:match("^Merge:") then
      M.set(bufnr, ns_status, line_idx, 0, 6, "GitladMerge")
      local remote_start = line:find("%S", 11)
      if remote_start then
        local remote_end = line:find("%s", remote_start)
        if remote_end then
          M.set(bufnr, ns_status, line_idx, remote_start - 1, remote_end - 1, "GitladRemote")
          -- Find ahead/behind indicator
          local ahead_behind = line:match("%[%+%d+/%-?%d+%]")
          if ahead_behind then
            local ab_start = line:find("%[%+%d+/%-?%d+%]")
            M.set(
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
              M.set(bufnr, ns_status, line_idx, msg_start - 1, ab_start - 2, "GitladCommitMsg")
            end
          else
            -- Commit message goes to end
            local msg_start = line:find("%S", remote_end)
            if msg_start then
              M.set(bufnr, ns_status, line_idx, msg_start - 1, #line, "GitladCommitMsg")
            end
          end
        else
          M.set(bufnr, ns_status, line_idx, remote_start - 1, #line, "GitladRemote")
        end
      end

      -- Push line: "Push:     remote/branch  commit_msg [+n/-n]"
    elseif line:match("^Push:") then
      M.set(bufnr, ns_status, line_idx, 0, 5, "GitladPush")
      local remote_start = line:find("%S", 11)
      if remote_start then
        local remote_end = line:find("%s", remote_start)
        if remote_end then
          M.set(bufnr, ns_status, line_idx, remote_start - 1, remote_end - 1, "GitladRemote")
          -- Find ahead/behind indicator
          local ahead_behind = line:match("%[%+%d+/%-?%d+%]")
          if ahead_behind then
            local ab_start = line:find("%[%+%d+/%-?%d+%]")
            M.set(
              bufnr,
              ns_status,
              line_idx,
              ab_start - 1,
              ab_start - 1 + #ahead_behind,
              "GitladAheadBehind"
            )
            local msg_start = line:find("%S", remote_end)
            if msg_start and msg_start < ab_start then
              M.set(bufnr, ns_status, line_idx, msg_start - 1, ab_start - 2, "GitladCommitMsg")
            end
          else
            local msg_start = line:find("%S", remote_end)
            if msg_start then
              M.set(bufnr, ns_status, line_idx, msg_start - 1, #line, "GitladCommitMsg")
            end
          end
        else
          M.set(bufnr, ns_status, line_idx, remote_start - 1, #line, "GitladRemote")
        end
      end

      -- Status indicator line: "· " or "⠋ Refreshing..."
    elseif line:match("^[·⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]") then
      M.apply_status_line_highlight(bufnr, ns_status, line_idx, line)

      -- Section headers: "Staged (n)", "Unstaged (n)", "Unmerged into X (n)", etc.
      -- Expand indicators are now in sign column, not in text
    elseif section_lines[i] then
      local section_info = section_lines[i]
      local hl_group = section_hl[section_info.section]
      if hl_group then
        M.set(bufnr, ns_status, line_idx, 0, #line, hl_group)
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
        M.set(bufnr, ns_status, line_idx, path_start - 1, path_start - 1 + #path, "GitladFilePath")
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
            M.set(
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
          M.set(bufnr, ns_status, line_idx, sign_pos - 1, sign_pos + 2, "GitladFileAdded") -- UTF-8 chars are 3 bytes
        end
      elseif section == "untracked" then
        local sign_pos = line:find("[●○✦]")
        if sign_pos then
          M.set(bufnr, ns_status, line_idx, sign_pos - 1, sign_pos + 2, "GitladSectionUntracked")
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
        M.set(bufnr, ns_diff_markers, line_idx, 0, #line, "GitladDiffHeader", { priority = 150 })
      elseif first_char == "+" then
        -- Added line - use line background for diff color
        -- Priority 100 for background, treesitter (125) overrides for syntax colors
        M.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffAdd", { priority = 100 })
        -- Highlight the + sign - priority 150 to stay visible over treesitter
        M.set(bufnr, ns_diff_markers, line_idx, 0, 1, "GitladDiffAddSign", { priority = 150 })
      elseif first_char == "-" then
        -- Deleted line - use line background for diff color
        -- Priority 100 for background, treesitter (125) overrides for syntax colors
        M.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffDelete", { priority = 100 })
        -- Highlight the - sign - priority 150 to stay visible over treesitter
        M.set(bufnr, ns_diff_markers, line_idx, 0, 1, "GitladDiffDeleteSign", { priority = 150 })
      end
      -- Context lines (starting with space) don't need special highlighting

      -- Submodule SHA diff lines
    elseif line_map[i] and line_map[i].type == "submodule_diff" then
      if line_map[i].diff_type == "add" then
        M.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffAdd", { priority = 100 })
        M.set(bufnr, ns_diff_markers, line_idx, 0, 1, "GitladDiffAddSign", { priority = 150 })
      elseif line_map[i].diff_type == "delete" then
        M.set_line(bufnr, ns_diff_markers, line_idx, "GitladDiffDelete", { priority = 100 })
        M.set(bufnr, ns_diff_markers, line_idx, 0, 1, "GitladDiffDeleteSign", { priority = 150 })
      end

      -- Commit lines in unpulled/unpushed sections: "hash subject" (no indent)
    elseif line:match("^%x%x%x%x%x%x%x") then
      -- Commit line format: "abcdef1 commit message"
      M.set(bufnr, ns_status, line_idx, 0, 7, "GitladCommitHash")
      if #line > 8 then
        M.set(bufnr, ns_status, line_idx, 8, #line, "GitladCommitMsg")
      end

      -- Stash entries: "  stash@{N} message"
    elseif line_map[i] and line_map[i].type == "stash" then
      -- Highlight stash ref (e.g., "stash@{0}")
      local ref_start, ref_end = line:find("stash@{%d+}")
      if ref_start then
        M.set(bufnr, ns_status, line_idx, ref_start - 1, ref_end, "GitladStashRef")
        -- Message is everything after the ref
        if ref_end < #line then
          M.set(bufnr, ns_status, line_idx, ref_end + 1, #line, "GitladStashMessage")
        end
      end

      -- Submodule entries: "  + path/to/submodule (info)" or "    path/to/submodule (info)"
    elseif line_map[i] and line_map[i].type == "submodule" then
      -- Find the status indicator if present (+, -, U)
      local status_match = line:match("^%s+([%+%-U])")
      if status_match then
        local status_start = line:find("[%+%-U]")
        if status_start then
          M.set(bufnr, ns_status, line_idx, status_start - 1, status_start, "GitladSubmoduleStatus")
        end
      end
      -- Find path (before the parentheses)
      local path_start, path_end = line:find("[%w/_%-%.]+%s+%(")
      if path_start then
        -- Adjust to not include the space and paren
        local actual_end = line:find("%s+%(", path_start) or path_end
        M.set(bufnr, ns_status, line_idx, path_start - 1, actual_end - 1, "GitladSubmodulePath")
      end
      -- Find info in parentheses
      local info_start, info_end = line:find("%(.-%)$")
      if info_start then
        M.set(bufnr, ns_status, line_idx, info_start - 1, info_end, "GitladSubmoduleInfo")
      end

      -- Help line
    elseif line:match("^Press %? for help") then
      M.set(bufnr, ns_status, line_idx, 0, #line, "GitladHelpText")
    end
  end
end

-- =============================================================================
-- Treesitter diff highlighting
-- =============================================================================

--- Apply treesitter syntax highlighting to diff content
--- This layers syntax highlighting on top of diff backgrounds
---@param bufnr number Buffer number
---@param diff_lines string[] The diff content lines (with +/- prefixes)
---@param start_line number 0-indexed line number where diff starts in buffer
---@param file_path string Path to the file (for language detection)
---@return boolean success Whether highlighting was applied
function M.highlight_diff_content(bufnr, diff_lines, start_line, file_path)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Detect language from file path
  local lang = M.get_lang_for_path(file_path)
  if not lang then
    return false
  end

  -- Check if parser is available
  if not M.parser_available(lang) then
    return false
  end

  -- Get highlight query
  local query = M.get_highlight_query(lang)
  if not query then
    return false
  end

  -- Strip diff markers and build parseable code
  -- Track line mapping: parsed_line_idx -> { buffer_line, col_offset }
  -- Note: We use explicit indexing instead of table.insert because
  -- table.insert(t, nil) is a no-op in Lua - it doesn't actually insert anything.
  -- This would cause line_mapping to be out of sync with code_lines.
  local code_lines = {}
  local line_mapping = {}

  for i, line in ipairs(diff_lines) do
    -- Diff lines have +/-/space marker at start, then content
    -- Format: "+content" or "-content" or " context"
    -- 1-indexed positions: 1 is marker, 2+ is content
    -- 0-indexed columns: 0 is marker, 1+ is content
    local first_char = line:sub(1, 1)

    if first_char == "+" or first_char == "-" or first_char == " " then
      -- Extract the actual code (after the diff marker)
      local code = line:sub(2) -- Everything after the marker
      code_lines[i] = code
      line_mapping[i] = {
        buffer_line = start_line + i - 1, -- 0-indexed
        col_offset = 1, -- 0-indexed column where code starts (1 = after marker)
      }
    elseif line:match("^@@") then
      -- Skip hunk headers - they're not code
      code_lines[i] = ""
      line_mapping[i] = nil -- Explicit nil to maintain index alignment
    else
      -- Unknown line format, skip
      code_lines[i] = ""
      line_mapping[i] = nil -- Explicit nil to maintain index alignment
    end
  end

  -- Join code for parsing
  local code = table.concat(code_lines, "\n")
  if code == "" then
    return false
  end

  -- Parse the code
  local ok, parser = pcall(vim.treesitter.get_string_parser, code, lang)
  if not ok or not parser then
    return false
  end

  local tree = parser:parse()[1]
  if not tree then
    return false
  end

  local root = tree:root()

  -- Apply highlights from treesitter captures
  -- Use higher priority (125) to ensure syntax colors override diff backgrounds
  -- but still allow the +/- sign highlights (priority 150) to show through
  for id, node, _ in query:iter_captures(root, code, 0, -1) do
    local capture_name = query.captures[id]
    local hl_group = "@" .. capture_name .. "." .. lang

    -- Check if this highlight group exists, fall back to base capture
    if vim.fn.hlexists(hl_group) == 0 then
      hl_group = "@" .. capture_name
    end

    local start_row, start_col, end_row, end_col = node:range()

    -- Map back to buffer positions
    for parsed_line = start_row, end_row do
      local mapping = line_mapping[parsed_line + 1] -- +1 for Lua 1-indexing
      if mapping then
        local buf_line = mapping.buffer_line
        local col_off = mapping.col_offset

        -- Get actual buffer line length to clamp values
        local buf_lines = vim.api.nvim_buf_get_lines(bufnr, buf_line, buf_line + 1, false)
        if #buf_lines == 0 then
          goto continue
        end
        local line_len = #buf_lines[1]

        local hl_start_col = (parsed_line == start_row) and (col_off + start_col) or col_off
        local hl_end_col
        if parsed_line == end_row then
          hl_end_col = col_off + end_col
        else
          -- Highlight to end of line content
          local line_content = code_lines[parsed_line + 1]
          hl_end_col = col_off + #line_content
        end

        -- Clamp to valid range
        hl_start_col = math.min(hl_start_col, line_len)
        hl_end_col = math.min(hl_end_col, line_len)

        -- Skip if invalid range
        if hl_start_col >= hl_end_col then
          goto continue
        end

        -- Apply highlight with priority higher than diff backgrounds (100)
        -- but lower than diff sign markers (150)
        M.set(bufnr, ns_diff_lang, buf_line, hl_start_col, hl_end_col, hl_group, { priority = 125 })
      end
      ::continue::
    end
  end

  return true
end

--- Apply treesitter highlighting to all expanded diffs in a status buffer
--- Call this after apply_status_highlights with the diff cache
---@param bufnr number Buffer number
---@param lines string[] The rendered buffer lines
---@param line_map table<number, LineInfo> Map of line numbers to file info (1-indexed)
---@param diff_cache table<string, DiffData> Map of cache keys to diff data
function M.apply_diff_treesitter_highlights(bufnr, lines, line_map, diff_cache)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous language highlights
  M.clear(bufnr, ns_diff_lang)

  -- Find all expanded file entries and their diff ranges
  local current_file = nil
  local diff_start_line = nil
  local diff_lines_for_file = {}

  for i, _ in ipairs(lines) do
    local info = line_map[i]
    local line = lines[i]

    -- Check if this is a diff content line (starts with +/-/space/@@)
    local is_diff_content = line:match("^[%+%-%s@]")

    if info and not is_diff_content then
      -- This is a file entry line (not diff content)
      -- If we were collecting diff lines for a previous file, process them
      if current_file and #diff_lines_for_file > 0 then
        M.highlight_diff_content(bufnr, diff_lines_for_file, diff_start_line, current_file)
      end

      -- Start tracking new file
      current_file = info.path
      diff_start_line = nil
      diff_lines_for_file = {}
    elseif info and is_diff_content then
      -- This is a diff line (staged/unstaged with hunk_index, or untracked content)
      if diff_start_line == nil then
        diff_start_line = i - 1 -- Convert to 0-indexed
      end
      table.insert(diff_lines_for_file, line)
    end
  end

  -- Process the last file if any
  if current_file and #diff_lines_for_file > 0 then
    M.highlight_diff_content(bufnr, diff_lines_for_file, diff_start_line, current_file)
  end
end

-- =============================================================================
-- History view highlighting
-- =============================================================================

--- Apply highlights to the history buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
function M.apply_history_highlights(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous highlights
  M.clear(bufnr, ns_history)

  for i, line in ipairs(lines) do
    local line_idx = i - 1 -- Convert to 0-indexed

    -- Entry header: "✓ [HH:MM:SS] git command (Nms)" or "✗ [...]"
    if line:match("^[✓✗]%s+%[") then
      -- Success/failure icon (first character, but UTF-8 so 3 bytes)
      if line:match("^✓") then
        M.set(bufnr, ns_history, line_idx, 0, 3, "GitladHistorySuccess")
      elseif line:match("^✗") then
        M.set(bufnr, ns_history, line_idx, 0, 3, "GitladHistoryFailure")
      end

      -- Time: [HH:MM:SS]
      local time_start = line:find("%[")
      local time_end = line:find("%]")
      if time_start and time_end then
        M.set(bufnr, ns_history, line_idx, time_start - 1, time_end, "GitladHistoryTime")
      end

      -- Command: "git command"
      local cmd_start = line:find("git%s")
      if cmd_start then
        local cmd_end = line:find("%s%(", cmd_start)
        if cmd_end then
          M.set(bufnr, ns_history, line_idx, cmd_start - 1, cmd_end - 1, "GitladHistoryCommand")
        end
      end

      -- Duration: "(Nms)"
      local dur_start = line:find("%(")
      local dur_end = line:find("%)$")
      if dur_start and dur_end then
        M.set(bufnr, ns_history, line_idx, dur_start - 1, dur_end, "GitladHistoryDuration")
      end

      -- Label lines in expanded entries: "  cwd:", "  exit:", "  cmd:", "  stdout:", "  stderr:"
    elseif line:match("^%s%s[a-z]+:") then
      local label_end = line:find(":")
      if label_end then
        M.set(bufnr, ns_history, line_idx, 2, label_end, "Comment")
      end

      -- Title line
    elseif line:match("^Git Command History") then
      M.set(bufnr, ns_history, line_idx, 0, #line, "Title")

      -- Help line
    elseif line:match("^Press") then
      M.set(bufnr, ns_history, line_idx, 0, #line, "GitladHelpText")
    end
  end
end

-- =============================================================================
-- Popup highlighting
-- =============================================================================

--- Apply highlights to a popup buffer
---@param bufnr number Buffer number
---@param lines string[] The rendered lines
---@param switches table[] Switch definitions
---@param options table[] Option definitions
---@param actions table[] Action definitions
function M.apply_popup_highlights(bufnr, lines, switches, options, actions)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous highlights
  M.clear(bufnr, ns_popup)

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
    if line:match("^[A-Z][a-z]") and not line:match("^%s") then
      M.set(bufnr, ns_popup, line_idx, 0, #line, "GitladPopupHeading")

      -- Switch line: " *-a description (--flag)" or "  -a description"
    elseif line:match("^%s[%*%s]%-") then
      -- Check if enabled (has *)
      if line:match("^%s%*%-") then
        M.set(bufnr, ns_popup, line_idx, 1, 2, "GitladPopupSwitchEnabled")
      end
      -- Highlight the -key part
      local key_start = line:find("%-")
      if key_start then
        M.set(bufnr, ns_popup, line_idx, key_start - 1, key_start + 1, "GitladPopupSwitchKey")
      end
      -- Highlight the (--flag) part at the end
      local cli_start = line:find("%(%-%-")
      if cli_start then
        M.set(bufnr, ns_popup, line_idx, cli_start - 1, #line, "GitladPopupValue")
      end

      -- Option line: "  =a description (--opt=value)"
    elseif line:match("^%s%s=") then
      -- Highlight the =key part
      local eq_pos = line:find("=")
      if eq_pos then
        M.set(bufnr, ns_popup, line_idx, eq_pos - 1, eq_pos + 1, "GitladPopupOptionKey")
      end
      -- Highlight the (--opt=value) part at the end
      local cli_start = line:find("%(%-%-")
      if cli_start then
        M.set(bufnr, ns_popup, line_idx, cli_start - 1, #line, "GitladPopupValue")
      end

      -- Action line: " a description"
    elseif line:match("^%s[a-zA-Z]%s") then
      -- Highlight the key
      local key = line:match("^%s([a-zA-Z])")
      if key and action_keys[key] then
        M.set(bufnr, ns_popup, line_idx, 1, 2, "GitladPopupActionKey")
      end
    end
  end
end

return M
