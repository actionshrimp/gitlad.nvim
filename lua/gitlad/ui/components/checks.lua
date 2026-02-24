---@mod gitlad.ui.components.checks CI checks section component
---@brief [[
--- A stateless component for rendering CI check results in PR detail view.
--- Follows the same pattern as comment.lua and pr_list.lua.
---@brief ]]

local M = {}

local types = require("gitlad.forge.types")

---@class ChecksRenderOptions
---@field collapsed? boolean Whether the section is collapsed (default: false)
---@field sub_collapsed? table<string, boolean> Per-category collapsed state
---@field sub_threshold? number Min checks to trigger sub-section (default: 5)

---@class CheckLineInfo
---@field type string Line type discriminator
---@field check? ForgeCheck Check reference for check lines
---@field sub_category? string Category key for sub-section headers

---@class ChecksRenderResult
---@field lines string[] Formatted lines
---@field line_info table<number, CheckLineInfo> Maps line index (1-based) to line metadata
---@field ranges table<string, {start: number, end_line: number}> Named ranges

-- Category definitions in display order
M.categories = {
  { key = "failed", label = "Failed" },
  { key = "in_progress", label = "In progress" },
  { key = "successful", label = "Successful" },
  { key = "pending", label = "Pending" },
  { key = "skipped", label = "Skipped" },
}

--- Classify a check into a category key
---@param check ForgeCheck
---@return string category One of "failed", "in_progress", "successful", "pending", "skipped"
function M.classify_check(check)
  if check.status == "in_progress" then
    return "in_progress"
  end
  if check.status == "queued" then
    return "pending"
  end
  if check.status == "completed" then
    local c = check.conclusion
    if c == "failure" or c == "timed_out" or c == "startup_failure" then
      return "failed"
    elseif c == "success" then
      return "successful"
    elseif c == "action_required" then
      return "pending"
    elseif c == "cancelled" or c == "skipped" or c == "neutral" then
      return "skipped"
    end
  end
  return "pending"
end

--- Format a single check line
---@param check ForgeCheck
---@param indent string Indentation prefix
---@return string
local function format_check_line(check, indent)
  local icon, _ = types.format_check_icon(check)
  local parts = { indent .. icon .. " " .. check.name }

  if check.app_name then
    table.insert(parts, " (" .. check.app_name .. ")")
  end

  local duration = types.format_check_duration(check.started_at, check.completed_at)
  if duration ~= "" then
    table.insert(parts, "  " .. duration)
  end

  return table.concat(parts)
end

--- Render a checks section
---@param checks_summary ForgeChecksSummary
---@param opts? ChecksRenderOptions
---@return ChecksRenderResult
function M.render(checks_summary, opts)
  opts = opts or {}
  local collapsed = opts.collapsed or false
  local sub_collapsed = opts.sub_collapsed or {}
  local threshold = opts.sub_threshold or 5

  local result = {
    lines = {},
    line_info = {},
    ranges = {},
  }

  local function add_line(text, info)
    table.insert(result.lines, text or "")
    if info then
      result.line_info[#result.lines] = info
    end
  end

  -- Section header with summary counts
  local compact_text, _ = types.format_checks_compact(checks_summary)
  local collapse_indicator = collapsed and ">" or "v"
  local header = collapse_indicator .. " Checks (" .. compact_text .. ")"
  add_line(header, { type = "checks_header" })

  result.ranges["checks_header"] = { start = 1, end_line = 1 }

  if collapsed then
    return result
  end

  -- Classify checks into category buckets
  local buckets = {}
  for _, cat in ipairs(M.categories) do
    buckets[cat.key] = {}
  end
  for _, check in ipairs(checks_summary.checks) do
    local cat = M.classify_check(check)
    if buckets[cat] then
      table.insert(buckets[cat], check)
    end
  end

  -- Render each category
  local checks_start = #result.lines + 1
  for _, cat in ipairs(M.categories) do
    local checks = buckets[cat.key]
    if #checks > 0 then
      if #checks > threshold then
        -- Sub-section with header
        local is_collapsed = sub_collapsed[cat.key] or false
        local sub_indicator = is_collapsed and ">" or "v"
        local sub_header = "  " .. sub_indicator .. " " .. cat.label .. " (" .. #checks .. ")"
        add_line(sub_header, { type = "checks_sub_header", sub_category = cat.key })

        local sub_start = #result.lines
        if not is_collapsed then
          for _, check in ipairs(checks) do
            add_line(format_check_line(check, "    "), { type = "check", check = check })
          end
        end
        result.ranges["checks_sub_" .. cat.key] = { start = sub_start, end_line = #result.lines }
      else
        -- Flat rendering
        for _, check in ipairs(checks) do
          add_line(format_check_line(check, "  "), { type = "check", check = check })
        end
      end
    end
  end

  if #checks_summary.checks > 0 then
    result.ranges["checks"] = { start = checks_start, end_line = #result.lines }
  end

  return result
end

--- Apply syntax highlighting to a rendered checks section
---@param bufnr number Buffer number
---@param ns number Namespace ID
---@param start_line number 0-indexed line where the component starts in buffer
---@param result ChecksRenderResult The render result to highlight
function M.apply_highlights(bufnr, ns, start_line, result)
  local ok, hl = pcall(require, "gitlad.ui.hl")
  if not ok then
    return
  end

  for i, line in ipairs(result.lines) do
    local line_idx = start_line + i - 1
    local info = result.line_info[i]
    if not info then
      goto continue
    end

    if info.type == "checks_header" then
      hl.set(bufnr, ns, line_idx, 0, #line, "GitladSectionHeader")
    elseif info.type == "checks_sub_header" then
      hl.set(bufnr, ns, line_idx, 0, #line, "GitladSectionHeader")
    elseif info.type == "check" and info.check then
      -- Highlight the icon character based on check state
      local _, icon_hl = types.format_check_icon(info.check)
      local icon_start = line:find("[✓✗○◎⊘!]")
      if icon_start then
        -- UTF-8 icons are multi-byte; find the end
        local icon_end = icon_start
        local byte = line:byte(icon_start)
        if byte >= 0xC0 then
          -- Multi-byte UTF-8
          if byte >= 0xF0 then
            icon_end = icon_start + 3
          elseif byte >= 0xE0 then
            icon_end = icon_start + 2
          else
            icon_end = icon_start + 1
          end
        end
        hl.set(bufnr, ns, line_idx, icon_start - 1, icon_end, icon_hl)
      end

      -- Highlight duration (at end of line, after two spaces)
      local duration_start = line:find("  %d+[smh]", icon_start or 1)
      if duration_start then
        hl.set(bufnr, ns, line_idx, duration_start + 1, #line, "GitladForgeCommentTimestamp")
      end

      -- Highlight app name in parentheses
      local paren_start, paren_end = line:find("%b()")
      if paren_start then
        hl.set(bufnr, ns, line_idx, paren_start - 1, paren_end, "Comment")
      end
    end

    ::continue::
  end
end

return M
