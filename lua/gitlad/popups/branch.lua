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

--- Create and show the branch popup
---@param repo_state RepoState
function M.open(repo_state)
  local branch_popup = popup
    .builder()
    :name("Branch")
    -- Switches
    :switch("f", "force", "Force delete (even if not merged)")
    -- Actions - Checkout group
    :group_heading("Checkout")
    :action("b", "Checkout branch", function(popup_data)
      M._checkout_branch(repo_state, popup_data)
    end)
    :action("c", "Create and checkout", function(popup_data)
      M._create_and_checkout(repo_state, popup_data)
    end)
    -- Actions - Create group
    :group_heading("Create")
    :action("n", "Create branch", function(popup_data)
      M._create_branch(repo_state, popup_data)
    end)
    -- Actions - Do group
    :group_heading("Do")
    :action("m", "Rename", function(popup_data)
      M._rename_branch(repo_state, popup_data)
    end)
    :action("x", "Spin-off", function(popup_data)
      M._spinoff(repo_state, popup_data)
    end)
    :action("D", "Delete", function(popup_data)
      M._delete_branch(repo_state, popup_data)
    end)
    -- Actions - Configure group
    :group_heading("Configure")
    :action("u", "Set upstream", function(popup_data)
      M._set_upstream(repo_state, popup_data)
    end)
    :action("p", "Configure pushremote", function(popup_data)
      M._set_push_remote(repo_state, popup_data)
    end)
    :build()

  branch_popup:show()
end

--- Checkout an existing branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._checkout_branch(repo_state, popup_data)
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
        vim.notify("[gitlad] No other branches to checkout", vim.log.levels.INFO)
        return
      end

      vim.ui.select(branch_names, {
        prompt = "Checkout branch:",
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
