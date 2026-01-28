---@mod gitlad.ui.components.reflog_list Reusable reflog list component
---@brief [[
--- A stateless component for rendering reflog entries.
--- Used by reflog view to display reflog history.
---@brief ]]

local M = {}

---@class ReflogListOptions
---@field section string|nil Section name for line_info (e.g., "reflog")
---@field indent number|nil Spaces to indent (default: 2)
---@field hash_length number|nil Characters of hash to show (default: 7)
---@field show_author boolean|nil Show author column (default: false)
---@field action_type_width number|nil Width of action type column (default: 14)

---@class ReflogLineInfo
---@field type "reflog" Discriminator for union type
---@field hash string Commit hash
---@field entry ReflogEntry Full entry info
---@field section string Which section this belongs to
---@field selector_start_col number 0-indexed column where selector starts
---@field selector_end_col number 0-indexed column where selector ends
---@field action_start_col number 0-indexed column where action type starts
---@field action_end_col number 0-indexed column where action type ends

---@class ReflogListResult
---@field lines string[] Formatted lines
---@field line_info table<number, ReflogLineInfo> Maps line index (1-based) to entry info
---@field entry_ranges table<string, {start: number, end_line: number}> Selector → line range

--- Pad or truncate a string to a fixed width
---@param str string
---@param width number
---@return string
local function pad_to_width(str, width)
  if #str >= width then
    return str:sub(1, width)
  end
  return str .. string.rep(" ", width - #str)
end

--- Render a list of reflog entries into formatted lines with metadata
---@param entries ReflogEntry[] List of entries to render
---@param opts ReflogListOptions|nil Rendering options
---@return ReflogListResult
function M.render(entries, opts)
  opts = opts or {}
  local indent_str = string.rep(" ", opts.indent or 2)
  local hash_len = opts.hash_length or 7
  local section = opts.section or "reflog"
  local action_width = opts.action_type_width or 14

  local result = {
    lines = {},
    line_info = {},
    entry_ranges = {},
  }

  for _, entry in ipairs(entries) do
    local hash = entry.hash:sub(1, hash_len)
    local range_start = #result.lines + 1

    -- Build the line: "  <hash> <selector>  <action_type>  <subject>"
    -- Track column positions for highlighting
    local parts = {}
    local col = 0

    -- Indent
    table.insert(parts, indent_str)
    col = col + #indent_str

    -- Hash
    table.insert(parts, hash)
    col = col + #hash

    -- Space
    table.insert(parts, " ")
    col = col + 1

    -- Selector (e.g., "HEAD@{0}")
    local selector_start_col = col
    local selector = entry.selector or ""
    table.insert(parts, selector)
    col = col + #selector
    local selector_end_col = col

    -- Two spaces
    table.insert(parts, "  ")
    col = col + 2

    -- Action type (fixed width, padded)
    local action_start_col = col
    local action_type = pad_to_width(entry.action_type or "unknown", action_width)
    table.insert(parts, action_type)
    col = col + #action_type
    local action_end_col = col

    -- Two spaces
    table.insert(parts, "  ")
    col = col + 2

    -- Subject (the message after the action type)
    -- Extract just the message part (after the colon in the full subject)
    local message = entry.subject or ""
    local _, colon_pos = message:find(":%s*")
    if colon_pos then
      message = message:sub(colon_pos + 1)
    end
    table.insert(parts, message)

    local line = table.concat(parts)
    table.insert(result.lines, line)
    result.line_info[#result.lines] = {
      type = "reflog",
      hash = entry.hash,
      entry = entry,
      section = section,
      selector_start_col = selector_start_col,
      selector_end_col = selector_end_col,
      action_start_col = action_start_col,
      action_end_col = action_end_col,
    }

    result.entry_ranges[entry.selector] = {
      start = range_start,
      end_line = #result.lines,
    }
  end

  return result
end

--- Get unique entries within a line range
--- Useful for visual selection - handles deduplication and filters non-reflog lines
---@param line_info table<number, ReflogLineInfo> Line info map (can be sparse)
---@param start_line number Start of range (1-indexed)
---@param end_line number End of range (1-indexed, inclusive)
---@return ReflogEntry[] Unique entries in selection order
function M.get_entries_in_range(line_info, start_line, end_line)
  local seen = {}
  local entries = {}

  for line = start_line, end_line do
    local info = line_info[line]
    if info and info.type == "reflog" and not seen[info.hash] then
      seen[info.hash] = true
      table.insert(entries, info.entry)
    end
  end

  return entries
end

--- Get the highlight group for an action type
---@param action_type string
---@return string highlight group name
local function get_action_highlight_group(action_type)
  -- Green: commit, merge, cherry-pick, initial
  if
    action_type == "commit"
    or action_type == "merge"
    or action_type == "cherry-pick"
    or action_type == "initial"
  then
    return "GitladReflogCommit"
  end

  -- Magenta: amend, rebase, rewritten
  if action_type == "amend" or action_type == "rebase" or action_type == "rewritten" then
    return "GitladReflogAmend"
  end

  -- Blue: checkout, branch
  if action_type == "checkout" or action_type == "branch" then
    return "GitladReflogCheckout"
  end

  -- Red: reset, restart
  if action_type == "reset" or action_type == "restart" then
    return "GitladReflogReset"
  end

  -- Cyan: pull, clone
  if action_type == "pull" or action_type == "clone" then
    return "GitladReflogPull"
  end

  -- Default: Comment color for unknown
  return "Comment"
end

--- Apply syntax highlighting to rendered reflog list
---@param bufnr number Buffer number
---@param start_line number 0-indexed line where the reflog list starts in buffer
---@param result ReflogListResult The render result to highlight
function M.apply_highlights(bufnr, start_line, result)
  local ok, hl = pcall(require, "gitlad.ui.hl")
  if not ok then
    return
  end

  local ns = hl.get_namespaces().status

  for i, line in ipairs(result.lines) do
    local line_idx = start_line + i - 1
    local info = result.line_info[i]

    if info and info.type == "reflog" then
      -- Find the hash in the line (7+ hex chars)
      local hash_start, hash_end = line:find("%x%x%x%x%x%x%x+")
      if hash_start then
        -- Highlight the hash
        hl.set(bufnr, ns, line_idx, hash_start - 1, hash_end, "GitladCommitHash")
      end

      -- Highlight the selector
      hl.set(
        bufnr,
        ns,
        line_idx,
        info.selector_start_col,
        info.selector_end_col,
        "GitladReflogSelector"
      )

      -- Highlight the action type with appropriate color
      local action_hl = get_action_highlight_group(info.entry.action_type)
      hl.set(bufnr, ns, line_idx, info.action_start_col, info.action_end_col, action_hl)

      -- The rest (message) gets default highlighting
    end
  end
end

return M
