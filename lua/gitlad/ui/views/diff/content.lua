---@mod gitlad.ui.views.diff.content File content retrieval and side-by-side alignment
---@brief [[
--- Retrieves file content for diff sides (worktree, index, commits) and
--- aligns side-by-side hunks with filler lines for the diff viewer.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")

--- Retrieve file content for a given ref and path.
--- For "WORKTREE"/nil: reads the working tree file directly.
--- For "INDEX"/":0:": uses `git show :0:<path>`.
--- Otherwise: uses `git show <ref>:<path>`.
---@param repo_root string Repository root path
---@param ref string|nil Git ref ("HEAD", "INDEX", "WORKTREE", commit hash, etc.)
---@param path string File path relative to repo root
---@param cb fun(lines: string[]|nil, err: string|nil) Callback with file lines or error
function M.get_file_content(repo_root, ref, path, cb)
  if ref == nil or ref == "WORKTREE" then
    -- Read from working tree
    vim.schedule(function()
      local full_path = repo_root .. "/" .. path
      local ok, lines = pcall(vim.fn.readfile, full_path)
      if ok then
        cb(lines, nil)
      else
        cb(nil, "File not found: " .. path)
      end
    end)
  elseif ref == "INDEX" or ref == ":0:" then
    -- Read from git index
    cli.run_async({ "show", ":0:" .. path }, { cwd = repo_root, internal = true }, function(result)
      if result.code == 0 then
        cb(result.stdout, nil)
      else
        local err = table.concat(result.stderr, "\n")
        cb(nil, "Failed to read index version: " .. err)
      end
    end)
  else
    -- Read from a specific ref (commit, tag, branch)
    cli.run_async(
      { "show", ref .. ":" .. path },
      { cwd = repo_root, internal = true },
      function(result)
        if result.code == 0 then
          cb(result.stdout, nil)
        else
          local err = table.concat(result.stderr, "\n")
          cb(nil, "Failed to read " .. ref .. ":" .. path .. ": " .. err)
        end
      end
    )
  end
end

---@class AlignedLineInfo
---@field left_type DiffLineType "context"|"add"|"delete"|"change"|"filler"
---@field right_type DiffLineType
---@field left_lineno number|nil Original file line number
---@field right_lineno number|nil Original file line number
---@field hunk_index number|nil Which hunk this line belongs to (1-based)
---@field is_hunk_boundary boolean True for first line of a hunk

---@class AlignedContent
---@field left_lines string[] Lines for left buffer (with filler lines)
---@field right_lines string[] Lines for right buffer (with filler lines)
---@field line_map AlignedLineInfo[] Maps buffer line index (1-based) to metadata

--- Transform a DiffFilePair's side-by-side hunks into aligned buffer content.
--- Iterates all hunks' DiffLinePair entries and produces left/right buffer lines
--- plus a line_map with metadata for each aligned line.
---@param file_pair DiffFilePair File pair with side-by-side hunks
---@return AlignedContent Aligned content for both buffers
function M.align_sides(file_pair)
  local left_lines = {}
  local right_lines = {}
  local line_map = {}

  for hunk_idx, hunk in ipairs(file_pair.hunks) do
    for pair_idx, pair in ipairs(hunk.pairs) do
      table.insert(left_lines, pair.left_line or "")
      table.insert(right_lines, pair.right_line or "")
      table.insert(line_map, {
        left_type = pair.left_type,
        right_type = pair.right_type,
        left_lineno = pair.left_lineno,
        right_lineno = pair.right_lineno,
        hunk_index = hunk_idx,
        is_hunk_boundary = (pair_idx == 1),
      })
    end
  end

  -- Recompute is_hunk_boundary: mark the first non-context line of each change region.
  -- With full-context diffs (-U999999) there's only one giant hunk, so the original
  -- per-pair is_hunk_boundary (pair_idx == 1) fires only on line 1. This post-processing
  -- pass marks context→change transitions so ]c/[c hunk navigation works correctly.
  local prev_context = true
  local prev_hunk_index = nil
  for _, info in ipairs(line_map) do
    local is_context = (info.left_type == "context") and (info.right_type == "context")
    local new_hunk = (info.hunk_index ~= prev_hunk_index)
    info.is_hunk_boundary = (not is_context) and (prev_context or new_hunk)
    prev_context = is_context
    prev_hunk_index = info.hunk_index
  end

  return {
    left_lines = left_lines,
    right_lines = right_lines,
    line_map = line_map,
  }
end

--- Return the git ref string needed to retrieve file content for a DiffSource side.
---@param source DiffSource The diff source specification
---@param side "left"|"mid"|"right" Which side of the diff
---@return string ref The git ref to use with get_file_content
function M.ref_for_source(source, side)
  local source_type = source.type

  if source_type == "staged" then
    if side == "left" then
      return "HEAD"
    else
      return "INDEX"
    end
  elseif source_type == "unstaged" then
    if side == "left" then
      return "INDEX"
    else
      return "WORKTREE"
    end
  elseif source_type == "worktree" then
    if side == "left" then
      return "HEAD"
    else
      return "WORKTREE"
    end
  elseif source_type == "commit" or source_type == "stash" then
    local ref = source.ref or "HEAD"
    if side == "left" then
      return ref .. "^"
    else
      return ref
    end
  elseif source_type == "range" then
    local range = source.range or ""
    -- Handle both "A..B" and "A...B" range formats
    local left_ref, right_ref = range:match("^(.+)%.%.%.(.+)$")
    if not left_ref then
      left_ref, right_ref = range:match("^(.+)%.%.(.+)$")
    end
    if left_ref and right_ref then
      if side == "left" then
        return left_ref
      else
        return right_ref
      end
    end
    -- Fallback: treat range as a ref
    if side == "left" then
      return range .. "^"
    else
      return range
    end
  elseif source_type == "pr" then
    local pr_info = source.pr_info
    if pr_info then
      if side == "left" then
        return pr_info.base_oid or pr_info.base_ref or "HEAD"
      else
        return pr_info.head_oid or pr_info.head_ref or "HEAD"
      end
    end
    -- Fallback
    if side == "left" then
      return "HEAD^"
    else
      return "HEAD"
    end
  elseif source_type == "three_way" then
    if side == "left" then
      return "HEAD"
    elseif side == "mid" then
      return "INDEX"
    else
      return "WORKTREE"
    end
  elseif source_type == "merge" then
    if side == "left" then
      return ":2:" -- OURS
    elseif side == "mid" then
      return "WORKTREE" -- Worktree file with conflict markers
    else
      return ":3:" -- THEIRS
    end
  end

  -- Unknown source type fallback
  if side == "left" then
    return "HEAD^"
  else
    return "HEAD"
  end
end

return M
