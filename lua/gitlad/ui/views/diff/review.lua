---@mod gitlad.ui.views.diff.review Review comment overlay for the native diff viewer
---@brief [[
--- Manages display of PR review threads in the side-by-side diff buffers.
--- Renders thread indicators as signs and expanded/collapsed thread content
--- as virtual lines below commented code lines.
---@brief ]]

local M = {}

local types = require("gitlad.forge.types")

-- Namespace for review overlay extmarks (separate from diff highlights)
local ns = vim.api.nvim_create_namespace("gitlad_diff_review")

-- =============================================================================
-- Review State
-- =============================================================================

---@class PendingComment
---@field path string File path
---@field line number Line number
---@field side string "LEFT"|"RIGHT"
---@field body string Comment body

---@class ReviewState
---@field threads ForgeReviewThread[] All review threads for this PR
---@field thread_map table<string, ForgeReviewThread[]> Threads grouped by file path
---@field collapsed table<string, boolean> Thread ID -> collapsed state (true = collapsed)
---@field pr_node_id string|nil PR GraphQL node ID (for mutations)
---@field file_thread_positions table<number, ForgeReviewThread> Buffer line -> thread mapping
---@field pending_mode boolean Whether pending review mode is active
---@field pending_comments PendingComment[] Pending comments not yet submitted

--- Create a new ReviewState
---@return ReviewState
function M.new_state()
  return {
    threads = {},
    thread_map = {},
    collapsed = {},
    pr_node_id = nil,
    file_thread_positions = {},
    pending_mode = false,
    pending_comments = {},
  }
end

-- =============================================================================
-- Thread-to-line mapping (pure, testable)
-- =============================================================================

--- Group review threads by file path.
---@param threads ForgeReviewThread[] All review threads
---@return table<string, ForgeReviewThread[]> Threads indexed by file path
function M.group_threads_by_path(threads)
  local map = {}
  for _, thread in ipairs(threads) do
    local path = thread.path
    if not map[path] then
      map[path] = {}
    end
    table.insert(map[path], thread)
  end
  return map
end

--- Map review threads for a file to buffer line positions using the line_map.
--- Returns a table mapping buffer line numbers (1-indexed) to the thread(s) at that line.
---@param file_threads ForgeReviewThread[] Threads for a single file
---@param line_map AlignedLineInfo[] Buffer line metadata from DiffBufferPair
---@return table<number, ForgeReviewThread[]> buffer_line -> threads at that line
function M.map_threads_to_lines(file_threads, line_map)
  local result = {}

  for _, thread in ipairs(file_threads) do
    local target_line = thread.line
    if target_line == nil then
      -- Outdated thread with no current line position — skip mapping
      goto continue
    end

    local side = thread.diff_side or "RIGHT"

    -- Find the buffer line that matches this thread's position
    for buf_line, info in ipairs(line_map) do
      local match = false
      if side == "RIGHT" and info.right_lineno == target_line then
        match = true
      elseif side == "LEFT" and info.left_lineno == target_line then
        match = true
      end

      if match then
        if not result[buf_line] then
          result[buf_line] = {}
        end
        table.insert(result[buf_line], thread)
        break
      end
    end

    ::continue::
  end

  return result
end

-- =============================================================================
-- Rendering helpers
-- =============================================================================

--- Format a single thread as collapsed summary text.
---@param thread ForgeReviewThread
---@return string summary One-line summary
function M.format_collapsed(thread)
  if #thread.comments == 0 then
    return ""
  end

  local first = thread.comments[1]
  local body_preview = first.body:gsub("\n", " ")
  if #body_preview > 60 then
    body_preview = body_preview:sub(1, 57) .. "..."
  end

  local reply_count = #thread.comments - 1
  local reply_text = ""
  if reply_count > 0 then
    reply_text = string.format(" [%d %s]", reply_count, reply_count == 1 and "reply" or "replies")
  end

  local status = ""
  if thread.is_resolved then
    status = " [resolved]"
  elseif thread.is_outdated then
    status = " [outdated]"
  end

  return string.format(" @%s: %s%s%s ", first.author.login, body_preview, reply_text, status)
end

--- Format a thread as expanded virtual lines.
--- Returns a list of {text, hl_group} chunks for each virtual line.
---@param thread ForgeReviewThread
---@return table[] virt_lines List of virt_line specs (each is a list of {text, hl_group} chunks)
function M.format_expanded(thread)
  local virt_lines = {}
  local border_hl = "GitladReviewBorder"
  local body_hl = "GitladReviewBody"

  if thread.is_resolved then
    border_hl = "GitladReviewResolved"
    body_hl = "GitladReviewResolved"
  elseif thread.is_outdated then
    border_hl = "GitladReviewOutdated"
    body_hl = "GitladReviewOutdated"
  end

  for i, comment in ipairs(thread.comments) do
    -- Header line: author + timestamp
    local time_text = types.relative_time(comment.created_at)
    local prefix = i == 1 and "\u{250c}" or "\u{2502}"

    table.insert(virt_lines, {
      { prefix .. " @", border_hl },
      { comment.author.login, "GitladReviewAuthor" },
      { "  " .. time_text, "GitladReviewTimestamp" },
    })

    -- Body lines
    local body_lines = vim.split(comment.body, "\n", { plain = true })
    for _, line in ipairs(body_lines) do
      table.insert(virt_lines, {
        { "\u{2502} ", border_hl },
        { line, body_hl },
      })
    end

    -- Separator between comments (not after last)
    if i < #thread.comments then
      table.insert(virt_lines, {
        { "\u{2502}   ", border_hl },
      })
    end
  end

  -- Bottom border
  local status_text = ""
  if thread.is_resolved then
    status_text = " resolved"
  elseif thread.is_outdated then
    status_text = " outdated"
  end
  table.insert(virt_lines, {
    { "\u{2514}" .. string.rep("\u{2500}", 40) .. status_text, border_hl },
  })

  return virt_lines
end

-- =============================================================================
-- Overlay application
-- =============================================================================

--- Apply review overlays to a buffer pair for the current file.
--- Clears previous overlays and re-renders based on current state.
---@param buffer_pair DiffBufferPair The side-by-side buffer pair
---@param file_threads ForgeReviewThread[] Threads for the current file
---@param line_map AlignedLineInfo[] Line mapping metadata
---@param collapsed table<string, boolean> Thread collapse state
---@param pending_comments? PendingComment[] Pending comments for this file
---@return table<number, ForgeReviewThread> positions Buffer line -> first thread at that line
function M.apply_overlays(buffer_pair, file_threads, line_map, collapsed, pending_comments)
  -- Clear previous review overlays
  vim.api.nvim_buf_clear_namespace(buffer_pair.left_bufnr, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buffer_pair.right_bufnr, ns, 0, -1)

  local has_threads = file_threads and #file_threads > 0
  local has_pending = pending_comments and #pending_comments > 0

  if not has_threads and not has_pending then
    return {}
  end

  local thread_positions = {}
  if has_threads then
    thread_positions = M.map_threads_to_lines(file_threads, line_map)
  end
  local positions = {}

  -- Track virt_line counts per buffer line per side for filler alignment
  -- { [buf_line] = { left = N, right = N } }
  local virt_counts = {}

  -- Get sorted line numbers for deterministic rendering
  local sorted_lines = {}
  for buf_line, _ in pairs(thread_positions) do
    table.insert(sorted_lines, buf_line)
  end
  table.sort(sorted_lines)

  for _, buf_line in ipairs(sorted_lines) do
    local threads = thread_positions[buf_line]
    local line_idx = buf_line - 1 -- 0-indexed

    for _, thread in ipairs(threads) do
      -- Track position for the first thread at each line
      if not positions[buf_line] then
        positions[buf_line] = thread
      end

      -- Determine which buffer to place the overlay on
      local side = thread.diff_side == "LEFT" and "left" or "right"
      local target_bufnr
      if side == "left" then
        target_bufnr = buffer_pair.left_bufnr
      else
        target_bufnr = buffer_pair.right_bufnr
      end

      -- Place sign on the commented line
      local sign_hl = "GitladReviewSign"
      if thread.is_resolved then
        sign_hl = "GitladReviewResolved"
      elseif thread.is_outdated then
        sign_hl = "GitladReviewOutdated"
      end

      -- Add sign indicator via extmark sign_text
      if vim.api.nvim_buf_is_valid(target_bufnr) then
        pcall(vim.api.nvim_buf_set_extmark, target_bufnr, ns, line_idx, 0, {
          sign_text = "\u{25cb}",
          sign_hl_group = sign_hl,
          priority = 100,
        })
      end

      -- Render expanded or collapsed content as virt_lines
      local is_collapsed = collapsed[thread.id]
      if is_collapsed == nil then
        -- Default: show collapsed
        is_collapsed = true
      end

      local virt_lines
      if is_collapsed then
        local summary = M.format_collapsed(thread)
        local summary_hl = "GitladReviewBorder"
        if thread.is_resolved then
          summary_hl = "GitladReviewResolved"
        elseif thread.is_outdated then
          summary_hl = "GitladReviewOutdated"
        end
        virt_lines = {
          { { "\u{2500}\u{2500} " .. summary, summary_hl } },
        }
      else
        virt_lines = M.format_expanded(thread)
      end

      if vim.api.nvim_buf_is_valid(target_bufnr) then
        pcall(vim.api.nvim_buf_set_extmark, target_bufnr, ns, line_idx, 0, {
          virt_lines = virt_lines,
          virt_lines_above = false,
        })
      end

      -- Record virt_line count for filler alignment
      if not virt_counts[buf_line] then
        virt_counts[buf_line] = { left = 0, right = 0 }
      end
      virt_counts[buf_line][side] = virt_counts[buf_line][side] + #virt_lines
    end
  end

  -- Render pending comments
  if has_pending then
    M._apply_pending_overlays(buffer_pair, pending_comments, line_map, virt_counts)
  end

  -- Filler pass: add blank virt_lines on the side with fewer lines to keep panes aligned
  M._apply_filler_lines(buffer_pair, virt_counts)

  return positions
end

--- Apply pending comment overlays for a file.
---@param buffer_pair DiffBufferPair
---@param pending_comments PendingComment[]
---@param line_map AlignedLineInfo[]
---@param virt_counts table<number, {left: number, right: number}> Virt line counts to update
function M._apply_pending_overlays(buffer_pair, pending_comments, line_map, virt_counts)
  for _, pc in ipairs(pending_comments) do
    -- Find the buffer line for this pending comment
    for buf_line, info in ipairs(line_map) do
      local match = false
      if pc.side == "RIGHT" and info.right_lineno == pc.line then
        match = true
      elseif pc.side == "LEFT" and info.left_lineno == pc.line then
        match = true
      end

      if match then
        local side = pc.side == "LEFT" and "left" or "right"
        local target_bufnr = side == "left" and buffer_pair.left_bufnr or buffer_pair.right_bufnr
        local line_idx = buf_line - 1

        -- Pending sign
        if vim.api.nvim_buf_is_valid(target_bufnr) then
          pcall(vim.api.nvim_buf_set_extmark, target_bufnr, ns, line_idx, 0, {
            sign_text = "\u{25cf}",
            sign_hl_group = "GitladReviewPending",
            priority = 110,
          })

          -- Pending comment preview (1 virt_line)
          local body_preview = pc.body:gsub("\n", " ")
          if #body_preview > 60 then
            body_preview = body_preview:sub(1, 57) .. "..."
          end

          pcall(vim.api.nvim_buf_set_extmark, target_bufnr, ns, line_idx, 0, {
            virt_lines = {
              {
                { "\u{2500}\u{2500} [pending] ", "GitladReviewPending" },
                { body_preview, "GitladReviewPending" },
              },
            },
            virt_lines_above = false,
          })

          -- Record for filler alignment
          if not virt_counts[buf_line] then
            virt_counts[buf_line] = { left = 0, right = 0 }
          end
          virt_counts[buf_line][side] = virt_counts[buf_line][side] + 1
        end

        break
      end
    end
  end
end

--- Apply filler virtual lines on the opposite buffer to keep panes visually aligned.
--- For each buffer line, if one side has more virt_lines than the other, adds
--- blank filler lines on the side with fewer to match.
---@param buffer_pair DiffBufferPair
---@param virt_counts table<number, {left: number, right: number}>
function M._apply_filler_lines(buffer_pair, virt_counts)
  for buf_line, counts in pairs(virt_counts) do
    local diff = counts.left - counts.right
    if diff == 0 then
      goto continue
    end

    local line_idx = buf_line - 1
    local target_bufnr, filler_count
    if diff > 0 then
      -- Left has more lines, add filler to right
      target_bufnr = buffer_pair.right_bufnr
      filler_count = diff
    else
      -- Right has more lines, add filler to left
      target_bufnr = buffer_pair.left_bufnr
      filler_count = -diff
    end

    if vim.api.nvim_buf_is_valid(target_bufnr) then
      local filler_lines = {}
      for _ = 1, filler_count do
        table.insert(filler_lines, { { " ", "GitladReviewFiller" } })
      end
      pcall(vim.api.nvim_buf_set_extmark, target_bufnr, ns, line_idx, 0, {
        virt_lines = filler_lines,
        virt_lines_above = false,
      })
    end

    ::continue::
  end
end

--- Clear all review overlays from a buffer pair.
---@param buffer_pair DiffBufferPair
function M.clear_overlays(buffer_pair)
  if buffer_pair.left_bufnr and vim.api.nvim_buf_is_valid(buffer_pair.left_bufnr) then
    vim.api.nvim_buf_clear_namespace(buffer_pair.left_bufnr, ns, 0, -1)
  end
  if buffer_pair.right_bufnr and vim.api.nvim_buf_is_valid(buffer_pair.right_bufnr) then
    vim.api.nvim_buf_clear_namespace(buffer_pair.right_bufnr, ns, 0, -1)
  end
end

-- =============================================================================
-- Navigation
-- =============================================================================

--- Find the next thread position after the current cursor line.
---@param positions table<number, ForgeReviewThread> Buffer line -> thread
---@param current_line number Current cursor line (1-indexed)
---@return number|nil next_line Line of next thread, or nil
function M.next_thread_line(positions, current_line)
  local best = nil
  for line, _ in pairs(positions) do
    if line > current_line then
      if best == nil or line < best then
        best = line
      end
    end
  end
  return best
end

--- Find the previous thread position before the current cursor line.
---@param positions table<number, ForgeReviewThread> Buffer line -> thread
---@param current_line number Current cursor line (1-indexed)
---@return number|nil prev_line Line of previous thread, or nil
function M.prev_thread_line(positions, current_line)
  local best = nil
  for line, _ in pairs(positions) do
    if line < current_line then
      if best == nil or line > best then
        best = line
      end
    end
  end
  return best
end

--- Get the thread at or near the cursor line.
--- Checks exact match first, then searches upward for the nearest thread
--- (since virt_lines appear below the anchored line).
---@param positions table<number, ForgeReviewThread> Buffer line -> thread
---@param current_line number Current cursor line (1-indexed)
---@return ForgeReviewThread|nil thread
---@return number|nil anchor_line The buffer line the thread is anchored to
function M.thread_at_cursor(positions, current_line)
  -- Exact match
  if positions[current_line] then
    return positions[current_line], current_line
  end

  -- Search upward (thread virt_lines appear below the anchor line)
  for line = current_line - 1, math.max(1, current_line - 30), -1 do
    if positions[line] then
      return positions[line], line
    end
  end

  return nil, nil
end

--- Get the namespace ID (for external use / testing).
---@return number
function M.get_namespace()
  return ns
end

return M
