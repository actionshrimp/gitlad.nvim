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

return M
