---@mod gitlad.ui.views.status_sections Status buffer section registry
---@brief [[
--- Defines available sections for the status buffer and their render functions.
--- Used by status_render.lua to render sections in configurable order.
---@brief ]]

local M = {}

local config = require("gitlad.config")
local git = require("gitlad.git")
local log_list = require("gitlad.ui.components.log_list")

-- Default section order (matches original hardcoded behavior)
-- Note: submodules excluded by default (like magit) - add explicitly if needed
M.DEFAULT_SECTIONS = {
  "untracked",
  "unstaged",
  "staged",
  "conflicted",
  "stashes",
  { "worktrees", min_count = 2 },
  "unpushed",
  "unpulled",
  "recent",
}

---@class SectionRenderContext
---@field self StatusBuffer The status buffer instance
---@field status table Git status data
---@field cfg GitladConfig Plugin configuration
---@field lines string[] Output lines array (mutated by render functions)
---@field add_section_header fun(name: string, section: string, count: number): boolean
---@field add_file_line fun(entry: table, section: string, sign: string, status_char: string|nil, use_display: boolean)
---@field add_commit_section fun(title: string, commits: table[], section_type: string)
---@field show_tags boolean Whether to show tags in commit sections

--- Normalize a section config entry to name and options
---@param section GitladSection
---@return string name
---@return table opts
function M.normalize_section(section)
  if type(section) == "string" then
    return section, {}
  elseif type(section) == "table" then
    local name = section[1]
    local opts = {}
    for k, v in pairs(section) do
      if type(k) ~= "number" then
        opts[k] = v
      end
    end
    return name, opts
  end
  return "", {}
end

--- Get the configured sections list (or defaults)
---@return GitladSection[]
function M.get_sections()
  local cfg = config.get()
  return cfg.status.sections or M.DEFAULT_SECTIONS
end

-- ============================================================================
-- Section render functions
-- Each function receives a SectionRenderContext and optional section options
-- ============================================================================

---@param ctx SectionRenderContext
---@param _opts table
local function render_untracked(ctx, _opts)
  local status = ctx.status
  if #status.untracked == 0 then
    return
  end

  local is_expanded = ctx.add_section_header("Untracked", "untracked", #status.untracked)
  if is_expanded then
    for _, entry in ipairs(status.untracked) do
      ctx.add_file_line(entry, "untracked", ctx.cfg.signs.untracked, nil, false)
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_unstaged(ctx, _opts)
  local status = ctx.status
  if #status.unstaged == 0 then
    return
  end

  local is_expanded = ctx.add_section_header("Unstaged", "unstaged", #status.unstaged)
  if is_expanded then
    for _, entry in ipairs(status.unstaged) do
      ctx.add_file_line(entry, "unstaged", ctx.cfg.signs.unstaged, entry.worktree_status, false)
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_staged(ctx, _opts)
  local status = ctx.status
  if #status.staged == 0 then
    return
  end

  local is_expanded = ctx.add_section_header("Staged", "staged", #status.staged)
  if is_expanded then
    for _, entry in ipairs(status.staged) do
      ctx.add_file_line(entry, "staged", ctx.cfg.signs.staged, entry.index_status, true)
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_conflicted(ctx, _opts)
  local status = ctx.status
  if #status.conflicted == 0 then
    return
  end

  local is_expanded = ctx.add_section_header("Conflicted", "conflicted", #status.conflicted)
  if is_expanded then
    for _, entry in ipairs(status.conflicted) do
      ctx.add_file_line(entry, "conflicted", ctx.cfg.signs.conflict, nil, false)
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_stashes(ctx, _opts)
  local status = ctx.status
  local self = ctx.self
  if not status.stashes or #status.stashes == 0 then
    return
  end

  local is_collapsed = self.collapsed_sections["stashes"]
  table.insert(ctx.lines, string.format("Stashes (%d)", #status.stashes))
  self.section_lines[#ctx.lines] = { name = "Stashes", section = "stashes" }
  self.sign_lines[#ctx.lines] = { expanded = not is_collapsed }

  if not is_collapsed then
    for _, stash in ipairs(status.stashes) do
      table.insert(ctx.lines, string.format("%s %s", stash.ref, stash.message))
      self.line_map[#ctx.lines] = {
        type = "stash",
        stash = stash,
        section = "stashes",
      }
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_submodules(ctx, _opts)
  local status = ctx.status
  local self = ctx.self

  if not status.submodules or #status.submodules == 0 then
    return
  end

  local is_collapsed = self.collapsed_sections["submodules"]
  table.insert(ctx.lines, string.format("Submodules (%d)", #status.submodules))
  self.section_lines[#ctx.lines] = { name = "Submodules", section = "submodules" }
  self.sign_lines[#ctx.lines] = { expanded = not is_collapsed }

  if not is_collapsed then
    for _, submodule in ipairs(status.submodules) do
      -- Format: status indicator, path, (describe or SHA)
      local status_char = ""
      if submodule.status == "modified" then
        status_char = "+"
      elseif submodule.status == "uninitialized" then
        status_char = "-"
      elseif submodule.status == "merge_conflict" then
        status_char = "U"
      end

      -- Show describe if available, otherwise abbreviated SHA
      local info = submodule.describe or submodule.sha:sub(1, 7)
      local line_text
      if status_char ~= "" then
        line_text = string.format("  %s %s (%s)", status_char, submodule.path, info)
      else
        line_text = string.format("    %s (%s)", submodule.path, info)
      end

      table.insert(ctx.lines, line_text)
      self.line_map[#ctx.lines] = {
        type = "submodule",
        submodule = submodule,
        section = "submodules",
      }

      -- Check if submodule is expanded and render SHA diff
      local cache_key = "submodule:" .. submodule.path
      if self.expanded_files[cache_key] then
        local diff_data = self.diff_cache[cache_key]
        if diff_data and diff_data.is_submodule then
          self.sign_lines[#ctx.lines] = { expanded = true }
          -- Render the SHA diff lines: -oldsha, +newsha
          table.insert(ctx.lines, "-" .. diff_data.old_sha)
          self.line_map[#ctx.lines] = { type = "submodule_diff", diff_type = "delete" }
          table.insert(ctx.lines, "+" .. diff_data.new_sha)
          self.line_map[#ctx.lines] = { type = "submodule_diff", diff_type = "add" }
        end
      else
        self.sign_lines[#ctx.lines] = { expanded = false }
      end
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param opts table
local function render_worktrees(ctx, opts)
  local status = ctx.status
  local self = ctx.self
  local pending_ops = require("gitlad.state.pending_ops")

  -- Count pending "add" ops for this repo (they show as phantom lines)
  local repo_root = self.repo_state.repo_root:gsub("/$", "")
  local pending_adds = {}
  for _, op in pairs(pending_ops.get_all()) do
    if op.type == "add" and op.repo_root:gsub("/$", "") == repo_root then
      -- Only count if not already in the worktree list
      local already_listed = false
      if status.worktrees then
        for _, wt in ipairs(status.worktrees) do
          if wt.path:gsub("/$", "") == op.path then
            already_listed = true
            break
          end
        end
      end
      if not already_listed then
        table.insert(pending_adds, op)
      end
    end
  end

  -- min_count controls minimum worktrees needed to show section (default: 2, like magit)
  local min_count = opts.min_count or 2
  local worktree_count = status.worktrees and #status.worktrees or 0
  if worktree_count + #pending_adds < min_count then
    return
  end

  local is_collapsed = self.collapsed_sections["worktrees"]
  table.insert(ctx.lines, string.format("Worktrees (%d)", worktree_count))
  self.section_lines[#ctx.lines] = { name = "Worktrees", section = "worktrees" }
  self.sign_lines[#ctx.lines] = { expanded = not is_collapsed }

  if not is_collapsed then
    -- Normalize repo_root path for comparison (remove trailing slash)
    local current_repo_root = repo_root

    -- Compute max branch name length for tabular alignment
    local max_branch_len = 0
    if status.worktrees then
      for _, worktree in ipairs(status.worktrees) do
        local branch_info = worktree.branch or "(detached)"
        max_branch_len = math.max(max_branch_len, #branch_info)
      end
    end
    -- Account for pending add phantom lines (use "(creating...)" as branch placeholder)
    for _ in ipairs(pending_adds) do
      max_branch_len = math.max(max_branch_len, #"(creating...)")
    end

    if status.worktrees then
      for _, worktree in ipairs(status.worktrees) do
        local branch_info = worktree.branch or "(detached)"
        -- Compute relative path (cwd-relative first, fallback to home-relative)
        local short_path = vim.fn.fnamemodify(worktree.path, ":.")
        if short_path:sub(1, 1) == "/" then
          short_path = vim.fn.fnamemodify(worktree.path, ":~")
        end
        if short_path:sub(-1) ~= "/" then
          short_path = short_path .. "/"
        end

        local line_text = string.format("%-" .. max_branch_len .. "s  %s", branch_info, short_path)

        table.insert(ctx.lines, line_text)
        self.line_map[#ctx.lines] = {
          type = "worktree",
          worktree = worktree,
          section = "worktrees",
        }

        -- Place current/locked/pending indicators in the sign column (gutter)
        local wt_path = worktree.path:gsub("/$", "")
        if pending_ops.is_pending(wt_path) then
          self.sign_lines[#ctx.lines] =
            { sign_text = pending_ops.get_spinner_char(), sign_hl = "GitladWorktreePending" }
        elseif wt_path == current_repo_root then
          self.sign_lines[#ctx.lines] = { sign_text = "*", sign_hl = "GitladWorktreeCurrent" }
        elseif worktree.locked then
          self.sign_lines[#ctx.lines] = { sign_text = "L", sign_hl = "GitladWorktreeLocked" }
        end
      end
    end

    -- Render phantom lines for pending "add" ops
    for _, op in ipairs(pending_adds) do
      local short_path = vim.fn.fnamemodify(op.path, ":.")
      if short_path:sub(1, 1) == "/" then
        short_path = vim.fn.fnamemodify(op.path, ":~")
      end
      if short_path:sub(-1) ~= "/" then
        short_path = short_path .. "/"
      end

      local line_text =
        string.format("%-" .. max_branch_len .. "s  %s", "(creating...)", short_path)

      table.insert(ctx.lines, line_text)
      self.line_map[#ctx.lines] = {
        type = "worktree_pending",
        path = op.path,
        section = "worktrees",
      }
      self.sign_lines[#ctx.lines] =
        { sign_text = pending_ops.get_spinner_char(), sign_hl = "GitladWorktreePending" }
    end
  end
  table.insert(ctx.lines, "")
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_unpushed(ctx, _opts)
  local status = ctx.status

  -- Track whether we have any unpushed commits (used to decide whether to show recent commits)
  local has_unpushed_upstream = status.upstream
    and status.unpushed_upstream
    and #status.unpushed_upstream > 0

  if status.push_remote then
    -- Push remote is different from upstream - show push remote sections first
    -- 1. User's commits to push remote (most important - your own work)
    ctx.add_commit_section(
      "Unpushed to " .. status.push_remote,
      status.unpushed_push or {},
      "unpushed_push"
    )
    -- 2. User's commits not yet in upstream (if upstream exists)
    if status.upstream and has_unpushed_upstream then
      ctx.add_commit_section(
        "Unmerged into " .. status.upstream,
        status.unpushed_upstream or {},
        "unpushed_upstream"
      )
    end
  elseif status.upstream then
    -- No separate push remote - just show upstream sections
    if has_unpushed_upstream then
      ctx.add_commit_section(
        "Unmerged into " .. status.upstream,
        status.unpushed_upstream or {},
        "unpushed_upstream"
      )
    end
  end
end

---@param ctx SectionRenderContext
---@param _opts table
local function render_unpulled(ctx, _opts)
  local status = ctx.status

  if status.push_remote then
    -- Push remote is different from upstream
    -- 1. Commits to pull from push remote
    ctx.add_commit_section(
      "Unpulled from " .. status.push_remote,
      status.unpulled_push or {},
      "unpulled_push"
    )
    -- 2. Commits to pull from upstream (last - often has many commits)
    if status.upstream then
      ctx.add_commit_section(
        "Unpulled from " .. status.upstream,
        status.unpulled_upstream or {},
        "unpulled_upstream"
      )
    end
  elseif status.upstream then
    -- No separate push remote - just show upstream
    ctx.add_commit_section(
      "Unpulled from " .. status.upstream,
      status.unpulled_upstream or {},
      "unpulled_upstream"
    )
  end
end

---@param ctx SectionRenderContext
---@param opts table
local function render_recent(ctx, opts)
  local status = ctx.status
  local commits = status.recent_commits

  if not commits or #commits == 0 then
    return
  end

  -- Apply count limit if specified
  local count = opts.count
  if count and count > 0 and #commits > count then
    local limited = {}
    for i = 1, count do
      limited[i] = commits[i]
    end
    commits = limited
  end

  ctx.add_commit_section("Recent commits", commits, "recent")
end

-- Section definitions registry
-- Maps section name to render function
M.SECTION_DEFS = {
  untracked = { render = render_untracked },
  unstaged = { render = render_unstaged },
  staged = { render = render_staged },
  conflicted = { render = render_conflicted },
  stashes = { render = render_stashes },
  submodules = { render = render_submodules },
  worktrees = { render = render_worktrees },
  unpushed = { render = render_unpushed },
  unpulled = { render = render_unpulled },
  recent = { render = render_recent },
}

--- Check if a section has any file content to display
--- Used by status_render to decide whether to show "Nothing to commit" message
---@param status table Git status data
---@return boolean
function M.has_file_changes(status)
  return #status.staged > 0
    or #status.unstaged > 0
    or #status.untracked > 0
    or #status.conflicted > 0
end

return M
