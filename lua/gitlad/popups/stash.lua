---@mod gitlad.popups.stash Stash popup
---@brief [[
--- Transient-style stash popup with switches, options, and actions.
--- Follows magit stash popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Format stash entries for display in vim.ui.select
---@param stashes StashEntry[]
---@return string[]
local function format_stash_list(stashes)
  local items = {}
  for _, stash in ipairs(stashes) do
    table.insert(items, stash.ref .. ": " .. stash.message)
  end
  return items
end

--- Get stash ref from formatted display string
---@param display string Formatted stash display (e.g., "stash@{0}: message")
---@return string|nil ref Stash ref (e.g., "stash@{0}")
local function get_stash_ref_from_display(display)
  return display:match("^(stash@{%d+}):")
end

--- Create and show the stash popup
---@param repo_state RepoState
---@param context? { stash: StashEntry } Optional stash at point for context-aware operations
function M.open(repo_state, context)
  local stash_at_point = context and context.stash or nil

  -- Build action labels with context info
  local pop_label = stash_at_point and ("Pop " .. stash_at_point.ref) or "Pop"
  local apply_label = stash_at_point and ("Apply " .. stash_at_point.ref) or "Apply"
  local drop_label = stash_at_point and ("Drop " .. stash_at_point.ref) or "Drop"

  local stash_popup = popup
    .builder()
    :name("Stash")
    -- Switches
    :switch("u", "include-untracked", "Include untracked files")
    :switch("a", "all", "Include all files (untracked + ignored)")
    :switch("k", "keep-index", "Keep staged changes in index")
    -- Actions - Stash group
    :group_heading("Stash")
    :action("z", "Stash", function(popup_data)
      M._stash_push(repo_state, popup_data)
    end)
    :action("i", "Stash index", function(popup_data)
      M._stash_index(repo_state, popup_data)
    end)
    -- Actions - Use group
    :group_heading("Use")
    :action("p", pop_label, function(_popup_data)
      if stash_at_point then
        M._stash_pop_direct(repo_state, stash_at_point.ref)
      else
        M._stash_pop(repo_state)
      end
    end)
    :action("a", apply_label, function(_popup_data)
      if stash_at_point then
        M._stash_apply_direct(repo_state, stash_at_point.ref)
      else
        M._stash_apply(repo_state)
      end
    end)
    :action("d", drop_label, function(_popup_data)
      if stash_at_point then
        M._stash_drop_direct(repo_state, stash_at_point.ref)
      else
        M._stash_drop(repo_state)
      end
    end)
    :build()

  stash_popup:show()
end

--- Stash changes with optional message
---@param repo_state RepoState
---@param popup_data PopupData
function M._stash_push(repo_state, popup_data)
  -- Prompt for stash message
  vim.ui.input({
    prompt = "Stash message (optional): ",
  }, function(message)
    -- User can cancel with nil, or provide empty string
    if message == nil then
      return
    end

    local args = popup_data:get_arguments()

    vim.notify("[gitlad] Stashing...", vim.log.levels.INFO)

    git.stash_push(message, args, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          local msg = message ~= "" and ("Stashed: " .. message) or "Stashed changes"
          vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Stash failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

--- Stash only staged changes (index)
---@param repo_state RepoState
---@param popup_data PopupData
function M._stash_index(repo_state, popup_data)
  -- Prompt for stash message
  vim.ui.input({
    prompt = "Stash message (optional): ",
  }, function(message)
    if message == nil then
      return
    end

    -- Add --staged flag to only stash the index
    local args = popup_data:get_arguments()
    table.insert(args, "--staged")

    vim.notify("[gitlad] Stashing index...", vim.log.levels.INFO)

    git.stash_push(message, args, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          local msg = message ~= "" and ("Stashed index: " .. message) or "Stashed index"
          vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify(
            "[gitlad] Stash index failed: " .. (err or "unknown error"),
            vim.log.levels.ERROR
          )
        end
      end)
    end)
  end)
end

--- Pop a stash (apply and remove)
---@param repo_state RepoState
function M._stash_pop(repo_state)
  git.stash_list({ cwd = repo_state.repo_root }, function(stashes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get stash list: " .. err, vim.log.levels.ERROR)
        return
      end

      if not stashes or #stashes == 0 then
        vim.notify("[gitlad] No stashes found", vim.log.levels.INFO)
        return
      end

      local items = format_stash_list(stashes)

      vim.ui.select(items, {
        prompt = "Pop stash:",
      }, function(choice)
        if not choice then
          return
        end

        local stash_ref = get_stash_ref_from_display(choice)
        if not stash_ref then
          vim.notify("[gitlad] Invalid stash selection", vim.log.levels.ERROR)
          return
        end

        vim.notify("[gitlad] Popping stash...", vim.log.levels.INFO)

        git.stash_pop(stash_ref, { cwd = repo_state.repo_root }, function(success, pop_err)
          vim.schedule(function()
            if success then
              vim.notify("[gitlad] Popped " .. stash_ref, vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Pop failed: " .. (pop_err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end)
      end)
    end)
  end)
end

--- Apply a stash (without removing it)
---@param repo_state RepoState
function M._stash_apply(repo_state)
  git.stash_list({ cwd = repo_state.repo_root }, function(stashes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get stash list: " .. err, vim.log.levels.ERROR)
        return
      end

      if not stashes or #stashes == 0 then
        vim.notify("[gitlad] No stashes found", vim.log.levels.INFO)
        return
      end

      local items = format_stash_list(stashes)

      vim.ui.select(items, {
        prompt = "Apply stash:",
      }, function(choice)
        if not choice then
          return
        end

        local stash_ref = get_stash_ref_from_display(choice)
        if not stash_ref then
          vim.notify("[gitlad] Invalid stash selection", vim.log.levels.ERROR)
          return
        end

        vim.notify("[gitlad] Applying stash...", vim.log.levels.INFO)

        git.stash_apply(stash_ref, { cwd = repo_state.repo_root }, function(success, apply_err)
          vim.schedule(function()
            if success then
              vim.notify("[gitlad] Applied " .. stash_ref, vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Apply failed: " .. (apply_err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end)
      end)
    end)
  end)
end

--- Drop a stash (remove without applying)
---@param repo_state RepoState
function M._stash_drop(repo_state)
  git.stash_list({ cwd = repo_state.repo_root }, function(stashes, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get stash list: " .. err, vim.log.levels.ERROR)
        return
      end

      if not stashes or #stashes == 0 then
        vim.notify("[gitlad] No stashes found", vim.log.levels.INFO)
        return
      end

      local items = format_stash_list(stashes)

      vim.ui.select(items, {
        prompt = "Drop stash:",
      }, function(choice)
        if not choice then
          return
        end

        local stash_ref = get_stash_ref_from_display(choice)
        if not stash_ref then
          vim.notify("[gitlad] Invalid stash selection", vim.log.levels.ERROR)
          return
        end

        -- Confirm deletion
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Drop " .. stash_ref .. "? This cannot be undone.",
        }, function(confirm)
          if confirm ~= "Yes" then
            return
          end

          vim.notify("[gitlad] Dropping stash...", vim.log.levels.INFO)

          git.stash_drop(stash_ref, { cwd = repo_state.repo_root }, function(success, drop_err)
            vim.schedule(function()
              if success then
                vim.notify("[gitlad] Dropped " .. stash_ref, vim.log.levels.INFO)
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Drop failed: " .. (drop_err or "unknown error"),
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

--- Pop a specific stash directly (without selection prompt)
---@param repo_state RepoState
---@param stash_ref string Stash ref (e.g., "stash@{0}")
function M._stash_pop_direct(repo_state, stash_ref)
  vim.notify("[gitlad] Popping stash...", vim.log.levels.INFO)
  git.stash_pop(stash_ref, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Popped " .. stash_ref, vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Pop failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Apply a specific stash directly (without selection prompt)
---@param repo_state RepoState
---@param stash_ref string Stash ref (e.g., "stash@{0}")
function M._stash_apply_direct(repo_state, stash_ref)
  vim.notify("[gitlad] Applying stash...", vim.log.levels.INFO)
  git.stash_apply(stash_ref, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Applied " .. stash_ref, vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Apply failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Drop a specific stash directly (with confirmation but without selection prompt)
---@param repo_state RepoState
---@param stash_ref string Stash ref (e.g., "stash@{0}")
function M._stash_drop_direct(repo_state, stash_ref)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Drop " .. stash_ref .. "? This cannot be undone.",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    vim.notify("[gitlad] Dropping stash...", vim.log.levels.INFO)
    git.stash_drop(stash_ref, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Dropped " .. stash_ref, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Drop failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
