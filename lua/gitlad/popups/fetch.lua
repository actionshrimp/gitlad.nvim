---@mod gitlad.popups.fetch Fetch popup
---@brief [[
--- Transient-style fetch popup with switches, options, and actions.
--- Follows magit fetch popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")
local remote_util = require("gitlad.utils.remote")

---@class FetchPopupContext
---@field repo_state RepoState
---@field popup PopupData

--- Build fetch arguments from popup state
---@param popup_data PopupData
---@param remote string|nil Override remote
---@return string[]
local function build_fetch_args(popup_data, remote)
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

--- Execute fetch operation
---@param repo_state RepoState
---@param args string[]
local function do_fetch(repo_state, args)
  vim.notify("[gitlad] Fetching...", vim.log.levels.INFO)

  git.fetch(args, { cwd = repo_state.repo_root }, function(success, _, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Fetch complete", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Fetch failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Create and show the fetch popup
---@param repo_state RepoState
function M.open(repo_state)
  local status = repo_state.status
  local default_remote = status and remote_util.get_remote_from_ref(status.upstream) or ""

  local fetch_popup = popup
    .builder()
    :name("Fetch")
    -- Switches
    :switch("P", "prune", "Prune deleted branches")
    :switch("t", "tags", "Fetch all tags")
    -- Options
    :option("r", "remote", default_remote, "Remote")
    -- Actions
    :group_heading("Fetch")
    :action("p", "Fetch from pushremote", function(popup_data)
      M._fetch_pushremote(repo_state, popup_data)
    end)
    :action("u", "Fetch from upstream", function(popup_data)
      M._fetch_upstream(repo_state, popup_data)
    end)
    :action("e", "Fetch elsewhere", function(popup_data)
      M._fetch_elsewhere(repo_state, popup_data)
    end)
    :action("a", "Fetch all remotes", function(popup_data)
      M._fetch_all(repo_state, popup_data)
    end)
    :build()

  fetch_popup:show()
end

--- Fetch from pushremote (the remote used for pushing, may differ from upstream)
---@param repo_state RepoState
---@param popup_data PopupData
function M._fetch_pushremote(repo_state, popup_data)
  local status = repo_state.status
  local remote = remote_util.get_push_remote(status)

  if not remote or remote == "" then
    vim.notify(
      "[gitlad] No push remote configured. Set a remote with =r or use 'e' to fetch elsewhere.",
      vim.log.levels.WARN
    )
    return
  end

  local args = build_fetch_args(popup_data, remote)
  do_fetch(repo_state, args)
end

--- Fetch from upstream (the remote used for pulling/merging)
---@param repo_state RepoState
---@param popup_data PopupData
function M._fetch_upstream(repo_state, popup_data)
  local status = repo_state.status
  local branch = status and status.branch or nil

  -- Check if upstream is a local branch (remote = ".")
  if branch then
    local git_module = require("gitlad.git")
    local upstream_remote =
      git_module.config_get("branch." .. branch .. ".remote", { cwd = repo_state.repo_root })
    if upstream_remote == "." then
      vim.notify("[gitlad] Upstream is a local branch — nothing to fetch", vim.log.levels.INFO)
      return
    end
  end

  local remote = status and remote_util.get_remote_from_ref(status.upstream) or nil

  -- Validate
  if not remote or remote == "" then
    vim.notify(
      "[gitlad] No upstream configured. Set a remote with =r or use 'e' to fetch elsewhere.",
      vim.log.levels.WARN
    )
    return
  end

  local args = build_fetch_args(popup_data, remote)
  do_fetch(repo_state, args)
end

--- Fetch elsewhere (prompts for remote if not set)
---@param repo_state RepoState
---@param popup_data PopupData
function M._fetch_elsewhere(repo_state, popup_data)
  -- Check if remote is already set
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  if remote and remote ~= "" then
    -- Remote already set, fetch directly
    local args = build_fetch_args(popup_data, remote)
    do_fetch(repo_state, args)
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
        prompt = "Select remote to fetch from:",
      }, function(choice)
        if not choice then
          return
        end

        local args = build_fetch_args(popup_data, choice)
        do_fetch(repo_state, args)
      end)
    end)
  end)
end

--- Fetch all remotes
---@param repo_state RepoState
---@param popup_data PopupData
function M._fetch_all(repo_state, popup_data)
  -- Build args with --all flag (no remote needed since we're fetching all)
  local args = popup_data:get_arguments()

  -- Filter out --remote= since we're fetching all remotes
  args = vim.tbl_filter(function(arg)
    return not vim.startswith(arg, "--remote=")
  end, args)

  table.insert(args, "--all")
  do_fetch(repo_state, args)
end

return M
