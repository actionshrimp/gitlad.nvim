---@mod gitlad.popups.log Log popup
---@brief [[
--- Transient-style log popup with switches, options, and actions.
--- Opens the log view with various filtering options.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Default number of commits to show
local DEFAULT_LIMIT = "256"

--- Build log arguments from popup state
---@param popup_data PopupData
---@param extra_args? string[] Additional args to append
---@return string[]
local function build_log_args(popup_data, extra_args)
  local args = {}

  -- Get switches
  for _, sw in ipairs(popup_data.switches) do
    if sw.enabled then
      table.insert(args, sw.cli)
    end
  end

  -- Get options
  for _, opt in ipairs(popup_data.options) do
    if opt.value and opt.value ~= "" then
      if opt.cli == "limit" then
        table.insert(args, "-" .. opt.value)
      elseif opt.cli == "author" then
        table.insert(args, "--author=" .. opt.value)
      elseif opt.cli == "since" then
        table.insert(args, "--since=" .. opt.value)
      elseif opt.cli == "until" then
        table.insert(args, "--until=" .. opt.value)
      end
    end
  end

  -- Append extra args
  if extra_args then
    vim.list_extend(args, extra_args)
  end

  return args
end

--- Open log view with given arguments
---@param repo_state RepoState
---@param args string[]
local function open_log_view(repo_state, args)
  -- For now, just fetch and display commits
  -- The full log buffer view will be implemented next
  vim.notify("[gitlad] Fetching log...", vim.log.levels.INFO)

  git.log_detailed(args, { cwd = repo_state.repo_root }, function(commits, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Log failed: " .. err, vim.log.levels.ERROR)
        return
      end

      if not commits or #commits == 0 then
        vim.notify("[gitlad] No commits found", vim.log.levels.INFO)
        return
      end

      -- Open the log view
      local log_view = require("gitlad.ui.views.log")
      log_view.open(repo_state, commits, args)
    end)
  end)
end

--- Create and show the log popup
---@param repo_state RepoState
function M.open(repo_state)
  -- Read current show_tags setting for display
  local show_tags = git.config_get_bool("gitlad.showTagsInRefs", { cwd = repo_state.repo_root })
  local tags_label = show_tags and "Hide tags in refs" or "Show tags in refs"

  local log_popup = popup
    .builder()
    :name("Log")
    -- Switches
    :switch("a", "--all", "All branches")
    :switch("m", "--merges", "Only merges")
    :switch("M", "--no-merges", "No merges")
    -- Options
    :option("n", "limit", DEFAULT_LIMIT, "Limit")
    :option("a", "author", "", "Author")
    :option("s", "since", "", "Since")
    :option("u", "until", "", "Until")
    -- Actions
    :group_heading("Log")
    :action("l", "Log current branch", function(popup_data)
      M._log_current(repo_state, popup_data)
    end)
    :action("o", "Log other branch", function(popup_data)
      M._log_other(repo_state, popup_data)
    end)
    :action("h", "Log HEAD", function(popup_data)
      M._log_head(repo_state, popup_data)
    end)
    :action("L", "Log all branches", function(popup_data)
      M._log_all(repo_state, popup_data)
    end)
    :group_heading("Reflog")
    :action("r", "Reflog current branch", function(_)
      M._reflog_current(repo_state)
    end)
    :action("O", "Reflog other ref", function(_)
      M._reflog_other(repo_state)
    end)
    :action("H", "Reflog HEAD", function(_)
      M._reflog_head(repo_state)
    end)
    :group_heading("Toggle")
    :action("t", tags_label, function(_)
      M._toggle_tags(repo_state)
    end)
    :build()

  log_popup:show()
end

--- Log current branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._log_current(repo_state, popup_data)
  local args = build_log_args(popup_data)
  open_log_view(repo_state, args)
end

--- Log other branch (prompts for branch selection)
---@param repo_state RepoState
---@param popup_data PopupData
function M._log_other(repo_state, popup_data)
  -- Get local branches
  git.branches({ cwd = repo_state.repo_root }, function(branches, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get branches: " .. err, vim.log.levels.ERROR)
        return
      end

      if not branches or #branches == 0 then
        vim.notify("[gitlad] No branches found", vim.log.levels.WARN)
        return
      end

      -- Build list of branch names
      local branch_names = {}
      for _, b in ipairs(branches) do
        table.insert(branch_names, b.name)
      end

      vim.ui.select(branch_names, {
        prompt = "Select branch to view log:",
      }, function(choice)
        if not choice then
          return
        end

        local args = build_log_args(popup_data, { choice })
        open_log_view(repo_state, args)
      end)
    end)
  end)
end

--- Log HEAD (no branch filter)
---@param repo_state RepoState
---@param popup_data PopupData
function M._log_head(repo_state, popup_data)
  local args = build_log_args(popup_data, { "HEAD" })
  open_log_view(repo_state, args)
end

--- Log all branches
---@param repo_state RepoState
---@param popup_data PopupData
function M._log_all(repo_state, popup_data)
  -- The --all switch should already be set, but ensure it's included
  local args = build_log_args(popup_data, { "--all" })
  open_log_view(repo_state, args)
end

--- Open reflog view with given entries
---@param repo_state RepoState
---@param ref string Git ref (e.g., "HEAD", branch name)
local function open_reflog_view(repo_state, ref)
  vim.notify("[gitlad] Fetching reflog for " .. ref .. "...", vim.log.levels.INFO)

  git.reflog(ref, { cwd = repo_state.repo_root }, function(entries, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Reflog failed: " .. err, vim.log.levels.ERROR)
        return
      end

      if not entries or #entries == 0 then
        vim.notify("[gitlad] No reflog entries found for " .. ref, vim.log.levels.INFO)
        return
      end

      -- Open the reflog view
      local reflog_view = require("gitlad.ui.views.reflog")
      reflog_view.open(repo_state, ref, entries)
    end)
  end)
end

--- Reflog current branch
---@param repo_state RepoState
function M._reflog_current(repo_state)
  local status = repo_state:get_status()
  if status and status.branch and status.branch ~= "" then
    open_reflog_view(repo_state, status.branch)
  else
    vim.notify("[gitlad] No current branch found", vim.log.levels.WARN)
  end
end

--- Reflog other ref (prompts for ref selection)
---@param repo_state RepoState
function M._reflog_other(repo_state)
  -- Use prompt utility to get ref input
  local prompt = require("gitlad.utils.prompt")
  prompt.prompt_for_ref({ prompt = "Reflog for ref: " }, function(ref)
    if ref and ref ~= "" then
      open_reflog_view(repo_state, ref)
    end
  end)
end

--- Reflog HEAD
---@param repo_state RepoState
function M._reflog_head(repo_state)
  open_reflog_view(repo_state, "HEAD")
end

--- Toggle showing tags in refs
---@param repo_state RepoState
function M._toggle_tags(repo_state)
  git.config_toggle(
    "gitlad.showTagsInRefs",
    { cwd = repo_state.repo_root },
    function(new_value, err)
      vim.schedule(function()
        if err then
          vim.notify("[gitlad] Failed to toggle tags: " .. err, vim.log.levels.ERROR)
          return
        end

        local msg = new_value and "Tags in refs: shown" or "Tags in refs: hidden"
        vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)

        -- Refresh status view if open
        local status_view = require("gitlad.ui.views.status")
        local status_buf = status_view.get_buffer(repo_state)
        if status_buf then
          status_buf:render()
        end

        -- Refresh log view if open
        local log_view = require("gitlad.ui.views.log")
        local log_buf = log_view.get_buffer()
        if log_buf then
          log_buf:render()
        end
      end)
    end
  )
end

return M
