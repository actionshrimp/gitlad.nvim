---@mod gitlad.popups.pull Pull popup
---@brief [[
--- Transient-style pull popup with switches, options, and actions.
--- Follows magit pull popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class PullPopupContext
---@field repo_state RepoState
---@field popup PopupData

--- Extract remote name from upstream (e.g., "origin/main" -> "origin")
---@param upstream string|nil
---@return string|nil
local function get_remote_from_upstream(upstream)
  if not upstream then
    return nil
  end
  return upstream:match("^([^/]+)/")
end

--- Check if pull can proceed (has upstream or remote specified)
---@param repo_state RepoState
---@param remote string|nil Remote option value
---@return boolean can_pull
---@return string|nil error_message
local function can_pull(repo_state, remote)
  local status = repo_state.status
  if not status then
    return false, "Status not loaded"
  end

  -- If remote is specified, we can pull
  if remote and remote ~= "" then
    return true, nil
  end

  -- Otherwise we need an upstream
  if not status.upstream then
    return false, "No upstream configured. Set a remote with =r or use 'e' to pull elsewhere."
  end

  return true, nil
end

--- Build pull arguments from popup state
---@param popup_data PopupData
---@param remote string|nil Override remote
---@return string[]
local function build_pull_args(popup_data, remote)
  local args = popup_data:get_arguments()

  -- Filter out --remote= since remote is a positional argument, not an option
  args = vim.tbl_filter(function(arg)
    return not vim.startswith(arg, "--remote=")
  end, args)

  if remote and remote ~= "" then
    table.insert(args, remote)
  end

  return args
end

--- Execute pull operation
---@param repo_state RepoState
---@param args string[]
local function do_pull(repo_state, args)
  vim.notify("[gitlad] Pulling...", vim.log.levels.INFO)

  git.pull(args, { cwd = repo_state.repo_root }, function(success, _, err)
    vim.schedule(function()
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
  local status = repo_state.status
  local default_remote = status and get_remote_from_upstream(status.upstream) or ""

  local pull_popup = popup
    .builder()
    :name("Pull")
    -- Switches
    :switch("r", "rebase", "Rebase instead of merge")
    :switch("f", "ff-only", "Fast-forward only")
    :switch("n", "no-ff", "Create merge commit")
    :switch("a", "autostash", "Autostash before pull")
    -- Options
    :option("o", "remote", default_remote, "Remote")
    -- Actions
    :group_heading("Pull")
    :action("p", "Pull from upstream", function(popup_data)
      M._pull_upstream(repo_state, popup_data)
    end)
    :action("e", "Pull elsewhere", function(popup_data)
      M._pull_elsewhere(repo_state, popup_data)
    end)
    :build()

  pull_popup:show()
end

--- Pull from upstream
---@param repo_state RepoState
---@param popup_data PopupData
function M._pull_upstream(repo_state, popup_data)
  -- Get remote from option, or default from upstream
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  -- Validate
  local ok, err = can_pull(repo_state, remote)
  if not ok then
    vim.notify("[gitlad] " .. err, vim.log.levels.WARN)
    return
  end

  local args = build_pull_args(popup_data, remote)
  do_pull(repo_state, args)
end

--- Pull elsewhere (prompts for remote if not set)
---@param repo_state RepoState
---@param popup_data PopupData
function M._pull_elsewhere(repo_state, popup_data)
  -- Check if remote is already set
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  if remote and remote ~= "" then
    -- Remote already set, pull directly
    local args = build_pull_args(popup_data, remote)
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

        local args = build_pull_args(popup_data, choice)
        do_pull(repo_state, args)
      end)
    end)
  end)
end

return M
