---@mod gitlad.popups.worktree Worktree popup
---@brief [[
--- Transient-style worktree popup with switches, options, and actions.
--- Follows magit worktree popup patterns (evil-collection keybind: %).
--- When worktrunk (wt) is installed and enabled, shows a worktrunk-oriented
--- popup with Switch/Merge/Remove/Steps sections plus a "Git Worktree" escape
--- hatch for raw git operations. Otherwise falls back to the standard git popup.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")
local prompt_module = require("gitlad.utils.prompt")
local config = require("gitlad.config")
local pending_ops = require("gitlad.state.pending_ops")

--- Format worktree entries for display in vim.ui.select
---@param worktrees WorktreeEntry[]
---@param current_path string Current worktree path (to mark with *)
---@return string[]
local function format_worktree_list(worktrees, current_path)
  local items = {}
  for _, wt in ipairs(worktrees) do
    local prefix = ""
    if wt.path == current_path then
      prefix = "* "
    elseif wt.locked then
      prefix = "L "
    else
      prefix = "  "
    end

    local branch_info = wt.branch or "(detached)"
    local short_path = vim.fn.fnamemodify(wt.path, ":~")
    table.insert(items, prefix .. branch_info .. "  " .. short_path)
  end
  return items
end

--- Get worktree from formatted display string
---@param display string Formatted worktree display
---@param worktrees WorktreeEntry[]
---@return WorktreeEntry|nil
local function get_worktree_from_display(display, worktrees)
  for _, wt in ipairs(worktrees) do
    local short_path = vim.fn.fnamemodify(wt.path, ":~")
    if display:find(short_path, 1, true) then
      return wt
    end
  end
  return nil
end

--- Normalize repo root by stripping trailing slash
--- This is needed because vim.fn.fnamemodify with :p adds a trailing slash,
--- which breaks :h and :t modifiers (e.g., "/path/to/repo/":t returns "")
---@param repo_root string Repository root path
---@return string
local function normalize_repo_root(repo_root)
  return repo_root:gsub("/$", "")
end

--- Generate worktree path using sibling strategy
--- Given repo at /path/to/repo, creates worktree at /path/to/repo_<branch>
---@param repo_root string Repository root path
---@param ref string Branch name or commit hash
---@return string
local function generate_sibling_path(repo_root, ref)
  local normalized = normalize_repo_root(repo_root)
  local parent = vim.fn.fnamemodify(normalized, ":h")
  local repo_name = vim.fn.fnamemodify(normalized, ":t")
  -- Sanitize ref for filesystem (replace / with -)
  local safe_ref = ref:gsub("/", "-")
  return parent .. "/" .. repo_name .. "_" .. safe_ref
end

--- Generate worktree path using sibling-bare strategy
--- Given repo at /path/to/repo, creates worktree at /path/to/<branch>
--- This is useful when you structure worktrees as:
---   repo-name/main/
---   repo-name/branch1/
---   repo-name/branch2/
---@param repo_root string Repository root path
---@param ref string Branch name or commit hash
---@return string
local function generate_sibling_bare_path(repo_root, ref)
  local normalized = normalize_repo_root(repo_root)
  local parent = vim.fn.fnamemodify(normalized, ":h")
  -- Sanitize ref for filesystem (replace / with -)
  local safe_ref = ref:gsub("/", "-")
  return parent .. "/" .. safe_ref
end

--- Prompt user to select a worktree from a list (excluding main and current)
---@param repo_state RepoState
---@param prompt_text string Prompt text
---@param include_current boolean Whether to include current worktree in list
---@param callback fun(worktree: WorktreeEntry|nil)
local function select_worktree(repo_state, prompt_text, include_current, callback)
  git.worktree_list({ cwd = repo_state.repo_root }, function(worktrees, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get worktree list: " .. err, vim.log.levels.ERROR)
        return
      end

      if not worktrees or #worktrees == 0 then
        vim.notify("[gitlad] No worktrees found", vim.log.levels.INFO)
        return
      end

      -- Filter out main worktree, and optionally current
      local selectable = {}
      for _, wt in ipairs(worktrees) do
        if not wt.is_main then
          if include_current or wt.path ~= repo_state.repo_root then
            table.insert(selectable, wt)
          end
        end
      end

      if #selectable == 0 then
        vim.notify("[gitlad] No worktrees available for this operation", vim.log.levels.INFO)
        return
      end

      local items = format_worktree_list(selectable, repo_state.repo_root)

      vim.ui.select(items, { prompt = prompt_text }, function(choice)
        if not choice then
          callback(nil)
          return
        end

        local selected = get_worktree_from_display(choice, selectable)
        callback(selected)
      end)
    end)
  end)
end

--- Create and show the worktree popup, bifurcating into worktrunk or git mode.
---@param repo_state RepoState
---@param context? { worktree: WorktreeEntry } Optional context for operations
function M.open(repo_state, context)
  local cfg = config.get()
  local wt = require("gitlad.worktrunk")
  if wt.is_active(cfg.worktree) then
    M._open_worktrunk_popup(repo_state, context, cfg)
  else
    M._open_git_popup(repo_state, context)
  end
end

--- Create and show the standard git worktree popup (no worktrunk).
---@param repo_state RepoState
---@param context? { worktree: WorktreeEntry } Optional context for operations
function M._open_git_popup(repo_state, context)
  local worktree_at_point = context and context.worktree or nil

  -- Build action labels with context info
  local at_point_label = ""
  if worktree_at_point then
    at_point_label = " " .. vim.fn.fnamemodify(worktree_at_point.path, ":t")
  end

  local worktree_popup = popup
    .builder()
    :name("Worktree")
    -- Switches
    :switch("f", "force", "Force operations")
    :switch("d", "detach", "Detach HEAD")
    :switch("l", "lock", "Lock after adding")
    -- Create actions
    :group_heading("Create new")
    :action("b", "worktree", function(popup_data)
      M._add_worktree(repo_state, popup_data)
    end)
    :action("c", "branch and worktree", function(popup_data)
      M._add_branch_and_worktree(repo_state, popup_data)
    end)
    -- Command actions
    :group_heading("Commands" .. at_point_label)
    :action("m", "Move worktree", function(_popup_data)
      if worktree_at_point and not worktree_at_point.is_main then
        M._move_worktree_direct(repo_state, worktree_at_point)
      else
        M._move_worktree(repo_state)
      end
    end)
    :action("k", "Delete worktree", function(popup_data)
      if worktree_at_point and not worktree_at_point.is_main then
        M._delete_worktree_direct(repo_state, worktree_at_point, popup_data)
      else
        M._delete_worktree(repo_state, popup_data)
      end
    end)
    :action("g", "Visit worktree", function(_popup_data)
      if worktree_at_point then
        M._visit_worktree_direct(repo_state, worktree_at_point)
      else
        M._visit_worktree(repo_state)
      end
    end)
    -- Lock actions
    :group_heading("Lock")
    :action("l", "Lock worktree", function(_popup_data)
      if worktree_at_point and not worktree_at_point.is_main then
        M._lock_worktree_direct(repo_state, worktree_at_point)
      else
        M._lock_worktree(repo_state)
      end
    end)
    :action("u", "Unlock worktree", function(_popup_data)
      if worktree_at_point and worktree_at_point.locked then
        M._unlock_worktree_direct(repo_state, worktree_at_point)
      else
        M._unlock_worktree(repo_state)
      end
    end)
    -- Maintenance
    :group_heading("Maintenance")
    :action("p", "Prune stale", function(_popup_data)
      M._prune_worktrees(repo_state)
    end)
    :build()

  worktree_popup:show()
end

--- Create and show the worktrunk-oriented worktree popup.
--- Shows Switch/Merge/Remove/Steps sections with a "Git Worktree" escape hatch.
---@param repo_state RepoState
---@param context? { worktree: WorktreeEntry }
---@param cfg GitladConfig
function M._open_worktrunk_popup(repo_state, context, cfg)
  local wt = require("gitlad.worktrunk")

  local wt_popup = popup
    .builder()
    :name("Worktrees [worktrunk]")
    -- Switches (Arguments)
    :switch(
      "i",
      "copy-ignored",
      "Copy ignored files on create",
      { persist_key = "wt_copy_ignored" }
    )
    :switch("v", "no-verify", "Skip hooks")
    :switch("y", "yes", "Skip prompts")
    -- Switch actions
    :group_heading("Switch")
    :action("s", "Switch to worktree", function(_popup_data)
      wt.list({ cwd = repo_state.repo_root }, function(infos, err)
        vim.schedule(function()
          if err or not infos or #infos == 0 then
            vim.notify("[gitlad] " .. (err or "No worktrees found"), vim.log.levels.WARN)
            return
          end
          -- Filter out current worktree
          local choices = vim.tbl_filter(function(info)
            return info.path ~= repo_state.repo_root
          end, infos)
          if #choices == 0 then
            vim.notify("[gitlad] No other worktrees to switch to", vim.log.levels.INFO)
            return
          end
          vim.ui.select(choices, {
            prompt = "Switch to worktree:",
            format_item = function(info)
              return info.branch .. "  " .. info.path
            end,
          }, function(info)
            if not info then
              return
            end
            wt.switch(info.branch, { cwd = repo_state.repo_root }, function(ok, e)
              vim.schedule(function()
                if ok then
                  vim.notify("[gitlad] Switched to " .. info.path, vim.log.levels.INFO)
                else
                  vim.notify("[gitlad] wt switch failed: " .. (e or ""), vim.log.levels.ERROR)
                end
              end)
            end)
          end)
        end)
      end)
    end)
    :action("S", "Create + switch", function(popup_data)
      M._wt_create_and_switch(repo_state, popup_data, cfg)
    end)
    -- Merge
    :group_heading("Merge")
    :action("m", "Merge current branch...", function(_popup_data)
      local merge_popup = require("gitlad.popups.worktree_merge")
      merge_popup.open(repo_state)
    end)
    -- Remove
    :group_heading("Remove")
    :action("R", "Remove worktree", function(_popup_data)
      M._wt_remove(repo_state)
    end)
    -- Steps
    :group_heading("Steps")
    :action("ci", "Copy ignored files (run now)", function(_popup_data)
      local target_path = context and context.worktree_path or repo_state.repo_root
      wt.copy_ignored({ cwd = target_path }, function(ok, err)
        vim.schedule(function()
          if ok then
            vim.notify("[gitlad] copy-ignored complete", vim.log.levels.INFO)
          else
            vim.notify("[gitlad] copy-ignored failed: " .. (err or ""), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
    -- Git Worktree escape hatch
    :group_heading("Git Worktree")
    :action("b", "Add worktree", function(popup_data)
      M._add_worktree(repo_state, popup_data)
    end)
    :action("c", "Create branch + worktree", function(popup_data)
      M._add_branch_and_worktree(repo_state, popup_data)
    end)
    :action("k", "Delete", function(popup_data)
      local worktree_at_point = context and context.worktree or nil
      if worktree_at_point and not worktree_at_point.is_main then
        M._delete_worktree_direct(repo_state, worktree_at_point, popup_data)
      else
        M._delete_worktree(repo_state, popup_data)
      end
    end)
    :action("g", "Visit", function(_popup_data)
      local worktree_at_point = context and context.worktree or nil
      if worktree_at_point then
        M._visit_worktree_direct(repo_state, worktree_at_point)
      else
        M._visit_worktree(repo_state)
      end
    end)
    :action("l", "Lock worktree", function(_popup_data)
      local worktree_at_point = context and context.worktree or nil
      if worktree_at_point and not worktree_at_point.is_main then
        M._lock_worktree_direct(repo_state, worktree_at_point)
      else
        M._lock_worktree(repo_state)
      end
    end)
    :action("u", "Unlock worktree", function(_popup_data)
      local worktree_at_point = context and context.worktree or nil
      if worktree_at_point and worktree_at_point.locked then
        M._unlock_worktree_direct(repo_state, worktree_at_point)
      else
        M._unlock_worktree(repo_state)
      end
    end)
    :action("p", "Prune stale", function(_popup_data)
      M._prune_worktrees(repo_state)
    end)
    :build()

  wt_popup:show()
end

--- Switch to a new worktree using wt switch -c
--- After creating, runs wt step copy-ignored if the persistent switch is on
--- or cfg.worktree.copy_ignored_on_create = "always".
---@param repo_state RepoState
---@param popup_data PopupData
---@param cfg GitladConfig
function M._wt_create_and_switch(repo_state, popup_data, cfg)
  vim.ui.input({ prompt = "Create + switch to branch: " }, function(branch)
    if not branch or branch == "" then
      return
    end

    local wt = require("gitlad.worktrunk")

    -- Determine if copy-ignored should run after create
    local copy_ignored_switch = false
    for _, sw in ipairs(popup_data.switches) do
      if sw.cli == "copy-ignored" and sw.enabled then
        copy_ignored_switch = true
        break
      end
    end
    local copy_ignored_always = cfg.worktree.copy_ignored_on_create == "always"
    local should_copy_ignored = copy_ignored_switch or copy_ignored_always

    vim.notify("[gitlad] Creating worktree for branch: " .. branch, vim.log.levels.INFO)

    wt.switch(branch, { cwd = repo_state.repo_root, create = true }, function(ok, err)
      vim.schedule(function()
        if not ok then
          vim.notify("[gitlad] wt switch -c failed: " .. (err or ""), vim.log.levels.ERROR)
          return
        end

        vim.notify("[gitlad] Created worktree for branch: " .. branch, vim.log.levels.INFO)
        repo_state:refresh_status(true)

        if should_copy_ignored then
          -- Determine source branch for copy-ignored
          local from_opt = cfg.worktree.copy_ignored_from
          -- Run copy-ignored from the new worktree (we don't have its path here,
          -- so we run from the main repo cwd; wt will target the new worktree)
          local copy_opts = { cwd = repo_state.repo_root }
          if from_opt == "current" then
            -- "current" means the worktree we're running from
            copy_opts.from = repo_state.repo_root
          end
          -- Note: when from = "trunk", wt uses its default trunk branch
          wt.copy_ignored(copy_opts, function(ci_ok, ci_err)
            vim.schedule(function()
              if ci_ok then
                vim.notify("[gitlad] copy-ignored complete", vim.log.levels.INFO)
              else
                vim.notify("[gitlad] copy-ignored failed: " .. (ci_err or ""), vim.log.levels.WARN)
              end
            end)
          end)
        end
      end)
    end)
  end)
end

--- Remove a worktree using wt remove (prompts with wt list)
---@param repo_state RepoState
function M._wt_remove(repo_state)
  local wt = require("gitlad.worktrunk")
  wt.list({ cwd = repo_state.repo_root }, function(infos, err)
    vim.schedule(function()
      if err or not infos or #infos == 0 then
        vim.notify("[gitlad] " .. (err or "No worktrees found"), vim.log.levels.WARN)
        return
      end
      -- Filter out main worktree
      local choices = vim.tbl_filter(function(info)
        return info.kind ~= "main"
      end, infos)
      if #choices == 0 then
        vim.notify("[gitlad] No linked worktrees to remove", vim.log.levels.INFO)
        return
      end
      vim.ui.select(choices, {
        prompt = "Remove worktree:",
        format_item = function(info)
          return info.branch .. "  " .. info.path
        end,
      }, function(info)
        if not info then
          return
        end
        wt.remove(info.branch, { cwd = repo_state.repo_root }, function(ok, e)
          vim.schedule(function()
            if ok then
              vim.notify("[gitlad] Removed worktree: " .. info.branch, vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify("[gitlad] wt remove failed: " .. (e or ""), vim.log.levels.ERROR)
            end
          end)
        end)
      end)
    end)
  end)
end

--- Add a worktree for an existing branch/commit
---@param repo_state RepoState
---@param popup_data PopupData
function M._add_worktree(repo_state, popup_data)
  -- Step 1: Select branch/commit
  prompt_module.prompt_for_ref({
    prompt = "Checkout in new worktree: ",
    cwd = repo_state.repo_root,
  }, function(ref)
    if not ref or ref == "" then
      return
    end

    -- Step 2: Generate default path based on config strategy
    local cfg = config.get()
    local default_path = ""
    if cfg.worktree.directory_strategy == "sibling" then
      default_path = generate_sibling_path(repo_state.repo_root, ref)
    elseif cfg.worktree.directory_strategy == "sibling-bare" then
      default_path = generate_sibling_bare_path(repo_state.repo_root, ref)
    end

    -- Step 3: Prompt for path (with default if sibling strategy)
    vim.ui.input({
      prompt = "Worktree path: ",
      default = default_path,
      completion = "dir",
    }, function(path)
      if not path or path == "" then
        return
      end

      -- Build args from popup switches
      local args = popup_data:get_arguments()

      -- Duplicate guard
      if pending_ops.is_pending(path) then
        vim.notify("[gitlad] Operation already in progress for this path", vim.log.levels.WARN)
        return
      end

      local done = pending_ops.register(path, "add", "Creating worktree...", repo_state.repo_root)
      vim.notify("[gitlad] Creating worktree...", vim.log.levels.INFO)

      git.worktree_add(
        path,
        ref,
        args,
        { cwd = repo_state.repo_root, timeout = 0 },
        function(success, err)
          vim.schedule(function()
            done()
            if success then
              vim.notify("[gitlad] Worktree created at " .. path, vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              vim.notify(
                "[gitlad] Failed to create worktree: " .. (err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end
      )
    end)
  end)
end

--- Add a worktree with a new branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._add_branch_and_worktree(repo_state, popup_data)
  -- Step 1: Get new branch name
  vim.ui.input({
    prompt = "Create branch: ",
  }, function(branch)
    if not branch or branch == "" then
      return
    end

    -- Step 2: Get starting point (default HEAD)
    prompt_module.prompt_for_ref({
      prompt = "Start point (default HEAD): ",
      cwd = repo_state.repo_root,
      default = "HEAD",
    }, function(start_point)
      -- If empty, use nil (git will default to HEAD)
      local sp = (start_point and start_point ~= "") and start_point or nil

      -- Step 3: Generate default path based on config strategy
      local cfg = config.get()
      local default_path = ""
      if cfg.worktree.directory_strategy == "sibling" then
        default_path = generate_sibling_path(repo_state.repo_root, branch)
      elseif cfg.worktree.directory_strategy == "sibling-bare" then
        default_path = generate_sibling_bare_path(repo_state.repo_root, branch)
      end

      -- Step 4: Prompt for path
      vim.ui.input({
        prompt = "Worktree path: ",
        default = default_path,
        completion = "dir",
      }, function(path)
        if not path or path == "" then
          return
        end

        -- Build args from popup switches (exclude --detach since we're creating a branch)
        local args = {}
        for _, sw in ipairs(popup_data.switches) do
          if sw.enabled and sw.cli ~= "detach" then
            table.insert(args, "--" .. sw.cli)
          end
        end

        -- Duplicate guard
        if pending_ops.is_pending(path) then
          vim.notify("[gitlad] Operation already in progress for this path", vim.log.levels.WARN)
          return
        end

        local done =
          pending_ops.register(path, "add", "Creating branch and worktree...", repo_state.repo_root)
        vim.notify("[gitlad] Creating branch and worktree...", vim.log.levels.INFO)

        git.worktree_add_new_branch(
          path,
          branch,
          sp,
          args,
          { cwd = repo_state.repo_root, timeout = 0 },
          function(success, err)
            vim.schedule(function()
              done()
              if success then
                vim.notify(
                  "[gitlad] Created branch '" .. branch .. "' and worktree at " .. path,
                  vim.log.levels.INFO
                )
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Failed to create branch/worktree: " .. (err or "unknown error"),
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

--- Move a worktree (with selection prompt)
---@param repo_state RepoState
function M._move_worktree(repo_state)
  select_worktree(repo_state, "Move worktree:", false, function(worktree)
    if worktree then
      M._move_worktree_direct(repo_state, worktree)
    end
  end)
end

--- Move a specific worktree
---@param repo_state RepoState
---@param worktree WorktreeEntry
function M._move_worktree_direct(repo_state, worktree)
  if worktree.is_main then
    vim.notify("[gitlad] Cannot move the main worktree", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({
    prompt = "Move worktree to: ",
    default = worktree.path,
    completion = "dir",
  }, function(new_path)
    if not new_path or new_path == "" or new_path == worktree.path then
      return
    end

    local force = worktree.locked

    vim.notify("[gitlad] Moving worktree...", vim.log.levels.INFO)

    git.worktree_move(
      worktree.path,
      new_path,
      force,
      { cwd = repo_state.repo_root },
      function(success, err)
        vim.schedule(function()
          if success then
            vim.notify("[gitlad] Worktree moved to " .. new_path, vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            vim.notify(
              "[gitlad] Failed to move worktree: " .. (err or "unknown error"),
              vim.log.levels.ERROR
            )
          end
        end)
      end
    )
  end)
end

--- Delete a worktree (with selection prompt)
---@param repo_state RepoState
---@param popup_data PopupData
function M._delete_worktree(repo_state, popup_data)
  select_worktree(repo_state, "Delete worktree:", false, function(worktree)
    if worktree then
      M._delete_worktree_direct(repo_state, worktree, popup_data)
    end
  end)
end

--- Delete a specific worktree
---@param repo_state RepoState
---@param worktree WorktreeEntry
---@param popup_data PopupData
function M._delete_worktree_direct(repo_state, worktree, popup_data)
  if worktree.is_main then
    vim.notify("[gitlad] Cannot delete the main worktree", vim.log.levels.ERROR)
    return
  end

  -- Duplicate guard
  if pending_ops.is_pending(worktree.path) then
    vim.notify("[gitlad] Operation already in progress for this worktree", vim.log.levels.WARN)
    return
  end

  -- Check if force flag is set
  local force = false
  for _, sw in ipairs(popup_data.switches) do
    if sw.cli == "force" and sw.enabled then
      force = true
      break
    end
  end

  -- Confirm deletion
  local confirm_msg = "Delete worktree at " .. vim.fn.fnamemodify(worktree.path, ":~") .. "?"
  if worktree.locked then
    confirm_msg = confirm_msg .. " (LOCKED)"
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = confirm_msg,
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    -- If locked or we need force, set force flag
    local use_force = force or worktree.locked

    local done =
      pending_ops.register(worktree.path, "delete", "Deleting worktree...", repo_state.repo_root)
    vim.notify("[gitlad] Deleting worktree...", vim.log.levels.INFO)

    git.worktree_remove(
      worktree.path,
      use_force,
      { cwd = repo_state.repo_root, timeout = 0 },
      function(success, err)
        vim.schedule(function()
          if success then
            done()
            vim.notify("[gitlad] Worktree deleted", vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            -- Check if it failed due to uncommitted changes
            if err and err:match("contains modified") then
              vim.ui.select({ "Yes, force delete", "No" }, {
                prompt = "Worktree has uncommitted changes. Force delete?",
              }, function(force_choice)
                if force_choice == "Yes, force delete" then
                  git.worktree_remove(
                    worktree.path,
                    true,
                    { cwd = repo_state.repo_root, timeout = 0 },
                    function(force_success, force_err)
                      vim.schedule(function()
                        done()
                        if force_success then
                          vim.notify("[gitlad] Worktree force deleted", vim.log.levels.INFO)
                          repo_state:refresh_status(true)
                        else
                          vim.notify(
                            "[gitlad] Failed to delete worktree: " .. (force_err or "unknown error"),
                            vim.log.levels.ERROR
                          )
                        end
                      end)
                    end
                  )
                else
                  -- User cancelled force prompt
                  done()
                end
              end)
            else
              done()
              vim.notify(
                "[gitlad] Failed to delete worktree: " .. (err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end
        end)
      end
    )
  end)
end

--- Visit a worktree (with selection prompt)
---@param repo_state RepoState
function M._visit_worktree(repo_state)
  select_worktree(repo_state, "Visit worktree:", true, function(worktree)
    if worktree then
      M._visit_worktree_direct(repo_state, worktree)
    end
  end)
end

--- Visit a specific worktree (change cwd and open status)
---@param repo_state RepoState
---@param worktree WorktreeEntry
function M._visit_worktree_direct(repo_state, worktree)
  -- Change Neovim's working directory
  vim.cmd("cd " .. vim.fn.fnameescape(worktree.path))

  -- Open gitlad status for the new worktree
  local status_view = require("gitlad.ui.views.status")
  status_view.open()

  vim.notify(
    "[gitlad] Switched to worktree: " .. vim.fn.fnamemodify(worktree.path, ":~"),
    vim.log.levels.INFO
  )
end

--- Lock a worktree (with selection prompt)
---@param repo_state RepoState
function M._lock_worktree(repo_state)
  select_worktree(repo_state, "Lock worktree:", false, function(worktree)
    if worktree then
      M._lock_worktree_direct(repo_state, worktree)
    end
  end)
end

--- Lock a specific worktree
---@param repo_state RepoState
---@param worktree WorktreeEntry
function M._lock_worktree_direct(repo_state, worktree)
  if worktree.is_main then
    vim.notify("[gitlad] Cannot lock the main worktree", vim.log.levels.ERROR)
    return
  end

  if worktree.locked then
    vim.notify("[gitlad] Worktree is already locked", vim.log.levels.INFO)
    return
  end

  vim.ui.input({
    prompt = "Lock reason (optional): ",
  }, function(reason)
    git.worktree_lock(worktree.path, reason, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Worktree locked", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify(
            "[gitlad] Failed to lock worktree: " .. (err or "unknown error"),
            vim.log.levels.ERROR
          )
        end
      end)
    end)
  end)
end

--- Unlock a worktree (with selection prompt)
---@param repo_state RepoState
function M._unlock_worktree(repo_state)
  -- Get locked worktrees only
  git.worktree_list({ cwd = repo_state.repo_root }, function(worktrees, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get worktree list: " .. err, vim.log.levels.ERROR)
        return
      end

      local locked_worktrees = {}
      for _, wt in ipairs(worktrees or {}) do
        if wt.locked then
          table.insert(locked_worktrees, wt)
        end
      end

      if #locked_worktrees == 0 then
        vim.notify("[gitlad] No locked worktrees found", vim.log.levels.INFO)
        return
      end

      local items = format_worktree_list(locked_worktrees, repo_state.repo_root)

      vim.ui.select(items, { prompt = "Unlock worktree:" }, function(choice)
        if not choice then
          return
        end

        local selected = get_worktree_from_display(choice, locked_worktrees)
        if selected then
          M._unlock_worktree_direct(repo_state, selected)
        end
      end)
    end)
  end)
end

--- Unlock a specific worktree
---@param repo_state RepoState
---@param worktree WorktreeEntry
function M._unlock_worktree_direct(repo_state, worktree)
  if not worktree.locked then
    vim.notify("[gitlad] Worktree is not locked", vim.log.levels.INFO)
    return
  end

  git.worktree_unlock(worktree.path, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Worktree unlocked", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify(
          "[gitlad] Failed to unlock worktree: " .. (err or "unknown error"),
          vim.log.levels.ERROR
        )
      end
    end)
  end)
end

--- Prune stale worktrees
---@param repo_state RepoState
function M._prune_worktrees(repo_state)
  -- First do dry run to show what would be pruned
  git.worktree_prune(true, { cwd = repo_state.repo_root }, function(success, output, err)
    vim.schedule(function()
      if not success then
        vim.notify(
          "[gitlad] Failed to check prunable worktrees: " .. (err or "unknown error"),
          vim.log.levels.ERROR
        )
        return
      end

      if not output or output == "" then
        vim.notify("[gitlad] No stale worktrees to prune", vim.log.levels.INFO)
        return
      end

      -- Confirm pruning
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Prune these stale worktrees?\n" .. output,
      }, function(choice)
        if choice ~= "Yes" then
          return
        end

        vim.notify("[gitlad] Pruning stale worktrees...", vim.log.levels.INFO)

        git.worktree_prune(
          false,
          { cwd = repo_state.repo_root },
          function(prune_success, prune_output, prune_err)
            vim.schedule(function()
              if prune_success then
                vim.notify("[gitlad] Stale worktrees pruned", vim.log.levels.INFO)
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Failed to prune worktrees: "
                    .. (prune_err or prune_output or "unknown error"),
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

-- Expose path generation functions for testing
M._generate_sibling_path = generate_sibling_path
M._generate_sibling_bare_path = generate_sibling_bare_path

return M
