---@mod gitlad.popups.diff Diff popup
---@brief [[
--- Transient-style diff popup with configurable viewer backend.
--- Context-aware: adapts actions based on cursor position (file vs commit).
---
--- Supports two viewers:
---   "native"   — built-in side-by-side diff viewer (default)
---   "diffview" — delegates to diffview.nvim
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local config = require("gitlad.config")

---@class DiffContext
---@field file_path? string File under cursor (if any)
---@field section? string Section type (staged/unstaged/untracked/commit)
---@field commit? GitCommitInfo Commit under cursor (if any)
---@field stash? StashEntry Stash under cursor (if any)
---@field ref? string Ref name under cursor (from refs buffer)
---@field base_ref? string Base ref being compared against (from refs buffer)
---@field ref_upstream? string Upstream tracking ref for the ref under cursor (e.g., origin/feature)
---@field current_upstream? string Upstream of the current (HEAD) branch (e.g., origin/main)

--- Check whether to use the native diff viewer
---@return boolean
local function use_native()
  return config.get().diff.viewer == "native"
end

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

--- Open the native diff viewer with the given DiffSpec
---@param spec DiffSpec|nil The diff specification
---@param err string|nil Error message from the producer
local function open_native(spec, err)
  if err then
    vim.notify("[gitlad] " .. err, vim.log.levels.ERROR)
    return
  end
  vim.schedule(function()
    local diff_view = require("gitlad.ui.views.diff")
    diff_view.open(spec)
  end)
end

--- Diff staged changes (index vs HEAD)
---@param repo_state RepoState
function M._diff_staged(repo_state)
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_staged(repo_state.repo_root, open_native)
  else
    open_diffview({ "--cached" }, "git diff --cached")
  end
end

--- Diff unstaged changes (working tree vs index)
---@param repo_state RepoState
function M._diff_unstaged(repo_state)
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_unstaged(repo_state.repo_root, open_native)
  else
    open_diffview({}, "git diff")
  end
end

--- Diff worktree (working tree vs HEAD)
---@param repo_state RepoState
function M._diff_worktree(repo_state)
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_worktree(repo_state.repo_root, open_native)
  else
    open_diffview({ "HEAD" }, "git diff HEAD")
  end
end

--- Show commit diff
---@param repo_state RepoState
---@param commit GitCommitInfo
function M._diff_commit(repo_state, commit)
  if not commit then
    vim.notify("[gitlad] No commit under cursor", vim.log.levels.WARN)
    return
  end
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_commit(repo_state.repo_root, commit.hash, open_native)
  else
    open_diffview({ commit.hash .. "^!" }, "git show " .. commit.hash)
  end
end

--- Show stash diff
---@param repo_state RepoState
---@param stash StashEntry
function M._diff_stash(repo_state, stash)
  if not stash then
    vim.notify("[gitlad] No stash under cursor", vim.log.levels.WARN)
    return
  end
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_stash(repo_state.repo_root, stash.ref, open_native)
  else
    open_diffview({ stash.ref .. "^!" }, "git stash show -p " .. stash.ref)
  end
end

--- Compute the default range expression based on context.
--- Uses three-dot (changes since divergence) as the default for branch comparisons.
---@param current_branch string|nil Current branch name
---@param upstream string|nil Upstream tracking branch
---@param context DiffContext Context about cursor position
---@return string|nil default_range Pre-computed range, or nil if no meaningful default
function M._compute_default_range(current_branch, upstream, context)
  if not context.ref then
    return nil
  end

  -- On a different branch than HEAD: compare base_ref against ref
  if context.base_ref and context.base_ref ~= context.ref then
    return context.base_ref .. "..." .. context.ref
  end

  -- On HEAD branch: use upstream if available
  if upstream then
    return upstream .. "..." .. context.ref
  end

  -- No meaningful default
  return nil
end

--- Diff range (prompt for range expression with contextual default)
---@param repo_state RepoState
---@param context DiffContext Context about cursor position
function M._diff_range(repo_state, context)
  local status = repo_state.status
  local current_branch = status and status.branch or nil
  local upstream_val = status and status.upstream or nil

  local default_range = M._compute_default_range(current_branch, upstream_val, context)

  vim.ui.input({
    prompt = "Diff range (e.g., main..HEAD): ",
    default = default_range or "",
    completion = "customlist,v:lua.gitlad_complete_refs",
  }, function(input)
    if not input or input == "" then
      return
    end
    if use_native() then
      local source = require("gitlad.ui.views.diff.source")
      source.produce_range(repo_state.repo_root, input, open_native)
    else
      open_diffview({ input }, "git diff " .. input)
    end
  end)
end

--- Diff ref against the current branch's upstream.
--- Uses the HEAD branch's upstream tracking ref (e.g., origin/main when on main
--- tracking origin/main). This shows changes unique to the ref compared to the
--- remote version of the merge target -- the most common comparison.
---@param repo_state RepoState
---@param context DiffContext Context about cursor position
function M._diff_upstream(repo_state, context)
  if not context.ref then
    vim.notify("[gitlad] No ref under cursor", vim.log.levels.WARN)
    return
  end

  -- Prefer the current (HEAD) branch's upstream -- this is typically origin/main,
  -- which is what users want when comparing a feature branch against the remote.
  -- Fall back to the ref's own upstream if HEAD has no upstream configured.
  local upstream = context.current_upstream or context.ref_upstream
  if not upstream then
    vim.notify("[gitlad] No upstream configured", vim.log.levels.WARN)
    return
  end

  local range = upstream .. "..." .. context.ref
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_range(repo_state.repo_root, range, open_native)
  else
    open_diffview({ range }, "git diff " .. range)
  end
end

--- Build range via guided 3-step flow (base ref -> range type -> other ref)
---@param repo_state RepoState
function M._diff_build_range(repo_state)
  local prompt_mod = require("gitlad.utils.prompt")
  prompt_mod.build_range_guided({ cwd = repo_state.repo_root }, function(range)
    if not range or range == "" then
      return
    end
    if use_native() then
      local source = require("gitlad.ui.views.diff.source")
      source.produce_range(repo_state.repo_root, range, open_native)
    else
      open_diffview({ range }, "git diff " .. range)
    end
  end)
end

--- Diff a ref against another ref
---@param repo_state RepoState
---@param ref string The ref to diff
---@param base string The base ref to compare against
function M._diff_ref_against(repo_state, ref, base)
  local range = base .. ".." .. ref
  if use_native() then
    local source = require("gitlad.ui.views.diff.source")
    source.produce_range(repo_state.repo_root, range, open_native)
  else
    open_diffview({ range }, "git diff " .. range)
  end
end

--- 3-way staging view (HEAD/index/working tree)
--- Opens diffview showing all files in a 3-pane layout: HEAD | INDEX | WORKING
--- Index buffers are editable - writing to them updates the git index.
--- Working tree buffers are also editable.
--- If file_path is provided, that file will be pre-selected.
---@param repo_state RepoState
---@param file_path? string Optional file path to pre-select
function M._diff_3way(repo_state, file_path)
  local has_diffview, diffview = check_diffview()

  if has_diffview then
    -- Pass --staging-3way to force ALL files into 3-pane view (HEAD | INDEX | WORKING)
    -- This works even for files that only have staged OR unstaged changes
    local args = { "--staging-3way" }
    if file_path then
      table.insert(args, "--selected-file=" .. file_path)
    end
    diffview.open(args)
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

  -- If on a stash, show stash diff
  if context.stash then
    M._diff_stash(repo_state, context.stash)
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
  -- Range action - unified flow with context-aware defaults
  builder:action("r", "Diff range...", function()
    M._diff_range(repo_state, context)
  end)

  -- Build range via guided flow (always available)
  builder:action("b", "Build range...", function()
    M._diff_build_range(repo_state)
  end)

  -- Add commit action only if we have a commit in context
  if context.commit then
    builder:action("c", "Show commit", function()
      M._diff_commit(repo_state, context.commit)
    end)
  end

  -- Diff against upstream (only when on a ref)
  if context.ref then
    local effective_upstream = context.current_upstream or context.ref_upstream
    local upstream_label
    if effective_upstream then
      upstream_label = "Diff " .. effective_upstream .. "..." .. context.ref
    else
      upstream_label = "Diff against upstream"
    end
    builder:action("U", upstream_label, function()
      M._diff_upstream(repo_state, context)
    end)
  end

  -- Add 3-way staging view for index-related sections (staged/unstaged)
  if context.section == "staged" or context.section == "unstaged" then
    builder:action("3", "3-way (HEAD/index/worktree)", function()
      M._diff_3way(repo_state, context.file_path)
    end)
  end

  local diff_popup = builder:build()
  diff_popup:show()
end

return M
