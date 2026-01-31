---@mod gitlad.popups.branch Branch popup
---@brief [[
--- Transient-style branch popup with switches, options, and actions.
--- Follows magit branch popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class BranchPopupContext
---@field repo_state RepoState
---@field popup PopupData

---@class BranchContext
---@field ref? string Pre-selected ref name for checkout
---@field ref_type? "local"|"remote"|"tag" Type of the ref (for smart checkout behavior)

--- Get the current branch name from repo state
---@param repo_state RepoState
---@return string|nil
local function get_current_branch(repo_state)
  local status = repo_state.status
  if not status then
    return nil
  end
  return status.branch
end

--- Filter branches to exclude the current branch
---@param branches table[] Array of branch info
---@param current_branch string|nil Current branch name
---@return string[] Array of branch names (excluding current)
local function get_other_branch_names(branches, current_branch)
  local names = {}
  for _, branch in ipairs(branches) do
    if branch.name ~= current_branch and branch.name ~= "HEAD (detached)" then
      table.insert(names, branch.name)
    end
  end
  return names
end

--- Get all branch names for display
---@param branches table[] Array of branch info
---@return string[] Array of branch names
local function get_all_branch_names(branches)
  local names = {}
  for _, branch in ipairs(branches) do
    if branch.name ~= "HEAD (detached)" then
      table.insert(names, branch.name)
    end
  end
  return names
end

--- Extract local branch name from a remote ref name
--- e.g., "origin/feature" -> "feature", "upstream/fix/bug" -> "fix/bug"
---@param remote_ref string The remote ref name (e.g., "origin/feature")
---@return string|nil local_name The local branch name, or nil if not a remote ref
---@return string|nil remote The remote name, or nil if not a remote ref
local function extract_local_name_from_remote(remote_ref)
  -- Match pattern: remote/branch where remote doesn't contain /
  -- but branch can contain /
  local remote, branch = remote_ref:match("^([^/]+)/(.+)$")
  if remote and branch then
    return branch, remote
  end
  return nil, nil
end

--- Check if a local branch exists in the branch list
---@param branches table[] Array of branch info from git.branches()
---@param branch_name string Branch name to check
---@return boolean exists True if the local branch exists
local function local_branch_exists(branches, branch_name)
  for _, branch in ipairs(branches) do
    if branch.name == branch_name then
      return true
    end
  end
  return false
end

--- Parse upstream input like "origin/main" into separate remote and merge values
--- If input is "origin/main", returns { remote = "origin", merge = "refs/heads/main" }
--- If input is just "main" (local branch), returns { remote = ".", merge = "refs/heads/main" }
--- The "." remote means "local repository" in git
---@param input string User input for upstream
---@param branch string Current branch name
---@return table<string, string> Config key-value pairs to set
local function parse_upstream_input(input, branch)
  if not input or input == "" then
    return {}
  end

  local result = {}
  local remote_key = "branch." .. branch .. ".remote"
  local merge_key = "branch." .. branch .. ".merge"

  -- Check if input contains a slash (could be remote/branch)
  local remote_part, branch_part = input:match("^([^/]+)/(.+)$")

  if remote_part and branch_part then
    -- Input is like "origin/main" or "upstream/feature/fix"
    result[remote_key] = remote_part
    result[merge_key] = "refs/heads/" .. branch_part
  else
    -- Input is just a branch name like "main" (local branch)
    -- Use "." as the remote to indicate local repository
    result[remote_key] = "."
    result[merge_key] = "refs/heads/" .. input
  end

  return result
end

--- Create and show the branch popup
---@param repo_state RepoState
---@param context? BranchContext Optional context with pre-selected ref
function M.open(repo_state, context)
  context = context or {}

  local current_branch = get_current_branch(repo_state)

  local builder = popup.builder()
    :name("Branch")
    :repo_root(repo_state.repo_root)
    :on_config_change(function(config_key, _value)
      -- Refresh status when upstream or push config changes
      -- These affect the Push/Pull lines in the status view
      if
        config_key:match("^branch%..*%.merge$")
        or config_key:match("^branch%..*%.remote$")
        or config_key:match("^branch%..*%.pushRemote$")
        or config_key:match("^remote%.pushDefault$")
      then
        repo_state:refresh_status(true)
      end
    end)

  -- Only show branch-specific config if we have a current branch
  if current_branch then
    builder
      :branch_scope(current_branch)
      -- Configure <branch> section
      :config_heading("Configure %s")
      :config_var("d", "branch.%s.description", "branch.%s.description", { type = "text" })
      :config_var("u", "branch.%s.merge", "branch.%s.merge", {
        type = "ref",
        on_set = function(value, popup_data)
          -- Auto-parse "origin/main" into remote=origin and merge=refs/heads/main
          return parse_upstream_input(value, popup_data.branch_scope)
        end,
        on_unset = function(popup_data)
          -- Unset both merge and remote when clearing upstream
          -- Use empty string "" to indicate unset (nil removes key from table in Lua)
          local branch = popup_data.branch_scope
          return {
            ["branch." .. branch .. ".merge"] = "",
            ["branch." .. branch .. ".remote"] = "",
          }
        end,
      })
      :config_display("branch.%s.remote", "branch.%s.remote") -- Read-only, set via merge
      :config_var("r", "branch.%s.rebase", "branch.%s.rebase", {
        type = "cycle",
        choices = { "true", "false", "" },
        default_display = "default:false",
      })
      :config_var("p", "branch.%s.pushRemote", "branch.%s.pushRemote", {
        type = "remote_cycle",
        fallback = "remote.pushDefault",
      })
  end

  -- Configure repository defaults section
  builder
    :config_heading("Configure repository defaults")
    :config_var("R", "pull.rebase", "pull.rebase", {
      type = "cycle",
      choices = { "true", "false", "" },
      default_display = "default:false",
    })
    :config_var("P", "remote.pushDefault", "remote.pushDefault", { type = "remote_cycle" })

  -- Switches (for delete operation)
  builder:switch("f", "force", "Force delete (even if not merged)")

  -- Actions in multi-column layout
  builder
    :columns(4)
    -- Checkout group
    :group_heading("Checkout")
    :action("b", "branch/revision", function(popup_data)
      M._checkout_branch(repo_state, popup_data, context.ref, context.ref_type)
    end)
    :action("l", "local branch", function(popup_data)
      M._checkout_local_branch(repo_state, popup_data)
    end)
    -- Create group (middle)
    :group_heading("")
    :action("c", "new branch", function(popup_data)
      M._create_and_checkout(repo_state, popup_data)
    end)
    :action("s", "new spin-off", function(popup_data)
      M._spinoff(repo_state, popup_data)
    end)
    -- Create group
    :group_heading("Create")
    :action("n", "new branch", function(popup_data)
      M._create_branch(repo_state, popup_data)
    end)
    -- Do group
    :group_heading("Do")
    :action("m", "rename", function(popup_data)
      M._rename_branch(repo_state, popup_data)
    end)
    :action("x", "delete", function(popup_data)
      M._delete_branch(repo_state, popup_data)
    end)

  local branch_popup = builder:build()
  branch_popup:show()
end

--- Checkout a local branch only (no remote branches)
---@param repo_state RepoState
---@param popup_data PopupData
function M._checkout_local_branch(repo_state, popup_data)
  local current_branch = get_current_branch(repo_state)

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

      -- Get branches excluding current
      local branch_names = get_other_branch_names(branches, current_branch)

      if #branch_names == 0 then
        vim.notify("[gitlad] No other local branches to checkout", vim.log.levels.INFO)
        return
      end

      vim.ui.select(branch_names, {
        prompt = "Checkout local branch:",
      }, function(choice)
        if not choice then
          return
        end

        local args = popup_data:get_arguments()
        git.checkout(choice, args, { cwd = repo_state.repo_root }, function(success, checkout_err)
          vim.schedule(function()
            if success then
              vim.notify("[gitlad] Switched to branch '" .. choice .. "'", vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Checkout failed: " .. (checkout_err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end)
      end)
    end)
  end)
end

--- Checkout an existing branch
--- When checking out a remote branch (e.g., "origin/feature"), this follows magit's smart behavior:
--- - If local branch "feature" exists: checkout the local branch
--- - If local branch doesn't exist: create "feature" from "origin/feature" with upstream tracking
---@param repo_state RepoState
---@param popup_data PopupData
---@param preselected_ref? string Pre-selected ref to checkout directly
---@param ref_type? "local"|"remote"|"tag" Type of the ref for smart behavior
function M._checkout_branch(repo_state, popup_data, preselected_ref, ref_type)
  local current_branch = get_current_branch(repo_state)

  -- Helper to perform simple checkout
  local function do_checkout(choice)
    local args = popup_data:get_arguments()
    git.checkout(choice, args, { cwd = repo_state.repo_root }, function(success, checkout_err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Switched to branch '" .. choice .. "'", vim.log.levels.INFO)
          repo_state:refresh_status(true)
          -- Also refresh refs buffer if it's open
          local refs_view = require("gitlad.ui.views.refs")
          local refs_buf = refs_view.get_buffer()
          if refs_buf then
            refs_buf:refresh()
          end
        else
          vim.notify(
            "[gitlad] Checkout failed: " .. (checkout_err or "unknown error"),
            vim.log.levels.ERROR
          )
        end
      end)
    end)
  end

  -- Helper to create and checkout a new local branch from a remote branch (with tracking)
  local function do_create_and_checkout_from_remote(local_name, remote_ref)
    local args = popup_data:get_arguments()
    -- git checkout -b <local> <remote> automatically sets up tracking
    git.checkout_new_branch(
      local_name,
      remote_ref,
      args,
      { cwd = repo_state.repo_root },
      function(success, checkout_err)
        vim.schedule(function()
          if success then
            vim.notify(
              "[gitlad] Created and switched to branch '"
                .. local_name
                .. "' tracking '"
                .. remote_ref
                .. "'",
              vim.log.levels.INFO
            )
            repo_state:refresh_status(true)
            -- Also refresh refs buffer if it's open
            local refs_view = require("gitlad.ui.views.refs")
            local refs_buf = refs_view.get_buffer()
            if refs_buf then
              refs_buf:refresh()
            end
          else
            vim.notify(
              "[gitlad] Create and checkout failed: " .. (checkout_err or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end
    )
  end

  -- Handle preselected ref (from refs view context)
  if preselected_ref then
    -- Check if it's a remote branch
    if ref_type == "remote" then
      local local_name, _ = extract_local_name_from_remote(preselected_ref)
      if local_name then
        -- Check if already on the corresponding local branch
        if local_name == current_branch then
          vim.notify("[gitlad] Already on '" .. local_name .. "'", vim.log.levels.INFO)
          return
        end

        -- Fetch local branches to check if the local branch exists
        git.branches({ cwd = repo_state.repo_root }, function(branches, err)
          vim.schedule(function()
            if err then
              vim.notify("[gitlad] Failed to get branches: " .. err, vim.log.levels.ERROR)
              return
            end

            if local_branch_exists(branches or {}, local_name) then
              -- Local branch exists, just checkout it
              do_checkout(local_name)
            else
              -- Local branch doesn't exist, create from remote with tracking
              do_create_and_checkout_from_remote(local_name, preselected_ref)
            end
          end)
        end)
        return
      end
    end

    -- Not a remote branch, or couldn't extract local name - checkout directly
    if preselected_ref == current_branch then
      vim.notify("[gitlad] Already on '" .. preselected_ref .. "'", vim.log.levels.INFO)
      return
    end
    do_checkout(preselected_ref)
    return
  end

  -- No preselected ref - show branch selection
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

      -- Get branches excluding current
      local branch_names = get_other_branch_names(branches, current_branch)

      if #branch_names == 0 then
        vim.notify("[gitlad] No other branches to checkout", vim.log.levels.INFO)
        return
      end

      vim.ui.select(branch_names, {
        prompt = "Checkout branch:",
      }, function(choice)
        if not choice then
          return
        end
        do_checkout(choice)
      end)
    end)
  end)
end

--- Create and checkout a new branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._create_and_checkout(repo_state, popup_data)
  vim.ui.input({
    prompt = "Create and checkout branch: ",
  }, function(name)
    if not name or name == "" then
      return
    end

    -- Ask for base (optional)
    vim.ui.input({
      prompt = "Base (leave empty for HEAD): ",
    }, function(base)
      local args = popup_data:get_arguments()

      git.checkout_new_branch(
        name,
        base,
        args,
        { cwd = repo_state.repo_root },
        function(success, err)
          vim.schedule(function()
            if success then
              vim.notify(
                "[gitlad] Created and switched to branch '" .. name .. "'",
                vim.log.levels.INFO
              )
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Create branch failed: " .. (err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end
      )
    end)
  end)
end

--- Create a branch (without checking it out)
---@param repo_state RepoState
---@param _popup_data PopupData
function M._create_branch(repo_state, _popup_data)
  vim.ui.input({
    prompt = "Create branch: ",
  }, function(name)
    if not name or name == "" then
      return
    end

    -- Ask for base (optional)
    vim.ui.input({
      prompt = "Base (leave empty for HEAD): ",
    }, function(base)
      git.create_branch(name, base, { cwd = repo_state.repo_root }, function(success, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Created branch '" .. name .. "'", vim.log.levels.INFO)
            -- No status refresh needed - branch list isn't shown in status
          else
            vim.notify(
              "[gitlad] Create branch failed: " .. (err or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end)
    end)
  end)
end

--- Rename a branch
---@param repo_state RepoState
---@param _popup_data PopupData
function M._rename_branch(repo_state, _popup_data)
  local current_branch = get_current_branch(repo_state)

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

      local branch_names = get_all_branch_names(branches)

      if #branch_names == 0 then
        vim.notify("[gitlad] No branches to rename", vim.log.levels.INFO)
        return
      end

      vim.ui.select(branch_names, {
        prompt = "Rename branch:",
      }, function(old_name)
        if not old_name then
          return
        end

        vim.ui.input({
          prompt = "New name for '" .. old_name .. "': ",
        }, function(new_name)
          if not new_name or new_name == "" then
            return
          end

          git.rename_branch(
            old_name,
            new_name,
            { cwd = repo_state.repo_root },
            function(success, rename_err)
              vim.schedule(function()
                if success then
                  vim.notify(
                    "[gitlad] Renamed '" .. old_name .. "' to '" .. new_name .. "'",
                    vim.log.levels.INFO
                  )
                  -- Refresh status if we renamed the current branch
                  if old_name == current_branch then
                    repo_state:refresh_status(true)
                  end
                else
                  vim.notify(
                    "[gitlad] Rename failed: " .. (rename_err or "unknown error"),
                    vim.log.levels.ERROR
                  )
                end
              end)
            end
          )
        end)
      end)
    end)
  end)
end

--- Set upstream (tracking branch) for current branch
---@param repo_state RepoState
---@param _popup_data PopupData
function M._set_upstream(repo_state, _popup_data)
  local current_branch = get_current_branch(repo_state)
  if not current_branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  -- Get list of remote branches
  git.remote_branches({ cwd = repo_state.repo_root }, function(branches, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remote branches: " .. err, vim.log.levels.ERROR)
        return
      end

      if not branches or #branches == 0 then
        vim.notify("[gitlad] No remote branches found", vim.log.levels.WARN)
        return
      end

      vim.ui.select(branches, {
        prompt = "Set upstream for '" .. current_branch .. "':",
      }, function(choice)
        if not choice then
          return
        end

        git.set_upstream(
          current_branch,
          choice,
          { cwd = repo_state.repo_root },
          function(success, set_err)
            vim.schedule(function()
              if success then
                vim.notify(
                  "[gitlad] Set upstream of '" .. current_branch .. "' to '" .. choice .. "'",
                  vim.log.levels.INFO
                )
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Set upstream failed: " .. (set_err or "unknown error"),
                  vim.log.levels.ERROR
                )
              end
            end)
          end
        )
      end)
    end)
  end)
end

--- Set push remote for current branch
---@param repo_state RepoState
---@param _popup_data PopupData
function M._set_push_remote(repo_state, _popup_data)
  local current_branch = get_current_branch(repo_state)
  if not current_branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  -- Get list of remotes
  git.remote_names({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remotes: " .. err, vim.log.levels.ERROR)
        return
      end

      if not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.WARN)
        return
      end

      vim.ui.select(remotes, {
        prompt = "Set push remote for '" .. current_branch .. "':",
      }, function(choice)
        if not choice then
          return
        end

        git.set_push_remote(
          current_branch,
          choice,
          { cwd = repo_state.repo_root },
          function(success, set_err)
            vim.schedule(function()
              if success then
                vim.notify(
                  "[gitlad] Set push remote of '" .. current_branch .. "' to '" .. choice .. "'",
                  vim.log.levels.INFO
                )
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Set push remote failed: " .. (set_err or "unknown error"),
                  vim.log.levels.ERROR
                )
              end
            end)
          end
        )
      end)
    end)
  end)
end

--- Spin-off: create a new branch with current changes and reset current branch to upstream
--- This is useful when you've made commits on the wrong branch
---@param repo_state RepoState
---@param _popup_data PopupData
function M._spinoff(repo_state, _popup_data)
  local current_branch = get_current_branch(repo_state)
  if not current_branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  -- Get upstream for current branch
  git.get_upstream(current_branch, { cwd = repo_state.repo_root }, function(upstream, err)
    vim.schedule(function()
      if err or not upstream then
        vim.notify(
          "[gitlad] No upstream configured for '" .. current_branch .. "'. Cannot spin-off.",
          vim.log.levels.ERROR
        )
        return
      end

      -- Check if there are commits to spin off (current branch ahead of upstream)
      local status = repo_state.status
      if status and status.ahead == 0 then
        vim.notify(
          "[gitlad] Branch is not ahead of upstream. Nothing to spin off.",
          vim.log.levels.INFO
        )
        return
      end

      -- Ask for new branch name
      vim.ui.input({
        prompt = "Spin-off to new branch: ",
      }, function(new_branch_name)
        if not new_branch_name or new_branch_name == "" then
          return
        end

        -- Create new branch at current HEAD
        git.create_branch(
          new_branch_name,
          "HEAD",
          { cwd = repo_state.repo_root },
          function(create_success, create_err)
            vim.schedule(function()
              if not create_success then
                vim.notify(
                  "[gitlad] Failed to create branch: " .. (create_err or "unknown error"),
                  vim.log.levels.ERROR
                )
                return
              end

              -- Reset current branch to upstream
              git.reset(
                upstream,
                "hard",
                { cwd = repo_state.repo_root },
                function(reset_success, reset_err)
                  vim.schedule(function()
                    if not reset_success then
                      vim.notify(
                        "[gitlad] Failed to reset to upstream: " .. (reset_err or "unknown error"),
                        vim.log.levels.ERROR
                      )
                      return
                    end

                    -- Switch to the new branch
                    git.checkout(
                      new_branch_name,
                      {},
                      { cwd = repo_state.repo_root },
                      function(checkout_success, checkout_err)
                        vim.schedule(function()
                          if not checkout_success then
                            vim.notify(
                              "[gitlad] Spun off to '"
                                .. new_branch_name
                                .. "' but failed to switch: "
                                .. (checkout_err or "unknown error"),
                              vim.log.levels.WARN
                            )
                            repo_state:refresh_status(true)
                            return
                          end

                          vim.notify(
                            "[gitlad] Spun off to '"
                              .. new_branch_name
                              .. "', reset '"
                              .. current_branch
                              .. "' to "
                              .. upstream,
                            vim.log.levels.INFO
                          )
                          repo_state:refresh_status(true)
                        end)
                      end
                    )
                  end)
                end
              )
            end)
          end
        )
      end)
    end)
  end)
end

--- Delete a branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._delete_branch(repo_state, popup_data)
  local current_branch = get_current_branch(repo_state)

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

      -- Can't delete current branch
      local branch_names = get_other_branch_names(branches, current_branch)

      if #branch_names == 0 then
        vim.notify(
          "[gitlad] No branches to delete (cannot delete current branch)",
          vim.log.levels.INFO
        )
        return
      end

      vim.ui.select(branch_names, {
        prompt = "Delete branch:",
      }, function(choice)
        if not choice then
          return
        end

        -- Check if force switch is enabled
        local force = false
        for _, sw in ipairs(popup_data.switches) do
          if sw.cli == "force" and sw.enabled then
            force = true
            break
          end
        end

        -- Confirm deletion
        local confirm_msg = force and string.format("Force delete branch '%s'?", choice)
          or string.format("Delete branch '%s'?", choice)

        vim.ui.select({ "Yes", "No" }, {
          prompt = confirm_msg,
        }, function(confirm)
          if confirm ~= "Yes" then
            return
          end

          git.delete_branch(
            choice,
            force,
            { cwd = repo_state.repo_root },
            function(success, delete_err)
              vim.schedule(function()
                if success then
                  vim.notify("[gitlad] Deleted branch '" .. choice .. "'", vim.log.levels.INFO)
                else
                  -- If delete failed with non-force, suggest force
                  local msg = delete_err or "unknown error"
                  if not force and msg:match("not fully merged") then
                    msg = msg .. " (use -f to force delete)"
                  end
                  vim.notify("[gitlad] Delete failed: " .. msg, vim.log.levels.ERROR)
                end
              end)
            end
          )
        end)
      end)
    end)
  end)
end

return M
