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

--- Extract remote name from upstream (e.g., "origin/main" -> "origin")
---@param upstream string|nil
---@return string|nil
local function get_remote_from_upstream(upstream)
  if not upstream then
    return nil
  end
  return upstream:match("^([^/]+)/")
end

--- Check if push can proceed (has upstream or remote specified)
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

  -- Otherwise we need an upstream
  if not status.upstream then
    return false, "No upstream configured. Set a remote with =r or use 'e' to push elsewhere."
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
  local default_remote = status and get_remote_from_upstream(status.upstream) or ""

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

--- Push to upstream
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_upstream(repo_state, popup_data)
  -- Get remote from option, or default from upstream
  local remote = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "remote" and opt.value ~= "" then
      remote = opt.value
      break
    end
  end

  -- Validate
  local ok, err = can_push(repo_state, remote)
  if not ok then
    vim.notify("[gitlad] " .. err, vim.log.levels.WARN)
    return
  end

  -- Get refspec if set
  local refspec = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "refspec" and opt.value ~= "" then
      refspec = opt.value
      break
    end
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
