---@mod gitlad.popups.remote Remote popup
---@brief [[
--- Transient-style remote popup for managing git remotes.
--- Follows magit remote popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Format remote entries for display in vim.ui.select
---@param remotes GitRemote[]
---@return string[]
local function format_remote_list(remotes)
  local items = {}
  for _, remote in ipairs(remotes) do
    table.insert(items, remote.name .. " (" .. remote.fetch_url .. ")")
  end
  return items
end

--- Get remote name from formatted display string
---@param display string Formatted remote display (e.g., "origin (https://...)")
---@return string|nil name Remote name
local function get_remote_name_from_display(display)
  return display:match("^([^%s]+)")
end

--- Create and show the remote popup
---@param repo_state RepoState
---@param context? table Optional context (unused for now)
function M.open(repo_state, context)
  _ = context -- unused for now

  local remote_popup = popup
    .builder()
    :name("Remotes")
    -- Arguments for add
    :switch("f", "fetch", "Fetch after add")
    -- Actions
    :group_heading("Actions")
    :columns(3)
    :action("a", "Add", function(popup_data)
      M._add_remote(repo_state, popup_data)
    end)
    :action("r", "Rename", function(_popup_data)
      M._rename_remote(repo_state)
    end)
    :action("x", "Remove", function(_popup_data)
      M._remove_remote(repo_state)
    end)
    :group_heading("Prune")
    :action("p", "Prune stale branches", function(_popup_data)
      M._prune_remote(repo_state)
    end)
    :action("P", "Prune stale refspecs", function(_popup_data)
      M._fetch_prune_remote(repo_state)
    end)
    :build()

  remote_popup:show()
end

--- Add a new remote
---@param repo_state RepoState
---@param popup_data PopupData
function M._add_remote(repo_state, popup_data)
  -- Prompt for remote name
  vim.ui.input({
    prompt = "Remote name: ",
  }, function(name)
    if not name or name == "" then
      return
    end

    -- Prompt for URL
    vim.ui.input({
      prompt = "Remote URL: ",
    }, function(url)
      if not url or url == "" then
        return
      end

      local args = popup_data:get_arguments()

      vim.notify("[gitlad] Adding remote...", vim.log.levels.INFO)

      git.remote_add(name, url, args, { cwd = repo_state.repo_root }, function(success, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Added remote '" .. name .. "'", vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            vim.notify(
              "[gitlad] Failed to add remote: " .. (err or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end)
    end)
  end)
end

--- Rename an existing remote
---@param repo_state RepoState
function M._rename_remote(repo_state)
  git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remotes: " .. err, vim.log.levels.ERROR)
        return
      end

      if not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.INFO)
        return
      end

      local items = format_remote_list(remotes)

      vim.ui.select(items, {
        prompt = "Rename remote:",
      }, function(choice)
        if not choice then
          return
        end

        local old_name = get_remote_name_from_display(choice)
        if not old_name then
          vim.notify("[gitlad] Invalid remote selection", vim.log.levels.ERROR)
          return
        end

        vim.ui.input({
          prompt = "New name for '" .. old_name .. "': ",
        }, function(new_name)
          if not new_name or new_name == "" then
            return
          end

          vim.notify("[gitlad] Renaming remote...", vim.log.levels.INFO)

          git.remote_rename(
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
                  repo_state:refresh_status(true)
                else
                  vim.notify(
                    "[gitlad] Failed to rename remote: " .. (rename_err or "unknown error"),
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

--- Remove an existing remote
---@param repo_state RepoState
function M._remove_remote(repo_state)
  git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remotes: " .. err, vim.log.levels.ERROR)
        return
      end

      if not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.INFO)
        return
      end

      local items = format_remote_list(remotes)

      vim.ui.select(items, {
        prompt = "Remove remote:",
      }, function(choice)
        if not choice then
          return
        end

        local name = get_remote_name_from_display(choice)
        if not name then
          vim.notify("[gitlad] Invalid remote selection", vim.log.levels.ERROR)
          return
        end

        -- Confirm deletion
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Remove remote '" .. name .. "'? This cannot be undone.",
        }, function(confirm)
          if confirm ~= "Yes" then
            return
          end

          vim.notify("[gitlad] Removing remote...", vim.log.levels.INFO)

          git.remote_remove(name, { cwd = repo_state.repo_root }, function(success, remove_err)
            vim.schedule(function()
              if success then
                vim.notify("[gitlad] Removed remote '" .. name .. "'", vim.log.levels.INFO)
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Failed to remove remote: " .. (remove_err or "unknown error"),
                  vim.log.levels.ERROR
                )
              end
            end)
          end)
        end)
      end)
    end)
  end)
end

--- Prune stale remote-tracking branches
---@param repo_state RepoState
function M._prune_remote(repo_state)
  git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remotes: " .. err, vim.log.levels.ERROR)
        return
      end

      if not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.INFO)
        return
      end

      local items = format_remote_list(remotes)

      vim.ui.select(items, {
        prompt = "Prune remote:",
      }, function(choice)
        if not choice then
          return
        end

        local name = get_remote_name_from_display(choice)
        if not name then
          vim.notify("[gitlad] Invalid remote selection", vim.log.levels.ERROR)
          return
        end

        vim.notify("[gitlad] Pruning stale branches...", vim.log.levels.INFO)

        git.remote_prune(
          name,
          false,
          { cwd = repo_state.repo_root },
          function(success, output, prune_err)
            vim.schedule(function()
              if success then
                local msg = output and output ~= "" and output or "No stale branches to prune"
                vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Failed to prune: " .. (prune_err or "unknown error"),
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

--- Fetch with --prune to prune stale refspecs
---@param repo_state RepoState
function M._fetch_prune_remote(repo_state)
  git.remotes({ cwd = repo_state.repo_root }, function(remotes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get remotes: " .. err, vim.log.levels.ERROR)
        return
      end

      if not remotes or #remotes == 0 then
        vim.notify("[gitlad] No remotes configured", vim.log.levels.INFO)
        return
      end

      local items = format_remote_list(remotes)

      vim.ui.select(items, {
        prompt = "Fetch --prune remote:",
      }, function(choice)
        if not choice then
          return
        end

        local name = get_remote_name_from_display(choice)
        if not name then
          vim.notify("[gitlad] Invalid remote selection", vim.log.levels.ERROR)
          return
        end

        vim.notify("[gitlad] Fetching with prune...", vim.log.levels.INFO)

        git.fetch(
          { "--prune", name },
          { cwd = repo_state.repo_root },
          function(success, _, fetch_err)
            vim.schedule(function()
              if success then
                vim.notify("[gitlad] Fetched and pruned '" .. name .. "'", vim.log.levels.INFO)
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Failed to fetch: " .. (fetch_err or "unknown error"),
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

return M
