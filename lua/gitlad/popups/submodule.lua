---@mod gitlad.popups.submodule Submodule popup
---@brief [[
--- Transient-style submodule popup with switches, options, and actions.
--- Follows magit submodule popup patterns (evil-collection keybind: ').
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Format submodule entries for display in vim.ui.select
---@param submodules SubmoduleEntry[]
---@return string[]
local function format_submodule_list(submodules)
  local items = {}
  for _, submodule in ipairs(submodules) do
    local status_char = ""
    if submodule.status == "modified" then
      status_char = "+ "
    elseif submodule.status == "uninitialized" then
      status_char = "- "
    elseif submodule.status == "merge_conflict" then
      status_char = "U "
    else
      status_char = "  "
    end
    local info = submodule.describe or submodule.sha:sub(1, 7)
    table.insert(items, status_char .. submodule.path .. " (" .. info .. ")")
  end
  return items
end

--- Get submodule path from formatted display string
---@param display string Formatted submodule display (e.g., "+ path/to/sub (v1.0)")
---@return string|nil path Submodule path
local function get_path_from_display(display)
  -- Format: "[+- ] path (info)"
  return display:match("^[%+%-%sU]+([^%(]+)%s+%(")
end

--- Prompt user to select submodules from a list
---@param repo_state RepoState
---@param prompt string Prompt text
---@param callback fun(paths: string[])
local function select_submodules(repo_state, prompt, callback)
  git.submodule_status({ cwd = repo_state.repo_root }, function(submodules, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get submodule list: " .. err, vim.log.levels.ERROR)
        return
      end

      if not submodules or #submodules == 0 then
        vim.notify("[gitlad] No submodules found", vim.log.levels.INFO)
        return
      end

      local items = format_submodule_list(submodules)

      vim.ui.select(items, { prompt = prompt }, function(choice)
        if not choice then
          return
        end

        local path = get_path_from_display(choice)
        if not path then
          vim.notify("[gitlad] Invalid submodule selection", vim.log.levels.ERROR)
          return
        end

        callback({ vim.trim(path) })
      end)
    end)
  end)
end

--- Create and show the submodule popup
---@param repo_state RepoState
---@param context? { submodule: SubmoduleEntry, paths: string[] } Optional context for operations
function M.open(repo_state, context)
  local submodule_at_point = context and context.submodule or nil
  local selected_paths = context and context.paths or nil

  -- Build action labels with context info
  local at_point_label = ""
  if submodule_at_point then
    at_point_label = " " .. submodule_at_point.path
  elseif selected_paths and #selected_paths > 0 then
    at_point_label = " (" .. #selected_paths .. " selected)"
  end

  local submodule_popup = popup
    .builder()
    :name("Submodule")
    -- Switches
    :switch("f", "force", "Force")
    :switch("r", "recursive", "Recursive")
    :switch("N", "no-fetch", "Don't fetch (for update)")
    -- Mutually exclusive update modes (shown together)
    :switch("C", "checkout", "Checkout")
    :switch("R", "rebase", "Rebase onto")
    :switch("M", "merge", "Merge")
    -- One module actions
    :group_heading("One module" .. at_point_label)
    :action("a", "Add", function(_popup_data)
      M._add(repo_state)
    end)
    :action("r", "Register (init)", function(popup_data)
      M._init(repo_state, submodule_at_point, selected_paths, popup_data)
    end)
    :action("p", "Populate (update --init)", function(popup_data)
      M._populate(repo_state, submodule_at_point, selected_paths, popup_data)
    end)
    :action("u", "Update", function(popup_data)
      M._update(repo_state, submodule_at_point, selected_paths, popup_data)
    end)
    :action("s", "Synchronize", function(popup_data)
      M._sync(repo_state, submodule_at_point, selected_paths, popup_data)
    end)
    :action("d", "Unpopulate (deinit)", function(popup_data)
      M._deinit(repo_state, submodule_at_point, selected_paths, popup_data)
    end)
    :action("k", "Remove", function(_popup_data)
      M._remove(repo_state, submodule_at_point, selected_paths)
    end)
    -- All modules actions
    :group_heading("All modules")
    :action("l", "List", function(_popup_data)
      M._list(repo_state)
    end)
    :action("F", "Fetch all", function(popup_data)
      M._fetch_all(repo_state, popup_data)
    end)
    :build()

  submodule_popup:show()
end

--- Get paths to operate on (from context or prompt)
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
---@return string[]|nil paths, boolean needs_prompt
local function get_paths(submodule_at_point, selected_paths)
  if selected_paths and #selected_paths > 0 then
    return selected_paths, false
  elseif submodule_at_point then
    return { submodule_at_point.path }, false
  end
  return nil, true
end

--- Add a new submodule
---@param repo_state RepoState
function M._add(repo_state)
  vim.ui.input({ prompt = "Submodule URL: " }, function(url)
    if not url or url == "" then
      return
    end

    vim.ui.input({ prompt = "Destination path (optional, enter for default): " }, function(path)
      local dest_path = (path and path ~= "") and path or nil

      vim.notify("[gitlad] Adding submodule...", vim.log.levels.INFO)

      git.submodule_add(
        url,
        dest_path,
        {},
        { cwd = repo_state.repo_root },
        function(success, output, err)
          vim.schedule(function()
            if success then
              vim.notify("[gitlad] Submodule added", vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Add failed: " .. (err or output or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end
      )
    end)
  end)
end

--- Initialize (register) submodules
---@param repo_state RepoState
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
---@param popup_data PopupData
function M._init(repo_state, submodule_at_point, selected_paths, popup_data)
  local paths, needs_prompt = get_paths(submodule_at_point, selected_paths)

  local function do_init(target_paths)
    vim.notify("[gitlad] Initializing submodule(s)...", vim.log.levels.INFO)

    git.submodule_init(target_paths, { cwd = repo_state.repo_root }, function(success, output, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Submodule(s) initialized", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify(
            "[gitlad] Init failed: " .. (err or output or "unknown error"),
            vim.log.levels.ERROR
          )
        end
      end)
    end)
  end

  if needs_prompt then
    select_submodules(repo_state, "Initialize submodule:", do_init)
  else
    do_init(paths)
  end
end

--- Populate submodules (update --init)
---@param repo_state RepoState
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
---@param popup_data PopupData
function M._populate(repo_state, submodule_at_point, selected_paths, popup_data)
  local paths, needs_prompt = get_paths(submodule_at_point, selected_paths)

  local function do_populate(target_paths)
    local args = { "--init" }
    local switch_args = popup_data:get_arguments()
    vim.list_extend(args, switch_args)

    vim.notify("[gitlad] Populating submodule(s)...", vim.log.levels.INFO)

    git.submodule_update(
      target_paths,
      args,
      { cwd = repo_state.repo_root },
      function(success, output, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Submodule(s) populated", vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            vim.notify(
              "[gitlad] Populate failed: " .. (err or output or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end
    )
  end

  if needs_prompt then
    select_submodules(repo_state, "Populate submodule:", do_populate)
  else
    do_populate(paths)
  end
end

--- Update submodules
---@param repo_state RepoState
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
---@param popup_data PopupData
function M._update(repo_state, submodule_at_point, selected_paths, popup_data)
  local paths, needs_prompt = get_paths(submodule_at_point, selected_paths)

  local function do_update(target_paths)
    local args = popup_data:get_arguments()

    vim.notify("[gitlad] Updating submodule(s)...", vim.log.levels.INFO)

    git.submodule_update(
      target_paths,
      args,
      { cwd = repo_state.repo_root },
      function(success, output, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Submodule(s) updated", vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            vim.notify(
              "[gitlad] Update failed: " .. (err or output or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end
    )
  end

  if needs_prompt then
    select_submodules(repo_state, "Update submodule:", do_update)
  else
    do_update(paths)
  end
end

--- Sync submodule URLs
---@param repo_state RepoState
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
---@param popup_data PopupData
function M._sync(repo_state, submodule_at_point, selected_paths, popup_data)
  local paths, needs_prompt = get_paths(submodule_at_point, selected_paths)

  local function do_sync(target_paths)
    local args = popup_data:get_arguments()

    vim.notify("[gitlad] Synchronizing submodule(s)...", vim.log.levels.INFO)

    git.submodule_sync(
      target_paths,
      args,
      { cwd = repo_state.repo_root },
      function(success, output, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Submodule(s) synchronized", vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            vim.notify(
              "[gitlad] Sync failed: " .. (err or output or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end
    )
  end

  if needs_prompt then
    select_submodules(repo_state, "Sync submodule:", do_sync)
  else
    do_sync(paths)
  end
end

--- Deinit (unpopulate) submodules
---@param repo_state RepoState
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
---@param popup_data PopupData
function M._deinit(repo_state, submodule_at_point, selected_paths, popup_data)
  local paths, needs_prompt = get_paths(submodule_at_point, selected_paths)

  local function do_deinit(target_paths)
    local args = popup_data:get_arguments()

    -- Confirm deinit
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Deinitialize submodule(s)? Working directories will be removed.",
    }, function(choice)
      if choice ~= "Yes" then
        return
      end

      vim.notify("[gitlad] Deinitializing submodule(s)...", vim.log.levels.INFO)

      git.submodule_deinit(
        target_paths,
        args,
        { cwd = repo_state.repo_root },
        function(success, output, err)
          vim.schedule(function()
            if success then
              vim.notify("[gitlad] Submodule(s) deinitialized", vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Deinit failed: " .. (err or output or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end
      )
    end)
  end

  if needs_prompt then
    select_submodules(repo_state, "Deinit submodule:", do_deinit)
  else
    do_deinit(paths)
  end
end

--- Remove a submodule completely
---@param repo_state RepoState
---@param submodule_at_point SubmoduleEntry|nil
---@param selected_paths string[]|nil
function M._remove(repo_state, submodule_at_point, selected_paths)
  local paths, needs_prompt = get_paths(submodule_at_point, selected_paths)

  local function do_remove(target_paths)
    if #target_paths ~= 1 then
      vim.notify("[gitlad] Remove only supports one submodule at a time", vim.log.levels.WARN)
      return
    end

    local path = target_paths[1]

    -- Confirm removal
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Remove submodule '"
        .. path
        .. "'? This will:\n- Deinit the submodule\n- Remove from .gitmodules\n- Remove from staging",
    }, function(choice)
      if choice ~= "Yes" then
        return
      end

      vim.notify("[gitlad] Removing submodule...", vim.log.levels.INFO)

      -- Step 1: Deinit
      git.submodule_deinit(
        { path },
        { "--force" },
        { cwd = repo_state.repo_root },
        function(deinit_success, _, deinit_err)
          if not deinit_success then
            vim.schedule(function()
              vim.notify(
                "[gitlad] Deinit failed: " .. (deinit_err or "unknown error"),
                vim.log.levels.ERROR
              )
            end)
            return
          end

          -- Step 2: Remove from index and working tree
          local rm_args = { "rm", "-f", path }
          require("gitlad.git.cli").run_async(
            rm_args,
            { cwd = repo_state.repo_root },
            function(result)
              vim.schedule(function()
                if result.code == 0 then
                  vim.notify("[gitlad] Submodule removed", vim.log.levels.INFO)
                  repo_state:refresh_status(true)
                else
                  local err_msg = table.concat(result.stderr, "\n")
                  vim.notify("[gitlad] Remove failed: " .. err_msg, vim.log.levels.ERROR)
                end
              end)
            end
          )
        end
      )
    end)
  end

  if needs_prompt then
    select_submodules(repo_state, "Remove submodule:", do_remove)
  else
    do_remove(paths)
  end
end

--- List all submodules
---@param repo_state RepoState
function M._list(repo_state)
  git.submodule_status({ cwd = repo_state.repo_root }, function(submodules, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get submodule list: " .. err, vim.log.levels.ERROR)
        return
      end

      if not submodules or #submodules == 0 then
        vim.notify("[gitlad] No submodules found", vim.log.levels.INFO)
        return
      end

      -- Display in a floating window or use vim.ui.select for now
      local items = format_submodule_list(submodules)
      vim.ui.select(items, {
        prompt = "Submodules (" .. #submodules .. "):",
      }, function(_choice)
        -- Just viewing, no action on selection
      end)
    end)
  end)
end

--- Fetch in all submodules
---@param repo_state RepoState
---@param popup_data PopupData
function M._fetch_all(repo_state, popup_data)
  local args = popup_data:get_arguments()

  vim.notify("[gitlad] Fetching in all submodules...", vim.log.levels.INFO)

  git.fetch_modules(args, { cwd = repo_state.repo_root }, function(success, output, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Fetch complete in all submodules", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify(
          "[gitlad] Fetch failed: " .. (err or output or "unknown error"),
          vim.log.levels.ERROR
        )
      end
    end)
  end)
end

return M
