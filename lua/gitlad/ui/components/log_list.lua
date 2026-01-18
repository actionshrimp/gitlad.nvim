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
---@field hash_length number|nil Characters of hash to show (default: 7)
---@field max_subject_len number|nil Truncate subject at this length (default: nil, no truncation)

---@class CommitLineInfo
---@field type "commit" Discriminator for union type
---@field hash string Commit hash
---@field commit GitCommitInfo Full commit info
---@field section string Which section this belongs to
---@field expanded boolean|nil Whether details are expanded

---@class LogListResult
---@field lines string[] Formatted lines
---@field line_info table<number, CommitLineInfo> Maps line index (1-based) to commit info
---@field commit_ranges table<string, {start: number, end_line: number}> Hash → line range (for expansion)

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

    local parts = { indent_str, hash, " ", subject }

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

        -- Subject is everything after hash + space
        local subject_start = hash_end + 2 -- +1 for space, +1 for 1-indexing
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
