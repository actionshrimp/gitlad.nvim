---@mod gitlad.ui.views.diff.three_way Three-way diff alignment algorithm
---@brief [[
--- Merges two 2-way diffs (staged: HEAD→INDEX, unstaged: INDEX→WORKTREE) into a
--- single 3-column display. INDEX is the shared anchor between the two diffs.
---
--- Also handles merge conflicts (OURS→BASE←THEIRS) with BASE as the anchor.
---
--- Pure Lua module — no vim dependency. Fully unit-testable.
---@brief ]]

local M = {}

--- Merge two file lists (staged and unstaged DiffFilePairs) by path into ThreeWayFileDiff[].
--- Files may appear in one or both lists.
---@param staged_pairs DiffFilePair[] Files from staged diff (HEAD → INDEX)
---@param unstaged_pairs DiffFilePair[] Files from unstaged diff (INDEX → WORKTREE)
---@return ThreeWayFileDiff[]
function M.merge_file_lists(staged_pairs, unstaged_pairs)
  -- Index files by path
  local staged_by_path = {}
  for _, pair in ipairs(staged_pairs) do
    local path = pair.new_path ~= "" and pair.new_path or pair.old_path
    staged_by_path[path] = pair
  end

  local unstaged_by_path = {}
  for _, pair in ipairs(unstaged_pairs) do
    local path = pair.new_path ~= "" and pair.new_path or pair.old_path
    unstaged_by_path[path] = pair
  end

  -- Collect all unique paths in order (staged first, then unstaged-only)
  local seen = {}
  local paths = {}
  for _, pair in ipairs(staged_pairs) do
    local path = pair.new_path ~= "" and pair.new_path or pair.old_path
    if not seen[path] then
      seen[path] = true
      table.insert(paths, path)
    end
  end
  for _, pair in ipairs(unstaged_pairs) do
    local path = pair.new_path ~= "" and pair.new_path or pair.old_path
    if not seen[path] then
      seen[path] = true
      table.insert(paths, path)
    end
  end

  -- Build ThreeWayFileDiff for each path
  local result = {}
  for _, path in ipairs(paths) do
    local staged = staged_by_path[path]
    local unstaged = unstaged_by_path[path]

    local additions = 0
    local deletions = 0
    if staged then
      additions = additions + staged.additions
      deletions = deletions + staged.deletions
    end
    if unstaged then
      additions = additions + unstaged.additions
      deletions = deletions + unstaged.deletions
    end

    table.insert(result, {
      path = path,
      staged_hunks = staged and staged.hunks or {},
      unstaged_hunks = unstaged and unstaged.hunks or {},
      status_staged = staged and staged.status or nil,
      status_unstaged = unstaged and unstaged.status or nil,
      additions = additions,
      deletions = deletions,
    })
  end

  return result
end

--- Get the anchor line range covered by a hunk.
--- Returns the start and end anchor line numbers.
---@param hunk DiffSideBySideHunk
---@param anchor_side "left"|"right"
---@return number start_line
---@return number end_line (inclusive, last anchor line in the hunk)
local function hunk_anchor_range(hunk, anchor_side)
  local start_line, count
  if anchor_side == "left" then
    start_line = hunk.header.old_start
    count = hunk.header.old_count
  else
    start_line = hunk.header.new_start
    count = hunk.header.new_count
  end
  -- End line is start + count - 1, but handle count=0 (pure addition)
  local end_line = start_line + math.max(count, 1) - 1
  return start_line, end_line
end

--- Collect all anchor line events from both staged and unstaged hunks.
--- An event represents a hunk that starts at a given INDEX line.
---@param staged_hunks DiffSideBySideHunk[]
---@param unstaged_hunks DiffSideBySideHunk[]
---@return table[] events Sorted list of { anchor_start, anchor_end, source: "staged"|"unstaged", hunk_idx, hunk }
local function collect_hunk_events(staged_hunks, unstaged_hunks)
  local events = {}

  -- For staged diff: HEAD→INDEX, anchor (INDEX) is on the right side (new)
  for i, hunk in ipairs(staged_hunks) do
    local start_line, end_line = hunk_anchor_range(hunk, "right")
    table.insert(events, {
      anchor_start = start_line,
      anchor_end = end_line,
      source = "staged",
      hunk_idx = i,
      hunk = hunk,
    })
  end

  -- For unstaged diff: INDEX→WORKTREE, anchor (INDEX) is on the left side (old)
  for i, hunk in ipairs(unstaged_hunks) do
    local start_line, end_line = hunk_anchor_range(hunk, "left")
    table.insert(events, {
      anchor_start = start_line,
      anchor_end = end_line,
      source = "unstaged",
      hunk_idx = i,
      hunk = hunk,
    })
  end

  -- Sort by anchor_start, breaking ties with "staged" first
  table.sort(events, function(a, b)
    if a.anchor_start ~= b.anchor_start then
      return a.anchor_start < b.anchor_start
    end
    -- staged before unstaged for same start
    if a.source ~= b.source then
      return a.source == "staged"
    end
    return a.hunk_idx < b.hunk_idx
  end)

  return events
end

--- Process a staged-only hunk: HEAD differs from INDEX, WORKTREE = INDEX.
--- Walks the hunk pairs (which are HEAD↔INDEX side-by-side) and produces 3-column output.
---@param hunk DiffSideBySideHunk
---@param hunk_region_idx number
---@param left_lines string[]
---@param mid_lines string[]
---@param right_lines string[]
---@param line_map ThreeWayLineInfo[]
local function emit_staged_hunk(hunk, hunk_region_idx, left_lines, mid_lines, right_lines, line_map)
  for pair_idx, pair in ipairs(hunk.pairs) do
    -- left = HEAD side (pair.left), mid = INDEX side (pair.right), right = same as mid
    local left_content = pair.left_line or ""
    local mid_content = pair.right_line or ""

    -- For context lines within the hunk, all 3 are the same
    if pair.left_type == "context" and pair.right_type == "context" then
      table.insert(left_lines, left_content)
      table.insert(mid_lines, mid_content)
      table.insert(right_lines, mid_content)
      table.insert(line_map, {
        left_type = "context",
        mid_type = "context",
        right_type = "context",
        left_lineno = pair.left_lineno,
        mid_lineno = pair.right_lineno,
        right_lineno = pair.right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = (pair_idx == 1),
      })
    else
      -- Changed/added/deleted in staged: right mirrors mid
      local right_content
      local right_type
      local right_lineno

      if pair.right_type == "filler" then
        -- INDEX has filler = line deleted from HEAD, not in INDEX or WORKTREE
        right_content = ""
        right_type = "filler"
        right_lineno = nil
      else
        -- INDEX has content, WORKTREE matches INDEX
        right_content = mid_content
        right_type = pair.right_type -- same visual as mid
        right_lineno = pair.right_lineno
      end

      table.insert(left_lines, left_content)
      table.insert(mid_lines, mid_content)
      table.insert(right_lines, right_content)
      table.insert(line_map, {
        left_type = pair.left_type,
        mid_type = pair.right_type, -- mid shows INDEX side of staged diff
        right_type = right_type,
        left_lineno = pair.left_lineno,
        mid_lineno = pair.right_lineno,
        right_lineno = right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = (pair_idx == 1),
      })
    end
  end
end

--- Process an unstaged-only hunk: HEAD = INDEX, INDEX differs from WORKTREE.
--- Walks the hunk pairs (which are INDEX↔WORKTREE side-by-side) and produces 3-column output.
---@param hunk DiffSideBySideHunk
---@param hunk_region_idx number
---@param left_lines string[]
---@param mid_lines string[]
---@param right_lines string[]
---@param line_map ThreeWayLineInfo[]
local function emit_unstaged_hunk(
  hunk,
  hunk_region_idx,
  left_lines,
  mid_lines,
  right_lines,
  line_map
)
  for pair_idx, pair in ipairs(hunk.pairs) do
    -- left = HEAD (same as INDEX = pair.left), mid = INDEX (pair.left), right = WORKTREE (pair.right)
    local mid_content = pair.left_line or ""
    local right_content = pair.right_line or ""

    if pair.left_type == "context" and pair.right_type == "context" then
      table.insert(left_lines, mid_content)
      table.insert(mid_lines, mid_content)
      table.insert(right_lines, right_content)
      table.insert(line_map, {
        left_type = "context",
        mid_type = "context",
        right_type = "context",
        left_lineno = pair.left_lineno,
        mid_lineno = pair.left_lineno,
        right_lineno = pair.right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = (pair_idx == 1),
      })
    else
      -- Changed in unstaged: left mirrors mid (HEAD = INDEX)
      local left_content
      local left_type
      local left_lineno

      if pair.left_type == "filler" then
        -- INDEX has filler = line added in WORKTREE, not in INDEX or HEAD
        left_content = ""
        left_type = "filler"
        left_lineno = nil
      else
        left_content = mid_content
        left_type = pair.left_type
        left_lineno = pair.left_lineno
      end

      table.insert(left_lines, left_content)
      table.insert(mid_lines, mid_content)
      table.insert(right_lines, right_content)
      table.insert(line_map, {
        left_type = left_type,
        mid_type = pair.left_type,
        right_type = pair.right_type,
        left_lineno = left_lineno,
        mid_lineno = pair.left_lineno,
        right_lineno = pair.right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = (pair_idx == 1),
      })
    end
  end
end

--- Process overlapping staged + unstaged hunks at the same anchor region.
--- Both diffs modify content at the same INDEX lines.
--- We walk pairs from both hunks anchored on INDEX line numbers.
---@param staged_hunk DiffSideBySideHunk
---@param unstaged_hunk DiffSideBySideHunk
---@param hunk_region_idx number
---@param left_lines string[]
---@param mid_lines string[]
---@param right_lines string[]
---@param line_map ThreeWayLineInfo[]
local function emit_overlapping_hunks(
  staged_hunk,
  unstaged_hunk,
  hunk_region_idx,
  left_lines,
  mid_lines,
  right_lines,
  line_map
)
  -- Build maps from INDEX line number to pair data for both hunks
  -- Staged: left=HEAD, right=INDEX
  -- Unstaged: left=INDEX, right=WORKTREE

  -- Collect all INDEX line numbers mentioned in either hunk
  -- For staged, INDEX lines are on the right (new) side
  -- For unstaged, INDEX lines are on the left (old) side

  -- We'll walk through staged pairs and unstaged pairs together,
  -- using the INDEX line as the join key.

  -- Build arrays of data keyed by sequential position
  local staged_pairs = staged_hunk.pairs
  local unstaged_pairs = unstaged_hunk.pairs

  -- Walk through INDEX lines that each hunk covers
  -- Staged right_lineno = INDEX line, unstaged left_lineno = INDEX line
  local si, ui = 1, 1
  local is_first = true

  while si <= #staged_pairs or ui <= #unstaged_pairs do
    local sp = staged_pairs[si]
    local up = unstaged_pairs[ui]

    -- Get INDEX line numbers from each current pair
    local s_idx_lineno = sp and sp.right_lineno -- staged: INDEX is right side
    local u_idx_lineno = up and up.left_lineno -- unstaged: INDEX is left side

    -- Handle cases where one side has filler (no INDEX line)
    if sp and sp.right_type == "filler" then
      -- Staged has a line deleted from HEAD, not in INDEX
      -- HEAD has content, INDEX and WORKTREE don't have this line
      table.insert(left_lines, sp.left_line or "")
      table.insert(mid_lines, "")
      table.insert(right_lines, "")
      table.insert(line_map, {
        left_type = sp.left_type,
        mid_type = "filler",
        right_type = "filler",
        left_lineno = sp.left_lineno,
        mid_lineno = nil,
        right_lineno = nil,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = is_first,
      })
      is_first = false
      si = si + 1
    elseif up and up.right_type ~= "filler" and up.left_type == "filler" then
      -- Unstaged has a line added in WORKTREE, not in INDEX
      -- HEAD and INDEX don't have this, only WORKTREE
      table.insert(left_lines, "")
      table.insert(mid_lines, "")
      table.insert(right_lines, up.right_line or "")
      table.insert(line_map, {
        left_type = "filler",
        mid_type = "filler",
        right_type = up.right_type,
        left_lineno = nil,
        mid_lineno = nil,
        right_lineno = up.right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = is_first,
      })
      is_first = false
      ui = ui + 1
    elseif s_idx_lineno and u_idx_lineno then
      -- Both have INDEX line numbers
      if s_idx_lineno == u_idx_lineno then
        -- Same INDEX line: all three panes may differ
        table.insert(left_lines, sp.left_line or "")
        table.insert(mid_lines, sp.right_line or "")
        table.insert(right_lines, up.right_line or "")
        table.insert(line_map, {
          left_type = sp.left_type,
          mid_type = sp.right_type,
          right_type = up.right_type,
          left_lineno = sp.left_lineno,
          mid_lineno = sp.right_lineno,
          right_lineno = up.right_lineno,
          hunk_index = hunk_region_idx,
          is_hunk_boundary = is_first,
        })
        is_first = false
        si = si + 1
        ui = ui + 1
      elseif s_idx_lineno < u_idx_lineno then
        -- Staged has an earlier INDEX line: unstaged hasn't reached it yet
        -- WORKTREE matches INDEX at this line
        table.insert(left_lines, sp.left_line or "")
        table.insert(mid_lines, sp.right_line or "")
        table.insert(right_lines, sp.right_line or "")
        table.insert(line_map, {
          left_type = sp.left_type,
          mid_type = sp.right_type,
          right_type = sp.right_type,
          left_lineno = sp.left_lineno,
          mid_lineno = sp.right_lineno,
          right_lineno = sp.right_lineno,
          hunk_index = hunk_region_idx,
          is_hunk_boundary = is_first,
        })
        is_first = false
        si = si + 1
      else
        -- Unstaged has an earlier INDEX line: staged hasn't reached it yet
        -- HEAD matches INDEX at this line
        table.insert(left_lines, up.left_line or "")
        table.insert(mid_lines, up.left_line or "")
        table.insert(right_lines, up.right_line or "")
        table.insert(line_map, {
          left_type = up.left_type,
          mid_type = up.left_type,
          right_type = up.right_type,
          left_lineno = up.left_lineno,
          mid_lineno = up.left_lineno,
          right_lineno = up.right_lineno,
          hunk_index = hunk_region_idx,
          is_hunk_boundary = is_first,
        })
        is_first = false
        ui = ui + 1
      end
    elseif s_idx_lineno then
      -- Only staged has data left: WORKTREE = INDEX
      table.insert(left_lines, sp.left_line or "")
      table.insert(mid_lines, sp.right_line or "")
      table.insert(right_lines, sp.right_line or "")
      table.insert(line_map, {
        left_type = sp.left_type,
        mid_type = sp.right_type,
        right_type = sp.right_type,
        left_lineno = sp.left_lineno,
        mid_lineno = sp.right_lineno,
        right_lineno = sp.right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = is_first,
      })
      is_first = false
      si = si + 1
    elseif u_idx_lineno then
      -- Only unstaged has data left: HEAD = INDEX
      table.insert(left_lines, up.left_line or "")
      table.insert(mid_lines, up.left_line or "")
      table.insert(right_lines, up.right_line or "")
      table.insert(line_map, {
        left_type = up.left_type,
        mid_type = up.left_type,
        right_type = up.right_type,
        left_lineno = up.left_lineno,
        mid_lineno = up.left_lineno,
        right_lineno = up.right_lineno,
        hunk_index = hunk_region_idx,
        is_hunk_boundary = is_first,
      })
      is_first = false
      ui = ui + 1
    else
      -- Both have filler lines with no anchor - shouldn't happen normally
      -- but handle gracefully
      if sp then
        si = si + 1
      end
      if up then
        ui = ui + 1
      end
    end
  end
end

--- Align a ThreeWayFileDiff into 3-column buffer content.
--- Walks through both sets of hunks, anchored on INDEX line numbers, and
--- produces aligned left/mid/right lines with metadata for highlighting.
---@param file_diff ThreeWayFileDiff The three-way file diff
---@return ThreeWayAlignedContent
function M.align_three_way(file_diff)
  local left_lines = {}
  local mid_lines = {}
  local right_lines = {}
  local line_map = {}

  local staged_hunks = file_diff.staged_hunks
  local unstaged_hunks = file_diff.unstaged_hunks

  -- No hunks at all: empty diff
  if #staged_hunks == 0 and #unstaged_hunks == 0 then
    return {
      left_lines = left_lines,
      mid_lines = mid_lines,
      right_lines = right_lines,
      line_map = line_map,
    }
  end

  -- Collect and sort all hunk events by their anchor (INDEX) line
  local events = collect_hunk_events(staged_hunks, unstaged_hunks)

  -- Group overlapping events (same or overlapping anchor ranges)
  local groups = {}
  local current_group = nil

  for _, event in ipairs(events) do
    if current_group and event.anchor_start <= current_group.anchor_end then
      -- Overlapping with current group
      table.insert(current_group.events, event)
      if event.anchor_end > current_group.anchor_end then
        current_group.anchor_end = event.anchor_end
      end
    else
      -- New group
      current_group = {
        anchor_start = event.anchor_start,
        anchor_end = event.anchor_end,
        events = { event },
      }
      table.insert(groups, current_group)
    end
  end

  -- Process each group, emitting context lines between groups
  local hunk_region_idx = 0

  for _, group in ipairs(groups) do
    hunk_region_idx = hunk_region_idx + 1

    -- Classify the group
    local has_staged = false
    local has_unstaged = false
    local staged_event, unstaged_event

    for _, event in ipairs(group.events) do
      if event.source == "staged" then
        has_staged = true
        staged_event = event
      elseif event.source == "unstaged" then
        has_unstaged = true
        unstaged_event = event
      end
    end

    if has_staged and has_unstaged then
      -- Overlapping: both staged and unstaged hunks affect the same region
      emit_overlapping_hunks(
        staged_event.hunk,
        unstaged_event.hunk,
        hunk_region_idx,
        left_lines,
        mid_lines,
        right_lines,
        line_map
      )
    elseif has_staged then
      -- Staged only: HEAD differs from INDEX, WORKTREE = INDEX
      emit_staged_hunk(
        staged_event.hunk,
        hunk_region_idx,
        left_lines,
        mid_lines,
        right_lines,
        line_map
      )
    elseif has_unstaged then
      -- Unstaged only: HEAD = INDEX, INDEX differs from WORKTREE
      emit_unstaged_hunk(
        unstaged_event.hunk,
        hunk_region_idx,
        left_lines,
        mid_lines,
        right_lines,
        line_map
      )
    end
  end

  return {
    left_lines = left_lines,
    mid_lines = mid_lines,
    right_lines = right_lines,
    line_map = line_map,
  }
end

return M
