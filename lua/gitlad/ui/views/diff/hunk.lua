---@mod gitlad.ui.views.diff.hunk Unified diff to side-by-side transform
---@brief [[
--- Parses unified diff output and transforms hunks into side-by-side line pairs.
--- Pure functions with no side effects — fully testable without vim.
---@brief ]]

local M = {}

--- Parse a hunk header line into its components
---@param line string The @@ header line
---@return DiffHunkHeader|nil header Parsed header, or nil if not a valid header
function M.parse_hunk_header(line)
  local old_start, old_count, new_start, new_count =
    line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return nil
  end
  return {
    old_start = tonumber(old_start) or 1,
    old_count = tonumber(old_count) or 1,
    new_start = tonumber(new_start) or 1,
    new_count = tonumber(new_count) or 1,
    text = line,
  }
end

--- Transform a run of -/+ lines into side-by-side DiffLinePairs
--- Equal counts: paired as "change". Extra -: "delete" with right filler. Extra +: "add" with left filler.
---@param del_lines string[] Deletion lines (content without the - prefix)
---@param del_linenos number[] Line numbers for deletions in old file
---@param add_lines string[] Addition lines (content without the + prefix)
---@param add_linenos number[] Line numbers for additions in new file
---@return DiffLinePair[]
function M.pair_change_run(del_lines, del_linenos, add_lines, add_linenos)
  local pairs_out = {}
  local del_count = #del_lines
  local add_count = #add_lines
  local paired = math.min(del_count, add_count)

  -- Paired lines: "change" type on both sides
  for i = 1, paired do
    table.insert(pairs_out, {
      left_line = del_lines[i],
      right_line = add_lines[i],
      left_type = "change",
      right_type = "change",
      left_lineno = del_linenos[i],
      right_lineno = add_linenos[i],
    })
  end

  -- Extra deletions: left shows delete, right is filler
  for i = paired + 1, del_count do
    table.insert(pairs_out, {
      left_line = del_lines[i],
      right_line = nil,
      left_type = "delete",
      right_type = "filler",
      left_lineno = del_linenos[i],
      right_lineno = nil,
    })
  end

  -- Extra additions: left is filler, right shows add
  for i = paired + 1, add_count do
    table.insert(pairs_out, {
      left_line = nil,
      right_line = add_lines[i],
      left_type = "filler",
      right_type = "add",
      left_lineno = nil,
      right_lineno = add_linenos[i],
    })
  end

  return pairs_out
end

--- Transform a single hunk's lines into side-by-side DiffLinePairs
---@param hunk_lines string[] Lines within the hunk (with +/-/space prefix)
---@param old_start number Starting line number in old file
---@param new_start number Starting line number in new file
---@return DiffLinePair[]
function M.transform_hunk_to_side_by_side(hunk_lines, old_start, new_start)
  local pairs_out = {}
  local old_lineno = old_start
  local new_lineno = new_start

  -- Accumulate runs of -/+ lines
  local del_lines = {}
  local del_linenos = {}
  local add_lines = {}
  local add_linenos = {}

  local function flush_run()
    if #del_lines > 0 or #add_lines > 0 then
      local run_pairs = M.pair_change_run(del_lines, del_linenos, add_lines, add_linenos)
      for _, p in ipairs(run_pairs) do
        table.insert(pairs_out, p)
      end
      del_lines = {}
      del_linenos = {}
      add_lines = {}
      add_linenos = {}
    end
  end

  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    local content = line:sub(2)

    if prefix == "-" then
      table.insert(del_lines, content)
      table.insert(del_linenos, old_lineno)
      old_lineno = old_lineno + 1
    elseif prefix == "+" then
      table.insert(add_lines, content)
      table.insert(add_linenos, new_lineno)
      new_lineno = new_lineno + 1
    elseif prefix == "\\" then
      -- "\ No newline at end of file" — attach to the preceding run
      -- Don't flush, don't increment line numbers
    else
      -- Context line (space prefix or no prefix)
      flush_run()
      table.insert(pairs_out, {
        left_line = content,
        right_line = content,
        left_type = "context",
        right_type = "context",
        left_lineno = old_lineno,
        right_lineno = new_lineno,
      })
      old_lineno = old_lineno + 1
      new_lineno = new_lineno + 1
    end
  end

  flush_run()
  return pairs_out
end

--- Parse file status from diff header or numstat
---@param old_path string Old path (can be /dev/null for added files)
---@param new_path string New path (can be /dev/null for deleted files)
---@return string status Single character status
function M.detect_file_status(old_path, new_path)
  if old_path == "/dev/null" or old_path == "" then
    return "A"
  elseif new_path == "/dev/null" or new_path == "" then
    return "D"
  elseif old_path ~= new_path then
    return "R"
  else
    return "M"
  end
end

--- Parse a complete unified diff output into DiffFilePairs
--- Handles multiple files in a single diff output.
---@param lines string[] Lines of unified diff output
---@return DiffFilePair[]
function M.parse_unified_diff(lines)
  local file_pairs = {}
  local current_file = nil
  local current_hunks_raw = {} -- Accumulate raw hunk data for current file
  local current_hunk_lines = nil
  local current_header = nil

  local function finish_hunk()
    if current_hunk_lines and current_header then
      table.insert(current_hunks_raw, {
        header = current_header,
        lines = current_hunk_lines,
      })
    end
    current_hunk_lines = nil
    current_header = nil
  end

  local function finish_file()
    finish_hunk()
    if current_file then
      -- Transform raw hunks to side-by-side
      local additions = 0
      local deletions = 0
      local sbs_hunks = {}

      for _, raw in ipairs(current_hunks_raw) do
        local sbs_pairs =
          M.transform_hunk_to_side_by_side(raw.lines, raw.header.old_start, raw.header.new_start)
        -- Count additions/deletions
        for _, p in ipairs(sbs_pairs) do
          if p.right_type == "add" or p.right_type == "change" then
            additions = additions + 1
          end
          if p.left_type == "delete" or p.left_type == "change" then
            deletions = deletions + 1
          end
        end
        table.insert(sbs_hunks, {
          header = raw.header,
          pairs = sbs_pairs,
        })
      end

      current_file.hunks = sbs_hunks
      current_file.additions = additions
      current_file.deletions = deletions
      table.insert(file_pairs, current_file)
    end
    current_file = nil
    current_hunks_raw = {}
  end

  for _, line in ipairs(lines) do
    if current_hunk_lines then
      -- Inside a hunk: check for boundaries that end the hunk, otherwise accumulate.
      -- This MUST be checked first — hunk lines like "--- comment" (a deleted Lua
      -- comment) or "+++ value" (an added line) would otherwise match the file header
      -- patterns below and get silently dropped.
      if line:match("^diff %-%-git ") then
        finish_file()

        local old_path, new_path = line:match("^diff %-%-git a/(.+) b/(.+)$")
        if old_path and new_path then
          current_file = {
            old_path = old_path,
            new_path = new_path,
            status = M.detect_file_status(old_path, new_path),
            hunks = {},
            additions = 0,
            deletions = 0,
            is_binary = false,
          }
        end
      elseif line:match("^@@") then
        finish_hunk()
        local header = M.parse_hunk_header(line)
        if header then
          current_header = header
          current_hunk_lines = {}
        end
      else
        table.insert(current_hunk_lines, line)
      end
    elseif line:match("^diff %-%-git ") then
      -- Detect file boundary: "diff --git a/... b/..."
      finish_file()

      local old_path, new_path = line:match("^diff %-%-git a/(.+) b/(.+)$")
      if old_path and new_path then
        current_file = {
          old_path = old_path,
          new_path = new_path,
          status = M.detect_file_status(old_path, new_path),
          hunks = {},
          additions = 0,
          deletions = 0,
          is_binary = false,
        }
      end
    elseif line:match("^Binary files") then
      if current_file then
        current_file.is_binary = true
      end
    elseif line:match("^--- ") then
      -- Old file path: "--- a/path" or "--- /dev/null"
      if current_file and line:match("^--- /dev/null") then
        current_file.status = "A"
      end
    elseif line:match("^%+%+%+ ") then
      -- New file path: "+++ b/path" or "+++ /dev/null"
      if current_file and line:match("^%+%+%+ /dev/null") then
        current_file.status = "D"
      end
    elseif line:match("^@@") then
      -- Hunk header
      finish_hunk()
      local header = M.parse_hunk_header(line)
      if header then
        current_header = header
        current_hunk_lines = {}
      end
    elseif line:match("^rename from ") then
      -- Rename detection
      if current_file then
        current_file.status = "R"
      end
    elseif line:match("^copy from ") then
      if current_file then
        current_file.status = "C"
      end
    elseif line:match("^similarity index ") or line:match("^dissimilarity index ") then
      -- Rename/copy metadata — skip
    elseif line:match("^rename to ") or line:match("^copy to ") then
      -- Rename/copy metadata — skip
    end
  end

  finish_file()
  return file_pairs
end

return M
