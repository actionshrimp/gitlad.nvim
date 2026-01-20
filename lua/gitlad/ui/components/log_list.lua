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

---@class LogListResult
---@field lines string[] Formatted lines
---@field line_info table<number, CommitLineInfo> Maps line index (1-based) to commit info
---@field commit_ranges table<string, {start: number, end_line: number}> Hash → line range (for expansion)

--- Format refs for display
---@param refs CommitRef[] Array of refs
---@return string Formatted refs string (e.g., "(HEAD -> origin/main, v1.0.0) ")
local function format_refs(refs)
  if not refs or #refs == 0 then
    return ""
  end

  local parts = { "(" }
  for i, ref in ipairs(refs) do
    if i > 1 then
      table.insert(parts, ", ")
    end
    if ref.is_head then
      table.insert(parts, "HEAD -> ")
    end
    table.insert(parts, ref.name)
  end
  table.insert(parts, ") ")

  return table.concat(parts)
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

    -- Add refs if present and show_refs is true
    if show_refs and commit.refs and #commit.refs > 0 then
      table.insert(parts, format_refs(commit.refs))
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

--- Get highlight group for a ref based on its type
---@param ref CommitRef
---@return string highlight group name
local function get_ref_highlight_group(ref)
  if ref.is_combined then
    return "GitladRefCombined"
  elseif ref.type == "tag" then
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

        -- Check if there's a refs section immediately after hash
        -- Format after hash: " (refs) subject" or " subject"
        local after_hash = hash_end + 1
        local subject_start = after_hash + 1 -- default: right after hash + space

        -- Check for refs: "(refs) " pattern immediately after hash
        local refs_start, refs_end = line:find("%s%(", hash_end)
        if
          refs_start
          and refs_start == hash_end + 1
          and info.commit.refs
          and #info.commit.refs > 0
        then
          -- Found refs section - find the closing paren
          local close_paren = line:find("%)", refs_start)
          if close_paren then
            -- Highlight opening paren
            hl.set(bufnr, ns, line_idx, refs_start, refs_start + 1, "GitladRefSeparator")

            -- Highlight each ref and separators
            local pos = refs_start + 2 -- After "("
            for j, ref in ipairs(info.commit.refs) do
              if j > 1 then
                -- Highlight ", " separator
                local sep_pos = line:find(", ", pos, true)
                if sep_pos then
                  hl.set(bufnr, ns, line_idx, sep_pos - 1, sep_pos + 1, "GitladRefSeparator")
                  pos = sep_pos + 2
                end
              end

              -- Handle "HEAD -> " prefix
              if ref.is_head then
                local head_end = pos + 7 -- "HEAD -> " is 8 chars
                hl.set(bufnr, ns, line_idx, pos - 1, head_end, "GitladRefHead")
                pos = head_end + 1
              end

              -- Highlight the ref name
              local ref_len = #ref.name
              local ref_hl = get_ref_highlight_group(ref)
              hl.set(bufnr, ns, line_idx, pos - 1, pos - 1 + ref_len, ref_hl)
              pos = pos + ref_len
            end

            -- Highlight closing paren
            hl.set(bufnr, ns, line_idx, close_paren - 1, close_paren, "GitladRefSeparator")

            -- Subject starts after ") "
            subject_start = close_paren + 2
          end
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
