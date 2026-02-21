---@mod gitlad.popups.pull Pull popup
---@brief [[
--- Transient-style pull popup with switches, options, and actions.
--- Follows magit's triangular workflow:
--- - "upstream" = where you pull from (the mainline branch)
--- - "pushremote" = where you push to (your fork/feature branch)
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")
local remote_util = require("gitlad.utils.remote")

---@class PullPopupContext
---@field repo_state RepoState
---@field popup PopupData

--- Build pull arguments from popup state
---@param popup_data PopupData
---@param remote string|nil Override remote
---@param branch string|nil Override branch (for pull from pushremote)
---@return string[]
local function build_pull_args(popup_data, remote, branch)
  local args = popup_data:get_arguments()

  -- Filter out --remote= since remote is a positional argument, not an option
  args = vim.tbl_filter(function(arg)
    return not vim.startswith(arg, "--remote=")
  end, args)

  if remote and remote ~= "" then
    table.insert(args, remote)
    if branch and branch ~= "" then
      table.insert(args, branch)
    end
  end

  return args
end

--- Execute pull operation
---@param repo_state RepoState
---@param args string[]
local function do_pull(repo_state, args)
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({ title = "Pull", command = "git pull " .. table.concat(args, " ") })

  vim.notify("[gitlad] Pulling...", vim.log.levels.INFO)

  git.pull(args, {
    cwd = repo_state.repo_root,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(success, _, err)
    vim.schedule(function()
      viewer:complete(success and 0 or 1)
      if success then
        vim.notify("[gitlad] Pull complete", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Pull failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Create and show the pull popup
---@param repo_state RepoState
function M.open(repo_state)
  local pull_popup = popup
    .builder()
    :name("Pull")
    -- Switches
    :switch("r", "rebase", "Rebase instead of merge")
    :switch("f", "ff-only", "Fast-forward only", { exclusive_with = { "no-ff" } })
    :switch("n", "no-ff", "Create merge commit", { exclusive_with = { "ff-only" } })
    :switch("a", "autostash", "Autostash before pull")
    -- Options (for "pull elsewhere" primarily)
    :option("o", "remote", "", "Remote")
    -- Actions
    :group_heading("Pull")
    :action("p", "Pull from pushremote", function(popup_data)
      M._pull_pushremote(repo_state, popup_data)
    end)
    :action("u", "Pull from upstream", function(popup_data)
      M._pull_upstream(repo_state, popup_data)
    end)
    :action("e", "Pull elsewhere", function(popup_data)
      M._pull_elsewhere(repo_state, popup_data)
    end)
    :build()

  pull_popup:show()
end

--- Pull from pushremote (the remote used for pushing, may differ from upstream)
--- In triangular workflow, this pulls from your fork/feature branch
--- Runs: git pull <pushremote> <current_branch>
---@param repo_state RepoState
---@param popup_data PopupData
function M._pull_pushremote(repo_state, popup_data)
  local status = repo_state.status
  local remote = remote_util.get_push_remote(status)

  if not remote or remote == "" then
    vim.notify(
      "[gitlad] No push remote configured. Use 'e' to pull elsewhere, or configure branch.<name>.pushRemote.",
      vim.log.levels.WARN
    )
    return
  end

  -- For pushremote, we need to specify both remote AND branch
  -- because pushremote may not have tracking configured
  local branch = status and status.branch or nil
  if not branch then
    vim.notify("[gitlad] Cannot determine current branch.", vim.log.levels.WARN)
    return
  end

  local args = build_pull_args(popup_data, remote, branch)
  do_pull(repo_state, args)
end

--- Pull from upstream (uses git's configured tracking branch)
--- This runs `git pull` with no remote/branch arguments, letting git
--- use the standard tracking branch configuration (branch.<name>.remote + branch.<name>.merge)
---@param repo_state RepoState
---@param popup_data PopupData
function M._pull_upstream(repo_state, popup_data)
  local status = repo_state.status

  -- Check if we have an upstream configured
  if not status or not status.upstream then
    vim.notify(
      "[gitlad] No upstream configured. Use 'e' to pull elsewhere, or set upstream with `git branch --set-upstream-to`.",
      vim.log.levels.WARN
    )
    return
  end

  -- Build args WITHOUT any remote - let git use the tracking configuration
  -- This ensures `git pull` works exactly as it would from the command line
  local args = build_pull_args(popup_data, nil, nil)
  do_pull(repo_state, args)
end

--- Pull elsewhere (prompts for remote if not set)
---@param repo_state RepoState
---@param popup_data PopupData
function M._pull_elsewhere(repo_state, popup_data)
  -- Check if remote is already set via the option
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  if remote and remote ~= "" then
    -- Remote already set, pull directly
    local args = build_pull_args(popup_data, remote, nil)
    do_pull(repo_state, args)
    return
  end

  -- Prompt for remote
  git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remotes: " .. err, vim.log.levels.ERROR)
        return
      end

      if not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.WARN)
        return
      end

      -- Build list of remote names
      local remote_names = {}
      for _, r in ipairs(remotes) do
        table.insert(remote_names, r.name)
      end

      vim.ui.select(remote_names, {
        prompt = "Select remote to pull from:",
      }, function(choice)
        if not choice then
          return
        end

        local args = build_pull_args(popup_data, choice, nil)
        do_pull(repo_state, args)
      end)
    end)
  end)
end

return M
