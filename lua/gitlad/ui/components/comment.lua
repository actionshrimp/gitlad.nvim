---@mod gitlad.ui.components.comment PR detail / conversation component
---@brief [[
--- A stateless component for rendering a full PR conversation view.
--- Renders PR header, body, comments, and reviews in a readable format.
--- Follows the same pattern as log_list.lua and pr_list.lua.
---@brief ]]

local M = {}

local types = require("gitlad.forge.types")

---@class CommentRenderOptions
---@field wrap_width? number Wrap text at this width (default: 80)
---@field checks_collapsed? boolean Whether checks section is collapsed (default: false)

---@class CommentLineInfo
---@field type string Line type discriminator
---@field pr? ForgePullRequest PR reference for header lines
---@field comment? ForgeComment Comment reference
---@field review? ForgeReview Review reference
---@field check? ForgeCheck Check reference for check lines

---@class CommentRenderResult
---@field lines string[] Formatted lines
---@field line_info table<number, CommentLineInfo> Maps line index (1-based) to line metadata
---@field ranges table<string, {start: number, end_line: number}> Named ranges for navigation

--- Wrap a string at word boundaries
---@param text string
---@param width number
---@param indent string
---@return string[]
local function wrap_text(text, width, indent)
  if not text or text == "" then
    return {}
  end

  local lines = {}
  -- Split on newlines first
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    if paragraph == "" then
      table.insert(lines, indent)
    else
      local line = indent
      for word in paragraph:gmatch("%S+") do
        if #line + #word + 1 > width and line ~= indent then
          table.insert(lines, line)
          line = indent .. word
        else
          if line == indent then
            line = indent .. word
          else
            line = line .. " " .. word
          end
        end
      end
      if line ~= indent or #lines == 0 then
        table.insert(lines, line)
      end
    end
  end

  return lines
end

--- Render a full PR detail view
---@param pr ForgePullRequest PR with comments, reviews, and timeline
---@param opts? CommentRenderOptions
---@return CommentRenderResult
function M.render(pr, opts)
  opts = opts or {}
  local width = opts.wrap_width or 80

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

  -- === PR Header ===
  local header_start = #result.lines + 1

  -- Title line
  add_line("#" .. pr.number .. " " .. pr.title, { type = "pr_header", pr = pr })

  -- Metadata line
  local state_text = types.format_pr_state(pr.state, pr.draft)
  local meta_parts = { "Author: @" .. pr.author.login, "State: " .. state_text }

  local decision = pr.review_decision
  -- Handle vim.NIL from JSON null
  if decision == vim.NIL then
    decision = nil
  end
  if decision then
    table.insert(meta_parts, "Reviews: " .. types.format_review_decision(decision))
  end
  add_line(table.concat(meta_parts, "  "), { type = "pr_metadata", pr = pr })

  -- Branch line
  local branch_line = "Base: "
    .. pr.base_ref
    .. " <- "
    .. pr.head_ref
    .. "  "
    .. types.format_diff_stat(pr.additions, pr.deletions)
  add_line(branch_line, { type = "pr_metadata", pr = pr })

  -- Labels line (if any)
  if pr.labels and #pr.labels > 0 then
    add_line("Labels: " .. table.concat(pr.labels, ", "), { type = "pr_metadata", pr = pr })
  end

  -- Merge status line (if available)
  if pr.mergeable or pr.merge_state_status then
    local merge_text = types.format_merge_status(pr.mergeable, pr.merge_state_status)
    add_line("Merge: " .. merge_text, { type = "pr_merge_status", pr = pr })
  end

  result.ranges["header"] = { start = header_start, end_line = #result.lines }

  -- Separator
  add_line("---", { type = "separator" })

  -- === PR Body ===
  if pr.body and pr.body ~= "" then
    local body_start = #result.lines + 1
    local body_lines = wrap_text(pr.body, width, "")
    for _, line in ipairs(body_lines) do
      add_line(line, { type = "pr_body", pr = pr })
    end
    result.ranges["body"] = { start = body_start, end_line = #result.lines }
  end

  -- === Checks Section (if available) ===
  if pr.checks_summary and pr.checks_summary.total > 0 then
    local checks_component = require("gitlad.ui.components.checks")
    local checks_result = checks_component.render(pr.checks_summary, {
      collapsed = opts.checks_collapsed or false,
    })

    -- Merge checks lines into result with offset
    local checks_offset = #result.lines
    for ci, cline in ipairs(checks_result.lines) do
      add_line(cline, checks_result.line_info[ci])
    end

    -- Merge ranges with offset
    for name, range in pairs(checks_result.ranges) do
      result.ranges[name] = {
        start = range.start + checks_offset,
        end_line = range.end_line + checks_offset,
      }
    end

    add_line("", nil)
  end

  -- Separator
  add_line("---", { type = "separator" })

  -- === Comments Section ===
  local comments = pr.comments or {}
  local comment_count = #comments
  add_line("Comments (" .. comment_count .. ")", { type = "section_header" })

  if comment_count > 0 then
    add_line("", nil)
    for _, comment in ipairs(comments) do
      local comment_start = #result.lines + 1

      -- Author + timestamp
      local time_str = types.relative_time(comment.created_at)
      local header = "  @" .. comment.author.login .. "  " .. time_str
      add_line(header, { type = "comment", comment = comment })

      -- Body
      local body_lines = wrap_text(comment.body, width - 2, "  ")
      for _, line in ipairs(body_lines) do
        add_line(line, { type = "comment", comment = comment })
      end

      add_line("", nil)
      result.ranges["comment_" .. comment.id] = { start = comment_start, end_line = #result.lines }
    end
  else
    add_line("", nil)
  end

  -- === Reviews Section ===
  local reviews = pr.reviews or {}
  -- Filter out PENDING reviews and reviews with no body
  local visible_reviews = {}
  for _, review in ipairs(reviews) do
    if review.state ~= "PENDING" then
      table.insert(visible_reviews, review)
    end
  end

  add_line("Reviews (" .. #visible_reviews .. ")", { type = "section_header" })

  if #visible_reviews > 0 then
    add_line("", nil)
    for _, review in ipairs(visible_reviews) do
      local review_start = #result.lines + 1

      -- Author + state + timestamp
      local time_str = types.relative_time(review.submitted_at)
      local header = "  @" .. review.author.login .. "  " .. review.state .. "  " .. time_str
      add_line(header, { type = "review", review = review })

      -- Body
      if review.body and review.body ~= "" then
        local body_lines = wrap_text(review.body, width - 2, "  ")
        for _, line in ipairs(body_lines) do
          add_line(line, { type = "review", review = review })
        end
      end

      -- Inline review comments
      if review.comments and #review.comments > 0 then
        for _, rc in ipairs(review.comments) do
          add_line("", nil)
          add_line(
            "    " .. rc.path .. ":" .. (rc.line or ""),
            { type = "review", review = review }
          )
          local rc_lines = wrap_text(rc.body, width - 4, "    ")
          for _, line in ipairs(rc_lines) do
            add_line(line, { type = "review", review = review })
          end
        end
      end

      add_line("", nil)
      result.ranges["review_" .. review.id] = { start = review_start, end_line = #result.lines }
    end
  else
    add_line("", nil)
  end

  return result
end

--- Apply syntax highlighting to a rendered comment view
---@param bufnr number Buffer number
---@param ns number Namespace ID
---@param start_line number 0-indexed line where the component starts in buffer
---@param result CommentRenderResult The render result to highlight
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

    if info.type == "pr_header" then
      -- Highlight PR number
      local num_start, num_end = line:find("#%d+")
      if num_start then
        hl.set(bufnr, ns, line_idx, num_start - 1, num_end, "GitladForgePRNumber")
      end
      -- Highlight title (rest of line after number)
      if num_end then
        hl.set(bufnr, ns, line_idx, num_end + 1, #line, "GitladForgePRTitle")
      end
    elseif info.type == "pr_metadata" then
      -- Highlight @author
      local author_start, author_end = line:find("@%S+")
      if author_start then
        hl.set(bufnr, ns, line_idx, author_start - 1, author_end, "GitladForgeCommentAuthor")
      end

      -- Highlight state
      for _, state in ipairs({ "OPEN", "CLOSED", "MERGED", "DRAFT" }) do
        local s_start, s_end = line:find(state, 1, true)
        if s_start then
          local state_hl = "GitladForgePRReviewRequired"
          if state == "OPEN" then
            state_hl = "GitladForgePRApproved"
          elseif state == "CLOSED" then
            state_hl = "GitladForgePRChangesRequested"
          elseif state == "MERGED" then
            state_hl = "GitladForgePRApproved"
          elseif state == "DRAFT" then
            state_hl = "GitladForgePRDraft"
          end
          hl.set(bufnr, ns, line_idx, s_start - 1, s_end, state_hl)
          break
        end
      end

      -- Highlight review decision
      for _, decision in ipairs({ "APPROVED", "CHANGES REQUESTED", "REVIEW REQUIRED" }) do
        local d_start, d_end = line:find(decision, 1, true)
        if d_start then
          local decision_hl = "GitladForgePRReviewRequired"
          if decision == "APPROVED" then
            decision_hl = "GitladForgePRApproved"
          elseif decision == "CHANGES REQUESTED" then
            decision_hl = "GitladForgePRChangesRequested"
          end
          hl.set(bufnr, ns, line_idx, d_start - 1, d_end, decision_hl)
          break
        end
      end

      -- Highlight diff stat
      local add_start, add_end = line:find("+%d+")
      if add_start then
        hl.set(bufnr, ns, line_idx, add_start - 1, add_end, "GitladForgePRAdditions")
      end
      local del_start, del_end = line:find("-%d+", add_end or 1)
      if del_start then
        hl.set(bufnr, ns, line_idx, del_start - 1, del_end, "GitladForgePRDeletions")
      end

      -- Highlight labels
      local label_start = line:find("Labels: ")
      if label_start then
        hl.set(bufnr, ns, line_idx, label_start - 1 + 8, #line, "GitladForgeLabel")
      end
    elseif info.type == "pr_merge_status" then
      -- Highlight "Merge: " label
      local prefix = "Merge: "
      hl.set(bufnr, ns, line_idx, 0, #prefix, "Comment")
      -- Highlight the status text with appropriate color
      if info.pr then
        local _, merge_hl = types.format_merge_status(info.pr.mergeable, info.pr.merge_state_status)
        hl.set(bufnr, ns, line_idx, #prefix, #line, merge_hl)
      end
    elseif info.type == "checks_header" or info.type == "check" then
      -- Delegate to checks component highlighting
      local checks_component = require("gitlad.ui.components.checks")
      -- Build a minimal single-line result for the checks highlighter
      local single_result = {
        lines = { line },
        line_info = { [1] = info },
        ranges = {},
      }
      checks_component.apply_highlights(bufnr, ns, line_idx, single_result)
    elseif info.type == "separator" then
      hl.set(bufnr, ns, line_idx, 0, #line, "Comment")
    elseif info.type == "section_header" then
      hl.set(bufnr, ns, line_idx, 0, #line, "GitladSectionHeader")
    elseif info.type == "comment" then
      -- Highlight @author
      local author_start, author_end = line:find("@%S+")
      if author_start then
        hl.set(bufnr, ns, line_idx, author_start - 1, author_end, "GitladForgeCommentAuthor")
        -- Highlight timestamp (rest of line after author)
        if author_end < #line then
          hl.set(bufnr, ns, line_idx, author_end + 2, #line, "GitladForgeCommentTimestamp")
        end
      end
    elseif info.type == "review" then
      -- Highlight @author
      local author_start, author_end = line:find("@%S+")
      if author_start then
        hl.set(bufnr, ns, line_idx, author_start - 1, author_end, "GitladForgeCommentAuthor")
      end

      -- Highlight review state
      for _, state in ipairs({ "APPROVED", "CHANGES_REQUESTED", "COMMENTED", "DISMISSED" }) do
        local s_start, s_end = line:find(state, 1, true)
        if s_start then
          local state_hl = "GitladForgePRReviewRequired"
          if state == "APPROVED" then
            state_hl = "GitladForgePRApproved"
          elseif state == "CHANGES_REQUESTED" then
            state_hl = "GitladForgePRChangesRequested"
          elseif state == "COMMENTED" then
            state_hl = "Comment"
          elseif state == "DISMISSED" then
            state_hl = "Comment"
          end
          hl.set(bufnr, ns, line_idx, s_start - 1, s_end, state_hl)
          break
        end
      end

      -- Highlight file paths (path:line)
      local path_match = line:match("^    (.+:%d*)$")
      if path_match then
        hl.set(bufnr, ns, line_idx, 4, 4 + #path_match, "GitladFilePath")
      end
    end

    ::continue::
  end
end

return M
