---@mod gitlad.popups.push Push popup
---@brief [[
--- Transient-style push popup with switches, options, and actions.
--- Follows magit push popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")
local remote_util = require("gitlad.utils.remote")

---@class PushPopupContext
---@field repo_state RepoState
---@field popup PopupData

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
  local push_ref, _ = remote_util.get_push_target(status)
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
---@param context? { commit?: string } Optional context (commit at point)
function M.open(repo_state, context)
  local ctx = context or {}
  local status = repo_state.status
  local branch = status and status.branch or nil

  -- Build dynamic description for "Push <branch> to" section heading
  local push_heading = "Push"
  if branch then
    push_heading = "Push " .. branch .. " to"
  end

  -- Build dynamic labels for push targets (like magit)
  -- When configured: show the actual ref (e.g., "origin/feature-branch")
  -- When not configured: show explanatory text
  local pushremote_label = "pushRemote, setting that"
  local upstream_label = "@{upstream}, setting it"

  if status then
    -- Get the effective push target (handles fallback from push_remote to upstream-derived)
    local push_ref, _ = remote_util.get_push_target(status)
    if push_ref then
      pushremote_label = push_ref
    end

    -- Check if upstream is configured
    if status.upstream then
      upstream_label = status.upstream
    end
  end

  local push_popup = popup
    .builder()
    :name("Push")
    -- Switches
    :switch("f", "force-with-lease", "Force with lease (safer)")
    :switch("F", "force", "Force (dangerous)")
    :switch("n", "dry-run", "Dry run")
    :switch("t", "tags", "Include tags")
    -- Options
    :option("r", "remote", "", "Remote")
    :option("b", "refspec", "", "Refspec")
    -- Actions - magit style
    :group_heading(push_heading)
    :action("p", pushremote_label, function(popup_data)
      M._push_to_pushremote(repo_state, popup_data)
    end)
    :action("u", upstream_label, function(popup_data)
      M._push_to_upstream(repo_state, popup_data)
    end)
    :action("e", "elsewhere", function(popup_data)
      M._push_elsewhere(repo_state, popup_data)
    end)
    -- Push section (like magit's second section)
    :group_heading("Push")
    :action("o", "another branch", function(popup_data)
      M._push_another_branch(repo_state, popup_data, ctx)
    end)
    :action("T", "a tag", function(popup_data)
      M._push_tag(repo_state, popup_data)
    end)
    :action("t", "all tags", function(popup_data)
      M._push_all_tags(repo_state, popup_data)
    end)
    :build()

  push_popup:show()
end

--- Check if remote branch exists
--- Uses the status data which already tracks whether push_commit_msg was fetched
---@param status GitStatusResult|nil
---@param push_ref string|nil The push target ref to check
---@return boolean
local function remote_branch_exists(status, push_ref)
  if not status then
    return false
  end
  -- If push_remote is set and push_commit_msg exists, the remote branch exists
  -- state/init.lua only sets push_commit_msg if the remote branch was found
  if status.push_remote ~= nil and status.push_commit_msg ~= nil then
    return true
  end

  -- If the push target is the same as upstream, the branch exists
  -- (because upstream tracking implies the remote branch exists)
  -- This handles the case where push_remote is not explicitly set but the branch
  -- is being tracked via upstream (e.g., origin/feature-branch as both upstream and push target)
  if push_ref and status.upstream and push_ref == status.upstream then
    return true
  end

  return false
end

--- Push to pushRemote, setting it if not configured
--- Like magit's "p" action: pushes to pushRemote (or remote.pushDefault) and sets it if needed
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_to_pushremote(repo_state, popup_data)
  local status = repo_state.status
  if not status or not status.branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  local branch = status.branch
  local opts = { cwd = repo_state.repo_root }

  -- Get the effective push remote (explicit pushRemote or fallback to pushDefault)
  git.get_push_remote(branch, opts, function(push_remote_name, err)
    vim.schedule(function()
      if push_remote_name and push_remote_name ~= "" then
        -- Push remote is configured, push to it
        M._do_push_to_remote(repo_state, popup_data, push_remote_name, branch, false)
      else
        -- No push remote configured, prompt user to select one
        git.remote_names(opts, function(remotes, rem_err)
          vim.schedule(function()
            if rem_err or not remotes or #remotes == 0 then
              vim.notify("[gitlad] No remotes configured", vim.log.levels.WARN)
              return
            end

            local prompt = "Set branch." .. branch .. ".pushRemote and push there"
            vim.ui.select(remotes, { prompt = prompt .. ":" }, function(choice)
              if not choice then
                return
              end

              -- Set the pushRemote config
              git.set_push_remote(branch, choice, opts, function(success, set_err)
                vim.schedule(function()
                  if success then
                    -- Now push to that remote
                    M._do_push_to_remote(repo_state, popup_data, choice, branch, true)
                  else
                    vim.notify(
                      "[gitlad] Failed to set pushRemote: " .. (set_err or "unknown"),
                      vim.log.levels.ERROR
                    )
                  end
                end)
              end)
            end)
          end)
        end)
      end
    end)
  end)
end

--- Helper to execute push to a specific remote
---@param repo_state RepoState
---@param popup_data PopupData
---@param remote string Remote name
---@param branch string Branch name
---@param is_new_config boolean Whether we just set the pushRemote config (affects -u behavior)
function M._do_push_to_remote(repo_state, popup_data, remote, branch, is_new_config)
  local status = repo_state.status
  local opts = { cwd = repo_state.repo_root }

  -- Check if we need to add -u flag (when no upstream is configured)
  git.get_upstream(branch, opts, function(upstream, _)
    vim.schedule(function()
      local args = build_push_args(popup_data, remote, branch)

      -- If creating a new branch or no upstream configured, add -u
      local push_ref = remote .. "/" .. branch
      local needs_upstream = not upstream

      -- Check if remote branch exists
      if not remote_branch_exists(status, push_ref) then
        -- Creating new remote branch
        local prompt = string.format("Create remote branch '%s'?", push_ref)
        vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
          if choice ~= "Yes" then
            return
          end

          if needs_upstream then
            -- Add -u if not already present
            local has_u = vim.tbl_contains(args, "-u") or vim.tbl_contains(args, "--set-upstream")
            if not has_u then
              table.insert(args, 1, "-u")
            end
          end

          do_push(repo_state, args)
        end)
      else
        -- Remote branch exists, just push
        do_push(repo_state, args)
      end
    end)
  end)
end

--- Push to @{upstream}, creating it if needed
--- Like magit's "u" action: pushes to the configured upstream tracking branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_to_upstream(repo_state, popup_data)
  local status = repo_state.status
  if not status or not status.branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  local branch = status.branch
  local opts = { cwd = repo_state.repo_root }

  -- Get upstream configuration
  local upstream_remote = git.config_get("branch." .. branch .. ".remote", opts)
  local upstream_merge = git.config_get("branch." .. branch .. ".merge", opts)

  if not upstream_remote or not upstream_merge or upstream_remote == "" or upstream_merge == "" then
    -- Upstream not configured, prompt user to set it
    M._configure_and_push_upstream(repo_state, popup_data, branch)
    return
  end

  -- Extract branch name from merge ref (refs/heads/main -> main)
  local upstream_branch = upstream_merge:gsub("^refs/heads/", "")

  -- For local upstream (remote = "."), the ref is just the branch name, not "./branch"
  local upstream_ref
  if upstream_remote == "." then
    upstream_ref = upstream_branch
  else
    upstream_ref = upstream_remote .. "/" .. upstream_branch
  end

  -- Build refspec: local_branch:remote_branch
  local refspec = branch .. ":" .. upstream_merge

  -- For local upstream, the branch always exists if upstream is configured
  if upstream_remote == "." then
    local args = build_push_args(popup_data, upstream_remote, refspec)
    do_push(repo_state, args)
    return
  end

  -- Check if remote branch exists
  if not remote_branch_exists(status, upstream_ref) then
    local prompt = string.format("Create upstream branch '%s'?", upstream_ref)
    vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
      if choice ~= "Yes" then
        return
      end

      local args = build_push_args(popup_data, upstream_remote, refspec)
      -- Add --set-upstream since we're creating the tracking relationship
      if not vim.tbl_contains(args, "-u") and not vim.tbl_contains(args, "--set-upstream") then
        table.insert(args, 1, "--set-upstream")
      end
      do_push(repo_state, args)
    end)
    return
  end

  -- Push to existing upstream
  local args = build_push_args(popup_data, upstream_remote, refspec)
  do_push(repo_state, args)
end

--- Configure upstream and push (when upstream is not set)
---@param repo_state RepoState
---@param popup_data PopupData
---@param branch string Current branch name
function M._configure_and_push_upstream(repo_state, popup_data, branch)
  local opts = { cwd = repo_state.repo_root }

  -- Use the prompt module for ref completion
  local prompt_module = require("gitlad.utils.prompt")
  prompt_module.prompt_for_ref({
    prompt = "Set upstream of " .. branch .. " and push there: ",
    cwd = repo_state.repo_root,
  }, function(upstream)
    if not upstream or upstream == "" then
      return
    end

    -- Parse upstream into remote and branch
    -- "origin/main" → remote="origin", branch="main"
    -- "main" (no slash) → remote=".", branch="main" (local upstream)
    -- "feature/foo" (local branch with slash) → remote=".", branch="feature/foo"
    local remote_part, branch_part = upstream:match("^([^/]+)/(.+)$")
    if not remote_part then
      -- No slash: treat as local branch name (remote = ".")
      remote_part = "."
      branch_part = upstream
    else
      -- Has a slash: check if the first component is a known remote
      local remotes = git.remote_names_sync(opts)
      local is_remote = false
      for _, r in ipairs(remotes) do
        if r == remote_part then
          is_remote = true
          break
        end
      end
      if not is_remote then
        -- Not a remote: treat as local branch name (e.g., "feature/foo")
        remote_part = "."
        branch_part = upstream
      end
    end

    -- Set upstream using git branch --set-upstream-to
    git.set_upstream(branch, upstream, opts, function(success, err)
      vim.schedule(function()
        if not success then
          vim.notify(
            "[gitlad] Failed to set upstream: " .. (err or "unknown"),
            vim.log.levels.ERROR
          )
          return
        end

        -- Now push to the newly configured upstream
        local refspec = branch .. ":refs/heads/" .. branch_part
        local args = build_push_args(popup_data, remote_part, refspec)
        do_push(repo_state, args)
      end)
    end)
  end)
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

--- Push another branch or commit to a remote branch
--- Two-stage selector: first pick source (branch/commit), then pick target (remote/branch)
---@param repo_state RepoState
---@param popup_data PopupData
---@param context { commit?: string } Optional context with commit at point
function M._push_another_branch(repo_state, popup_data, context)
  local prompt_module = require("gitlad.utils.prompt")

  -- Stage 1: Select source (pre-fill from context if available)
  prompt_module.prompt_for_ref({
    prompt = "Push: ",
    cwd = repo_state.repo_root,
    default = context.commit or "",
  }, function(source)
    if not source or source == "" then
      return
    end

    -- Stage 2: Select target (remote/branch)
    prompt_module.prompt_for_ref({
      prompt = "Push " .. source .. " to: ",
      cwd = repo_state.repo_root,
    }, function(target)
      if not target or target == "" then
        return
      end

      -- Parse target: "origin/feature" → remote="origin", branch="feature"
      -- "main" (no slash) → remote=".", branch="main" (local push)
      -- "feature/foo" (local branch with slash) → remote=".", branch="feature/foo"
      local push_opts = { cwd = repo_state.repo_root }
      local remote, branch_name = target:match("^([^/]+)/(.+)$")
      if not remote then
        -- No slash: treat as local branch name (remote = ".")
        remote = "."
        branch_name = target
      else
        -- Has a slash: check if the first component is a known remote
        local remotes = git.remote_names_sync(push_opts)
        local is_remote = false
        for _, r in ipairs(remotes) do
          if r == remote then
            is_remote = true
            break
          end
        end
        if not is_remote then
          -- Not a remote: treat as local branch name (e.g., "feature/foo")
          remote = "."
          branch_name = target
        end
      end

      -- Build args and push: git push <remote> <source>:<branch>
      local args = build_push_args(popup_data, remote, source .. ":" .. branch_name)
      do_push(repo_state, args)
    end)
  end)
end

--- Push a single tag to a remote
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_tag(repo_state, popup_data)
  -- Get list of tags
  local tags_output =
    vim.fn.systemlist("git -C " .. vim.fn.shellescape(repo_state.repo_root) .. " tag")
  if vim.v.shell_error ~= 0 or not tags_output or #tags_output == 0 then
    vim.notify("[gitlad] No tags found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(tags_output, { prompt = "Push tag:" }, function(tag)
    if not tag then
      return
    end

    git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
      vim.schedule(function()
        if err or not remotes or #remotes == 0 then
          vim.notify("[gitlad] No remotes configured", vim.log.levels.WARN)
          return
        end

        local remote_names = vim.tbl_map(function(r)
          return r.name
        end, remotes)
        vim.ui.select(remote_names, { prompt = "Push " .. tag .. " to:" }, function(remote)
          if not remote then
            return
          end
          local args = build_push_args(popup_data, remote, tag)
          do_push(repo_state, args)
        end)
      end)
    end)
  end)
end

--- Push all tags to a remote
---@param repo_state RepoState
---@param popup_data PopupData
function M._push_all_tags(repo_state, popup_data)
  git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err or not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.WARN)
        return
      end

      local remote_names = vim.tbl_map(function(r)
        return r.name
      end, remotes)
      vim.ui.select(remote_names, { prompt = "Push all tags to:" }, function(remote)
        if not remote then
          return
        end
        local args = build_push_args(popup_data, remote, nil)
        table.insert(args, "--tags")
        do_push(repo_state, args)
      end)
    end)
  end)
end

return M
