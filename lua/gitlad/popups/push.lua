---@mod gitlad.popups.push Push popup
---@brief [[
--- Transient-style push popup with switches, options, and actions.
--- Follows magit push popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class PushPopupContext
---@field repo_state RepoState
---@field popup PopupData

--- Extract remote name from ref (e.g., "origin/main" -> "origin")
---@param ref string|nil
---@return string|nil
local function get_remote_from_ref(ref)
  if not ref then
    return nil
  end
  return ref:match("^([^/]+)/")
end

--- Get the effective push target for the current branch
--- This returns the same push_remote that the status view displays
---@param status GitStatusResult|nil
---@return string|nil push_ref Full ref like "origin/feature-branch"
---@return string|nil remote Remote name like "origin"
local function get_push_target(status)
  if not status then
    return nil, nil
  end

  -- Use explicitly calculated push_remote if available
  if status.push_remote then
    local remote = get_remote_from_ref(status.push_remote)
    return status.push_remote, remote
  end

  -- Fall back to computing it the same way state/init.lua does
  -- Push goes to <remote>/<branch> where remote is derived from upstream
  if status.upstream then
    local remote = get_remote_from_ref(status.upstream)
    if remote then
      return remote .. "/" .. status.branch, remote
    end
  end

  return nil, nil
end

--- Check if push can proceed (has push target or remote specified)
---@param repo_state RepoState
---@param remote string|nil Remote option value
---@return boolean can_push
---@return string|nil error_message
local function can_push(repo_state, remote)
  local status = repo_state.status
  if not status then
    return false, "Status not loaded"
  end

  -- If remote is specified, we can push
  if remote and remote ~= "" then
    return true, nil
  end

  -- Check if we have a push target (either explicit or derived from upstream)
  local push_ref, _ = get_push_target(status)
  if not push_ref then
    return false, "No push target. Set a remote with =r or use 'e' to push elsewhere."
  end

  return true, nil
end

--- Build push arguments from popup state
---@param popup_data PopupData
---@param remote string|nil Override remote
---@param refspec string|nil Override refspec
---@return string[]
local function build_push_args(popup_data, remote, refspec)
  local args = popup_data:get_arguments()

  -- Filter out --remote= and --refspec= since they are positional arguments, not options
  args = vim.tbl_filter(function(arg)
    return not vim.startswith(arg, "--remote=") and not vim.startswith(arg, "--refspec=")
  end, args)

  if remote and remote ~= "" then
    table.insert(args, remote)
    if refspec and refspec ~= "" then
      table.insert(args, refspec)
    end
  end

  return args
end

--- Execute push operation
---@param repo_state RepoState
---@param args string[]
local function do_push(repo_state, args)
  vim.notify("[gitlad] Pushing...", vim.log.levels.INFO)

  git.push(args, { cwd = repo_state.repo_root }, function(success, _, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Push complete", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Push failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Create and show the push popup
---@param repo_state RepoState
function M.open(repo_state)
  local status = repo_state.status
  local _, default_remote = get_push_target(status)
  default_remote = default_remote or ""

  local push_popup = popup
    .builder()
    :name("Push")
    -- Switches
    :switch("f", "force-with-lease", "Force with lease (safer)")
    :switch("F", "force", "Force (dangerous)")
    :switch("n", "dry-run", "Dry run")
    :switch("t", "tags", "Include tags")
    :switch("u", "set-upstream", "Set upstream")
    -- Options
    :option("r", "remote", default_remote, "Remote")
    :option("b", "refspec", "", "Refspec")
    -- Actions
    :group_heading("Push")
    :action("p", "Push to upstream", function(popup_data)
      M._push_upstream(repo_state, popup_data)
    end)
    :action("e", "Push elsewhere", function(popup_data)
      M._push_elsewhere(repo_state, popup_data)
    end)
    :build()

  push_popup:show()
end

--- Check if remote branch exists
--- Uses the status data which already tracks whether push_commit_msg was fetched
---@param status GitStatusResult|nil
---@return boolean
local function remote_branch_exists(status)
  if not status then
    return false
  end
  -- If push_remote is set and push_commit_msg exists, the remote branch exists
  -- state/init.lua only sets push_commit_msg if the remote branch was found
  return status.push_remote ~= nil and status.push_commit_msg ~= nil
end

--- Push to push target (same-name branch on remote)
--- Unlike git's default behavior which can be confused by mismatched upstream,
--- we explicitly push to <remote>/<branch> like magit does
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_upstream(repo_state, popup_data)
  local status = repo_state.status

  -- Get remote from option, or from push target
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  -- Get refspec if explicitly set
  local refspec = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "refspec" and opt.value ~= "" then
      refspec = opt.value
      break
    end
  end

  -- Validate
  local ok, err = can_push(repo_state, remote)
  if not ok then
    vim.notify("[gitlad] " .. err, vim.log.levels.WARN)
    return
  end

  -- For "push to upstream", always derive the push target unless user explicitly set refspec
  -- This ensures we push to <remote>/<branch> even when upstream differs
  -- The remote option may be pre-filled but we still need to derive the refspec
  local push_ref = nil
  if (not refspec or refspec == "") and status then
    local push_remote
    push_ref, push_remote = get_push_target(status)
    if push_ref and push_remote then
      -- Use derived remote if not explicitly set, otherwise use user's choice
      if not remote or remote == "" then
        remote = push_remote
      end
      -- Always set refspec to current branch for "push to upstream"
      refspec = status.branch
    end
  end

  -- Check if remote branch exists
  -- If not, prompt user to create it
  if push_ref and not remote_branch_exists(status) then
    local prompt = string.format("Create remote branch '%s'?", push_ref)
    vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
      if choice ~= "Yes" then
        return
      end

      -- Only add -u flag if no upstream is already configured
      -- This preserves triangular workflow where upstream might be e.g. origin/main
      local current_branch = status and status.branch
      if not current_branch then
        local args = build_push_args(popup_data, remote, refspec)
        do_push(repo_state, args)
        return
      end

      git.get_upstream(current_branch, { cwd = repo_state.repo_root }, function(upstream, _)
        vim.schedule(function()
          local args = build_push_args(popup_data, remote, refspec)

          -- Only set upstream if one isn't already configured
          if not upstream then
            -- Ensure -u is in args if not already
            local has_set_upstream = false
            for _, arg in ipairs(args) do
              if arg == "--set-upstream" or arg == "-u" then
                has_set_upstream = true
                break
              end
            end
            if not has_set_upstream then
              table.insert(args, 1, "-u")
            end
          end

          do_push(repo_state, args)
        end)
      end)
    end)
    return
  end

  local args = build_push_args(popup_data, remote, refspec)
  do_push(repo_state, args)
end

--- Push elsewhere (prompts for remote if not set)
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_elsewhere(repo_state, popup_data)
  -- Check if remote is already set
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  -- Get refspec if set
  local refspec = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "refspec" and opt.value ~= "" then
      refspec = opt.value
      break
    end
  end

  if remote and remote ~= "" then
    -- Remote already set, push directly
    local args = build_push_args(popup_data, remote, refspec)
    do_push(repo_state, args)
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
        prompt = "Select remote to push to:",
      }, function(choice)
        if not choice then
          return
        end

        local args = build_push_args(popup_data, choice, refspec)
        do_push(repo_state, args)
      end)
    end)
  end)
end

return M
