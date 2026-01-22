---@mod gitlad.popups.diff Diff popup
---@brief [[
--- Transient-style diff popup that delegates to diffview.nvim.
--- Context-aware: adapts actions based on cursor position (file vs commit).
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")

---@class DiffContext
---@field file_path? string File under cursor (if any)
---@field section? string Section type (staged/unstaged/untracked/commit)
---@field commit? GitCommitInfo Commit under cursor (if any)
---@field ref? string Ref name under cursor (from refs buffer)
---@field base_ref? string Base ref being compared against (from refs buffer)

--- Check if diffview.nvim is available
---@return boolean has_diffview
---@return table|nil diffview The diffview module if available
local function check_diffview()
  local ok, diffview = pcall(require, "diffview")
  return ok, ok and diffview or nil
end

--- Open diffview with args, or show fallback
---@param args string[] Arguments to pass to diffview.open()
---@param fallback_cmd? string Fallback git command if diffview not available
local function open_diffview(args, fallback_cmd)
  local has_diffview, diffview = check_diffview()

  if has_diffview then
    diffview.open(args)
  else
    -- Fallback: show notification with install hint
    local msg = "[gitlad] diffview.nvim not installed. "
    if fallback_cmd then
      msg = msg .. "Showing in terminal..."
      vim.notify(msg, vim.log.levels.WARN)
      vim.cmd("botright split")
      vim.cmd("terminal " .. fallback_cmd)
      vim.cmd("startinsert")
    else
      msg = msg .. "Install with: { 'sindrets/diffview.nvim' }"
      vim.notify(msg, vim.log.levels.WARN)
    end
  end
end

--- Diff staged changes (index vs HEAD)
---@param repo_state RepoState
function M._diff_staged(repo_state)
  open_diffview({ "--cached" }, "git diff --cached")
end

--- Diff unstaged changes (working tree vs index)
---@param repo_state RepoState
function M._diff_unstaged(repo_state)
  open_diffview({}, "git diff")
end

--- Diff worktree (working tree vs HEAD)
---@param repo_state RepoState
function M._diff_worktree(repo_state)
  open_diffview({ "HEAD" }, "git diff HEAD")
end

--- Show commit diff
---@param repo_state RepoState
---@param commit GitCommitInfo
function M._diff_commit(repo_state, commit)
  if not commit then
    vim.notify("[gitlad] No commit under cursor", vim.log.levels.WARN)
    return
  end
  open_diffview({ commit.hash .. "^!" }, "git show " .. commit.hash)
end

--- Diff range (prompt for refs)
---@param repo_state RepoState
---@param default_range? string Default range to show in prompt
function M._diff_range(repo_state, default_range)
  vim.ui.input(
    { prompt = "Diff range (e.g., main..HEAD): ", default = default_range or "" },
    function(input)
      if not input or input == "" then
        return
      end
      open_diffview({ input }, "git diff " .. input)
    end
  )
end

--- Diff a ref against another ref
---@param repo_state RepoState
---@param ref string The ref to diff
---@param base string The base ref to compare against
function M._diff_ref_against(repo_state, ref, base)
  local range = base .. ".." .. ref
  open_diffview({ range }, "git diff " .. range)
end

--- Diff a ref against another ref (prompt for base)
---@param repo_state RepoState
---@param ref string The ref to diff
function M._diff_ref_against_prompt(repo_state, ref)
  vim.ui.input({ prompt = "Diff " .. ref .. " against: ", default = "HEAD" }, function(base)
    if not base or base == "" then
      return
    end
    M._diff_ref_against(repo_state, ref, base)
  end)
end

--- Diff changes on a ref since it diverged from base (three-dot range)
--- Shows commits reachable from ref but not from the common ancestor of base and ref.
--- This is useful to see "what's on this branch that's not on main".
---@param repo_state RepoState
---@param ref string The ref to show changes for
---@param base string The base ref to compare against
function M._diff_ref_changes(repo_state, ref, base)
  local range = base .. "..." .. ref
  open_diffview({ range }, "git diff " .. range)
end

--- Diff changes on a ref since it diverged from another branch (prompt for base)
--- Uses three-dot syntax to show only changes unique to the ref.
---@param repo_state RepoState
---@param ref string The ref to show changes for
function M._diff_ref_changes_prompt(repo_state, ref)
  vim.ui.input({ prompt = "Show " .. ref .. " changes vs: ", default = "main" }, function(base)
    if not base or base == "" then
      return
    end
    M._diff_ref_changes(repo_state, ref, base)
  end)
end

--- 3-way staging view (HEAD/index/working tree)
--- Opens diffview with both "Changes" (unstaged) and "Staged changes" sections.
--- Index buffers are editable - writing to them updates the git index.
--- Working tree buffers are also editable.
---@param repo_state RepoState
function M._diff_3way(repo_state)
  local has_diffview, diffview = check_diffview()

  if has_diffview then
    -- Open with no args to get the staging view showing both
    -- "Changes" (index vs working tree) and "Staged changes" (HEAD vs index)
    diffview.open({})
  else
    vim.notify(
      "[gitlad] 3-way staging view requires diffview.nvim. Install with: { 'sindrets/diffview.nvim' }",
      vim.log.levels.WARN
    )
  end
end

--- Context-aware diff (do what I mean)
---@param repo_state RepoState
---@param context DiffContext
function M._diff_dwim(repo_state, context)
  -- If on a ref, diff against base_ref (or HEAD)
  if context.ref then
    local base = context.base_ref or "HEAD"
    M._diff_ref_against(repo_state, context.ref, base)
    return
  end

  -- If on a commit, show commit diff
  if context.commit then
    M._diff_commit(repo_state, context.commit)
    return
  end

  -- If on a file, diff based on section
  if context.file_path then
    if context.section == "staged" then
      M._diff_staged(repo_state)
    else
      -- unstaged, untracked, or unknown -> diff unstaged
      M._diff_unstaged(repo_state)
    end
    return
  end

  -- Default: show unstaged changes
  M._diff_unstaged(repo_state)
end

--- Create and show the diff popup
---@param repo_state RepoState
---@param context? DiffContext Context about cursor position
function M.open(repo_state, context)
  context = context or {}

  local builder = popup
    .builder()
    :name("Diff")
    :group_heading("Diffing")
    :action("d", "Diff (dwim)", function()
      M._diff_dwim(repo_state, context)
    end)
    :action("s", "Diff staged", function()
      M._diff_staged(repo_state)
    end)
    :action("u", "Diff unstaged", function()
      M._diff_unstaged(repo_state)
    end)
    :action("w", "Diff worktree", function()
      M._diff_worktree(repo_state)
    end)
    :action("r", "Diff range...", function()
      M._diff_range(repo_state)
    end)

  -- Add commit action only if we have a commit in context
  if context.commit then
    builder:action("c", "Show commit", function()
      M._diff_commit(repo_state, context.commit)
    end)
  end

  -- Add ref-specific actions
  if context.ref then
    local base = context.base_ref or "HEAD"
    local ref = context.ref
    builder:action("b", "Diff " .. ref .. ".." .. base, function()
      M._diff_ref_against(repo_state, ref, base)
    end)
    builder:action("o", "Diff " .. ref .. " against...", function()
      M._diff_ref_against_prompt(repo_state, ref)
    end)
    builder:action("m", "Changes on " .. ref .. " vs...", function()
      M._diff_ref_changes_prompt(repo_state, ref)
    end)
  end

  -- Add 3-way staging view for index-related sections (staged/unstaged)
  if context.section == "staged" or context.section == "unstaged" then
    builder:action("3", "3-way (HEAD/index/worktree)", function()
      M._diff_3way(repo_state)
    end)
  end

  local diff_popup = builder:build()
  diff_popup:show()
end

return M
