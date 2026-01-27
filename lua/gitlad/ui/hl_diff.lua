---@mod gitlad.ui.hl_diff Diff content highlighting
---@brief [[
--- Treesitter-based diff highlighting for gitlad.
---@brief ]]

local M = {}

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

--- Apply treesitter syntax highlighting to diff content
--- This layers syntax highlighting on top of diff backgrounds
---@param bufnr number Buffer number
---@param diff_lines string[] The diff content lines (with +/- prefixes)
---@param start_line number 0-indexed line number where diff starts in buffer
---@param file_path string Path to the file (for language detection)
---@param ns_diff_lang number Namespace for diff language highlights
---@param hl_module table Reference to the hl module for set function
---@return boolean success Whether highlighting was applied
function M.highlight_diff_content(bufnr, diff_lines, start_line, file_path, ns_diff_lang, hl_module)
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
        hl_module.set(bufnr, ns_diff_lang, buf_line, hl_start_col, hl_end_col, hl_group, { priority = 125 })
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
---@param ns_diff_lang number Namespace for diff language highlights
---@param hl_module table Reference to the hl module for set/clear functions
function M.apply_diff_treesitter_highlights(bufnr, lines, line_map, diff_cache, ns_diff_lang, hl_module)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear previous language highlights
  hl_module.clear(bufnr, ns_diff_lang)

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
        M.highlight_diff_content(bufnr, diff_lines_for_file, diff_start_line, current_file, ns_diff_lang, hl_module)
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
    M.highlight_diff_content(bufnr, diff_lines_for_file, diff_start_line, current_file, ns_diff_lang, hl_module)
  end
end

return M
