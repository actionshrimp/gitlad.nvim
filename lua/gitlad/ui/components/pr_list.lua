---@mod gitlad.ui.components.pr_list Reusable PR list component
---@brief [[
--- A stateless component for rendering pull request lists.
--- Used by the PR list view. Follows the same pattern as log_list.lua.
---@brief ]]

local M = {}

local types = require("gitlad.forge.types")

---@class PRListOptions
---@field indent number|nil Spaces to indent (default: 0)
---@field max_title_len number|nil Truncate title at this length (default: 50)
---@field show_diff_stat boolean|nil Show +/- stats (default: true)
---@field show_review boolean|nil Show review decision (default: true)
---@field show_author boolean|nil Show author (default: true)

---@class PRLineInfo
---@field type "pr" Discriminator for union type
---@field number number PR number
---@field pr ForgePullRequest Full PR info

---@class PRListResult
---@field lines string[] Formatted lines
---@field line_info table<number, PRLineInfo> Maps line index (1-based) to PR info

--- Format PR number with consistent width
---@param number number PR number
---@return string
local function format_number(number)
  return "#" .. number
end

--- Format author for display
---@param author ForgeUser
---@return string
local function format_author(author)
  return "@" .. author.login
end

--- Render a list of PRs into formatted lines with metadata
---@param prs ForgePullRequest[] List of PRs to render
---@param opts PRListOptions|nil Rendering options
---@return PRListResult
function M.render(prs, opts)
  opts = opts or {}
  local indent_str = string.rep(" ", opts.indent or 0)
  local max_title = opts.max_title_len or 50
  local show_diff = opts.show_diff_stat ~= false
  local show_review = opts.show_review ~= false
  local show_author = opts.show_author ~= false

  local result = {
    lines = {},
    line_info = {},
  }

  if #prs == 0 then
    return result
  end

  -- Calculate column widths for alignment
  local max_num_width = 0
  local max_author_width = 0
  for _, pr in ipairs(prs) do
    local num_str = format_number(pr.number)
    if #num_str > max_num_width then
      max_num_width = #num_str
    end
    if show_author then
      local author_str = format_author(pr.author)
      if #author_str > max_author_width then
        max_author_width = #author_str
      end
    end
  end

  for _, pr in ipairs(prs) do
    local parts = { indent_str }

    -- PR number (right-aligned in column)
    local num_str = format_number(pr.number)
    local num_padding = string.rep(" ", max_num_width - #num_str)
    table.insert(parts, num_padding .. num_str)
    table.insert(parts, " ")

    -- Title (truncated)
    local title = pr.title
    if pr.draft then
      title = "[Draft] " .. title
    end
    if #title > max_title then
      title = title:sub(1, max_title - 3) .. "..."
    end
    -- Pad title to consistent width for alignment
    local title_padded = title .. string.rep(" ", max_title - #title)
    table.insert(parts, title_padded)
    table.insert(parts, "  ")

    -- Author
    if show_author then
      local author_str = format_author(pr.author)
      local author_padded = author_str .. string.rep(" ", max_author_width - #author_str)
      table.insert(parts, author_padded)
      table.insert(parts, "  ")
    end

    -- Diff stat
    if show_diff then
      table.insert(parts, types.format_diff_stat(pr.additions, pr.deletions))
      table.insert(parts, "  ")
    end

    -- Review decision
    if show_review then
      local decision = pr.review_decision
      -- vim.NIL comes from JSON null values
      if decision == vim.NIL then
        decision = nil
      end
      local review_str = types.format_review_decision(decision)
      if review_str ~= "" then
        table.insert(parts, review_str)
      end
    end

    local line = table.concat(parts)
    -- Trim trailing whitespace
    line = line:gsub("%s+$", "")
    table.insert(result.lines, line)
    result.line_info[#result.lines] = {
      type = "pr",
      number = pr.number,
      pr = pr,
    }
  end

  return result
end

--- Apply syntax highlighting to rendered PR list
---@param bufnr number Buffer number
---@param ns number Namespace ID
---@param start_line number 0-indexed line where the PR list starts in buffer
---@param result PRListResult The render result to highlight
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

    local pr = info.pr

    -- Highlight PR number (#123)
    local num_start, num_end = line:find("#%d+")
    if num_start then
      hl.set(bufnr, ns, line_idx, num_start - 1, num_end, "GitladForgePRNumber")
    end

    -- Highlight author (@username)
    local author_start, author_end = line:find("@%S+")
    if author_start then
      hl.set(bufnr, ns, line_idx, author_start - 1, author_end, "GitladForgePRAuthor")
    end

    -- Highlight diff stat (+N)
    local add_start, add_end = line:find("+%d+")
    if add_start then
      hl.set(bufnr, ns, line_idx, add_start - 1, add_end, "GitladForgePRAdditions")
    end

    -- Highlight diff stat (-N)
    local del_start, del_end = line:find("-%d+", add_end or 1)
    if del_start then
      hl.set(bufnr, ns, line_idx, del_start - 1, del_end, "GitladForgePRDeletions")
    end

    -- Highlight review decision
    local decision = pr.review_decision
    if decision == vim.NIL then
      decision = nil
    end
    if decision then
      local review_text = require("gitlad.forge.types").format_review_decision(decision)
      if review_text ~= "" then
        local rev_start = line:find(review_text, 1, true)
        if rev_start then
          local rev_end = rev_start + #review_text
          local review_hl = "GitladForgePRReviewRequired"
          if decision == "APPROVED" then
            review_hl = "GitladForgePRApproved"
          elseif decision == "CHANGES_REQUESTED" then
            review_hl = "GitladForgePRChangesRequested"
          end
          hl.set(bufnr, ns, line_idx, rev_start - 1, rev_end - 1, review_hl)
        end
      end
    end

    -- Highlight [Draft] indicator
    if pr.draft then
      local draft_start, draft_end = line:find("%[Draft%]")
      if draft_start then
        hl.set(bufnr, ns, line_idx, draft_start - 1, draft_end, "GitladForgePRDraft")
      end
    end

    ::continue::
  end
end

return M
