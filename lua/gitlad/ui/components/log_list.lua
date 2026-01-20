---@mod gitlad.ui.components.log_list Reusable commit list component
---@brief [[
--- A stateless component for rendering commit lists.
--- Used by status buffer (unpushed/unpulled sections), log view, and refs view.
---@brief ]]

local M = {}

---@class LogListOptions
---@field section string|nil Section name for line_info (e.g., "unpushed_upstream", "log")
---@field indent number|nil Spaces to indent (default: 2)
---@field show_author boolean|nil Show author column (default: false)
---@field show_date boolean|nil Show relative date (default: false)
---@field show_refs boolean|nil Show refs on commits (default: true)
---@field hash_length number|nil Characters of hash to show (default: 7)
---@field max_subject_len number|nil Truncate subject at this length (default: nil, no truncation)

---@class CommitLineInfo
---@field type "commit" Discriminator for union type
---@field hash string Commit hash
---@field commit GitCommitInfo Full commit info
---@field section string Which section this belongs to
---@field expanded boolean|nil Whether details are expanded
---@field displayed_refs CommitRef[]|nil Filtered refs actually displayed on this line

---@class LogListResult
---@field lines string[] Formatted lines
---@field line_info table<number, CommitLineInfo> Maps line index (1-based) to commit info
---@field commit_ranges table<string, {start: number, end_line: number}> Hash → line range (for expansion)

--- Format refs for display (no brackets, space-separated)
--- Skips the current branch (is_head) and remote HEAD refs since they're obvious from context
---@param refs CommitRef[] Array of refs
---@return string Formatted refs string (e.g., "origin/main v1.0.0 ")
---@return CommitRef[] filtered_refs The refs that were actually included
local function format_refs(refs)
  if not refs or #refs == 0 then
    return "", {}
  end

  local parts = {}
  local filtered = {}
  local first = true
  for _, ref in ipairs(refs) do
    -- Skip the current branch (HEAD) - it's obvious from context
    -- Also skip remote HEAD refs like "origin/HEAD"
    local is_remote_head = ref.name:match("/HEAD$")
    if not ref.is_head and not is_remote_head then
      if not first then
        table.insert(parts, " ")
      end
      first = false
      table.insert(parts, ref.name)
      table.insert(filtered, ref)
    end
  end

  if #filtered == 0 then
    return "", {}
  end

  table.insert(parts, " ")
  return table.concat(parts), filtered
end

--- Render a list of commits into formatted lines with metadata
---@param commits GitCommitInfo[] List of commits to render
---@param expanded_hashes table<string, boolean>|nil Which commits are expanded (keyed by hash)
---@param opts LogListOptions|nil Rendering options
---@return LogListResult
function M.render(commits, expanded_hashes, opts)
  opts = opts or {}
  expanded_hashes = expanded_hashes or {}
  local indent_str = string.rep(" ", opts.indent or 2)
  local hash_len = opts.hash_length or 7
  local section = opts.section or "log"
  local max_subject = opts.max_subject_len
  local show_refs = opts.show_refs ~= false -- Default to true

  local result = {
    lines = {},
    line_info = {},
    commit_ranges = {},
  }

  for _, commit in ipairs(commits) do
    local hash = commit.hash:sub(1, hash_len)
    local is_expanded = expanded_hashes[commit.hash]
    local range_start = #result.lines + 1

    -- Build the main commit line
    local subject = commit.subject or ""
    if max_subject and #subject > max_subject then
      subject = subject:sub(1, max_subject - 3) .. "..."
    end

    local parts = { indent_str, hash, " " }

    -- Add refs if present and show_refs is true (filtered to exclude current branch)
    local displayed_refs = {}
    if show_refs and commit.refs and #commit.refs > 0 then
      local refs_str
      refs_str, displayed_refs = format_refs(commit.refs)
      if #displayed_refs > 0 then
        table.insert(parts, refs_str)
      end
    end

    table.insert(parts, subject)

    -- Optionally add author
    if opts.show_author and commit.author then
      table.insert(parts, " (")
      table.insert(parts, commit.author)
      table.insert(parts, ")")
    end

    -- Optionally add date
    if opts.show_date and commit.date then
      table.insert(parts, " ")
      table.insert(parts, commit.date)
    end

    local line = table.concat(parts)
    table.insert(result.lines, line)
    result.line_info[#result.lines] = {
      type = "commit",
      hash = commit.hash,
      commit = commit,
      section = section,
      expanded = is_expanded or false,
      displayed_refs = displayed_refs, -- Filtered refs actually shown on this line
    }

    -- If expanded, add detail lines (body)
    if is_expanded and commit.body then
      local body_indent = indent_str .. "  "
      for body_line in commit.body:gmatch("[^\n]+") do
        table.insert(result.lines, body_indent .. body_line)
        result.line_info[#result.lines] = {
          type = "commit",
          hash = commit.hash,
          commit = commit,
          section = section,
          expanded = true,
        }
      end
    end

    result.commit_ranges[commit.hash] = {
      start = range_start,
      end_line = #result.lines,
    }
  end

  return result
end

--- Get unique commits within a line range
--- Useful for visual selection - handles deduplication and filters non-commit lines
---@param line_info table<number, CommitLineInfo> Line info map (can be sparse)
---@param start_line number Start of range (1-indexed)
---@param end_line number End of range (1-indexed, inclusive)
---@return GitCommitInfo[] Unique commits in selection order
function M.get_commits_in_range(line_info, start_line, end_line)
  local seen = {}
  local commits = {}

  for line = start_line, end_line do
    local info = line_info[line]
    if info and info.type == "commit" and not seen[info.hash] then
      seen[info.hash] = true
      table.insert(commits, info.commit)
    end
  end

  return commits
end

--- Get highlight group for a ref based on its type (non-combined refs only)
---@param ref CommitRef
---@return string highlight group name
local function get_ref_highlight_group(ref)
  if ref.type == "tag" then
    return "GitladRefTag"
  elseif ref.type == "remote" then
    return "GitladRefRemote"
  else -- local
    return "GitladRefLocal"
  end
end

--- Apply syntax highlighting to rendered log list
---@param bufnr number Buffer number
---@param start_line number 0-indexed line where the log list starts in buffer
---@param result LogListResult The render result to highlight
function M.apply_highlights(bufnr, start_line, result)
  local ok, hl = pcall(require, "gitlad.ui.hl")
  if not ok then
    return
  end

  local ns = hl.get_namespaces().status

  for i, line in ipairs(result.lines) do
    local line_idx = start_line + i - 1
    local info = result.line_info[i]

    if info and info.type == "commit" then
      -- Find the hash in the line (7+ hex chars)
      local hash_start, hash_end = line:find("%x%x%x%x%x%x%x+")
      if hash_start then
        -- Highlight the hash
        hl.set(bufnr, ns, line_idx, hash_start - 1, hash_end, "GitladCommitHash")

        -- Track position after hash for refs highlighting
        local pos = hash_end + 2 -- After hash and space
        local subject_start = pos -- Default: right after hash + space

        -- Highlight refs if present (use displayed_refs which excludes current branch)
        local refs = info.displayed_refs or {}
        if #refs > 0 then
          for _, ref in ipairs(refs) do
            -- For combined refs, highlight prefix and name separately
            if ref.is_combined and ref.remote_prefix then
              -- Highlight remote prefix (e.g., "origin/")
              local prefix_len = #ref.remote_prefix
              hl.set(bufnr, ns, line_idx, pos - 1, pos - 1 + prefix_len, "GitladRefRemote")
              pos = pos + prefix_len

              -- Highlight branch name with combined color (muted red)
              local branch_name = ref.name:sub(prefix_len + 1) -- Remove prefix from name
              local branch_len = #branch_name
              hl.set(bufnr, ns, line_idx, pos - 1, pos - 1 + branch_len, "GitladRefCombined")
              pos = pos + branch_len
            else
              -- Regular ref - highlight entire name
              local ref_len = #ref.name
              local ref_hl = get_ref_highlight_group(ref)
              hl.set(bufnr, ns, line_idx, pos - 1, pos - 1 + ref_len, ref_hl)
              pos = pos + ref_len
            end

            -- Space after ref (last ref has trailing space before subject)
            pos = pos + 1
          end
          subject_start = pos
        end

        -- Highlight subject
        if subject_start <= #line then
          -- Find where subject ends (before author in parens, or end of line)
          local subject_end = line:find(" %(", subject_start)
          if subject_end then
            hl.set(bufnr, ns, line_idx, subject_start - 1, subject_end - 1, "GitladCommitMsg")
            -- Highlight author in parens if present
            local author_start, author_end = line:find("%(.-%)$")
            if author_start then
              hl.set(bufnr, ns, line_idx, author_start - 1, author_end, "GitladCommitAuthor")
            end
          else
            -- No author, subject goes to end
            hl.set(bufnr, ns, line_idx, subject_start - 1, #line, "GitladCommitMsg")
          end
        end
      elseif info.expanded then
        -- This is a body line (expanded commit detail)
        -- Use commit body highlighting
        hl.set(bufnr, ns, line_idx, 0, #line, "GitladCommitBody")
      end
    end
  end
end

return M
