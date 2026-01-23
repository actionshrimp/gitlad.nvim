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

--- Diff range with ref context - multi-step picker workflow
--- Step 1: Ask what to diff against
--- Step 2: Ask for range type (.. or ...)
---@param repo_state RepoState
---@param ref string The ref to diff
function M._diff_range_with_context(repo_state, ref)
  -- Step 1: Ask what to diff against
  vim.ui.input({ prompt = "Diff " .. ref .. " against: ", default = "main" }, function(base)
    if not base or base == "" then
      return
    end

    -- Step 2: Ask for range type with descriptive text
    local range_options = {
      {
        value = "..",
        label = ".. (two-dot)",
        desc = "Shows all differences between " .. base .. " and " .. ref,
      },
      {
        value = "...",
        label = "... (three-dot)",
        desc = "Shows changes on " .. ref .. " since it diverged from " .. base,
      },
    }

    vim.ui.select(range_options, {
      prompt = "Range type:",
      format_item = function(item)
        return item.label .. " - " .. item.desc
      end,
    }, function(choice)
      if not choice then
        return
      end
      local range = base .. choice.value .. ref
      open_diffview({ range }, "git diff " .. range)
    end)
  end)
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
  -- Context-aware range action
  if context.ref then
    local ref = context.ref
    builder:action("r", "Diff " .. ref .. " against...", function()
      M._diff_range_with_context(repo_state, ref)
    end)
  else
    builder:action("r", "Diff range...", function()
      M._diff_range(repo_state)
    end)
  end

  -- Add commit action only if we have a commit in context
  if context.commit then
    builder:action("c", "Show commit", function()
      M._diff_commit(repo_state, context.commit)
    end)
  end

  -- Add quick ref diff using context's base_ref
  if context.ref then
    local base = context.base_ref or "HEAD"
    local ref = context.ref
    builder:action("b", "Diff " .. ref .. ".." .. base, function()
      M._diff_ref_against(repo_state, ref, base)
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
