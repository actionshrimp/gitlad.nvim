---@mod gitlad.popups.rebase Rebase popup
---@brief [[
--- Transient-style rebase popup with switches, options, and actions.
--- Follows magit rebase popup patterns with evil-collection keybindings.
---
--- Actions for "Rebase <branch> onto":
--- - `p` - Rebase onto pushremote
--- - `u` - Rebase onto upstream
--- - `e` - Rebase elsewhere (prompts for branch)
---
--- Actions when rebase is in progress:
--- - `r` - Continue
--- - `s` - Skip
--- - `a` - Abort
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")
local client = require("gitlad.client")

--- Extract remote name from ref (e.g., "origin/main" -> "origin")
---@param ref string|nil
---@return string|nil
local function get_remote_from_ref(ref)
  if not ref then
    return nil
  end
  return ref:match("^([^/]+)/")
end

--- Get the push remote for the current branch
--- Returns the remote that would be used for pushing (may differ from upstream)
---@param status GitStatusResult|nil
---@return string|nil remote Remote name like "origin"
local function get_push_remote(status)
  if not status then
    return nil
  end

  -- Use explicitly calculated push_remote if available
  if status.push_remote then
    return get_remote_from_ref(status.push_remote)
  end

  -- Fall back to deriving from upstream
  if status.upstream then
    return get_remote_from_ref(status.upstream)
  end

  return nil
end

--- Build rebase arguments from popup state
---@param popup_data PopupData
---@return string[]
local function build_rebase_args(popup_data)
  local args = popup_data:get_arguments()
  return args
end

--- Open or focus the status buffer
---@param repo_state RepoState
local function open_status_buffer(repo_state)
  local status_view = require("gitlad.ui.views.status")
  -- This will open a new window if needed, or focus existing one
  status_view.open(repo_state)
end

--- Execute rebase operation
---@param repo_state RepoState
---@param target string Target ref to rebase onto
---@param args string[]
local function do_rebase(repo_state, target, args)
  -- Check if interactive mode is enabled
  local is_interactive = vim.tbl_contains(args, "--interactive") or vim.tbl_contains(args, "-i")

  -- Build options with potential custom editor env for interactive rebase
  local opts = { cwd = repo_state.repo_root }
  if is_interactive then
    -- Use our custom editor for interactive rebase
    opts.env = client.get_envs_git_editor()
  end

  vim.notify("[gitlad] Rebasing onto " .. target .. "...", vim.log.levels.INFO)

  git.rebase(target, args, opts, function(success, output, err)
    vim.schedule(function()
      -- Open/focus the status buffer first
      open_status_buffer(repo_state)

      if success then
        vim.notify("[gitlad] Rebase complete", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        -- Check if rebase is in progress (conflicts)
        if git.rebase_in_progress({ cwd = repo_state.repo_root }) then
          vim.notify(
            "[gitlad] Rebase stopped - resolve conflicts and use rebase popup to continue",
            vim.log.levels.WARN
          )
        else
          vim.notify("[gitlad] Rebase failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Create and show the rebase popup (normal mode - no rebase in progress)
---@param repo_state RepoState
---@param context? { commit: string } Context with commit at point
local function show_normal_popup(repo_state, context)
  local status = repo_state.status
  local branch = status and status.branch or "HEAD"

  -- Build dynamic description showing current branch
  local heading = string.format("Rebase %s onto", branch)

  -- Show commit at point in heading if available
  local commit_info = ""
  if context and context.commit then
    commit_info = string.format(" (from %s)", context.commit:sub(1, 7))
  end

  local rebase_popup = popup
    .builder()
    :name("Rebase")
    -- Switches (following magit defaults)
    :switch(
      "A",
      "autostash",
      "Autostash",
      { enabled = true }
    )
    :switch("k", "keep-empty", "Keep empty commits")
    :switch("a", "autosquash", "Autosquash")
    -- Actions
    :group_heading(heading .. commit_info)
    :action("p", "pushremote", function(popup_data)
      M._rebase_pushremote(repo_state, popup_data)
    end)
    :action("u", "upstream", function(popup_data)
      M._rebase_upstream(repo_state, popup_data)
    end)
    :action("e", "elsewhere", function(popup_data)
      M._rebase_elsewhere(repo_state, popup_data)
    end)
    :action("i", "interactively", function(popup_data)
      M._rebase_interactive(repo_state, popup_data, context)
    end)
    :build()

  rebase_popup:show()
end

--- Create and show the rebase popup (in-progress mode)
---@param repo_state RepoState
local function show_in_progress_popup(repo_state)
  local rebase_popup = popup
    .builder()
    :name("Rebase")
    -- No switches when rebase is in progress
    :group_heading("Actions")
    :action("r", "Continue", function(_popup_data)
      M._rebase_continue(repo_state)
    end)
    :action("s", "Skip", function(_popup_data)
      M._rebase_skip(repo_state)
    end)
    :action("a", "Abort", function(_popup_data)
      M._rebase_abort(repo_state)
    end)
    :build()

  rebase_popup:show()
end

--- Create and show the rebase popup
--- Shows different UI depending on whether a rebase is in progress
---@param repo_state RepoState
---@param context? { commit: string } Context with commit at point
function M.open(repo_state, context)
  if git.rebase_in_progress({ cwd = repo_state.repo_root }) then
    show_in_progress_popup(repo_state)
  else
    show_normal_popup(repo_state, context)
  end
end

--- Rebase onto pushremote (the remote used for pushing)
--- In triangular workflow, this rebases onto your fork's version of the branch
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_pushremote(repo_state, popup_data)
  local status = repo_state.status

  -- Get push remote
  local remote = get_push_remote(status)
  if not remote or remote == "" then
    vim.notify(
      "[gitlad] No push remote configured. Use 'e' to rebase elsewhere.",
      vim.log.levels.WARN
    )
    return
  end

  -- Build target: remote/branch
  local branch = status and status.branch
  if not branch then
    vim.notify("[gitlad] Cannot determine current branch.", vim.log.levels.WARN)
    return
  end

  local target = remote .. "/" .. branch
  local args = build_rebase_args(popup_data)
  do_rebase(repo_state, target, args)
end

--- Rebase onto upstream (the configured tracking branch)
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_upstream(repo_state, popup_data)
  local status = repo_state.status

  -- Check if we have an upstream configured
  if not status or not status.upstream then
    vim.notify(
      "[gitlad] No upstream configured. Use 'e' to rebase elsewhere, or set upstream with `git branch --set-upstream-to`.",
      vim.log.levels.WARN
    )
    return
  end

  local args = build_rebase_args(popup_data)
  do_rebase(repo_state, status.upstream, args)
end

--- Rebase elsewhere (prompts for target branch)
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_elsewhere(repo_state, popup_data)
  -- Get list of branches (local and remote)
  git.remote_branches({ cwd = repo_state.repo_root }, function(remote_branches, remote_err)
    vim.schedule(function()
      if remote_err then
        vim.notify("[gitlad] Failed to get remote branches: " .. remote_err, vim.log.levels.ERROR)
        return
      end

      git.branches({ cwd = repo_state.repo_root }, function(local_branches, local_err)
        vim.schedule(function()
          if local_err then
            vim.notify("[gitlad] Failed to get local branches: " .. local_err, vim.log.levels.ERROR)
            return
          end

          -- Build list of all branches
          local branches = {}

          -- Add remote branches first (more common rebase targets)
          if remote_branches then
            for _, b in ipairs(remote_branches) do
              table.insert(branches, b)
            end
          end

          -- Add local branches
          if local_branches then
            for _, b in ipairs(local_branches) do
              if not b.current then
                table.insert(branches, b.name)
              end
            end
          end

          if #branches == 0 then
            vim.notify("[gitlad] No branches found", vim.log.levels.WARN)
            return
          end

          vim.ui.select(branches, {
            prompt = "Rebase onto:",
          }, function(choice)
            if not choice then
              return
            end

            local args = build_rebase_args(popup_data)
            do_rebase(repo_state, choice, args)
          end)
        end)
      end)
    end)
  end)
end

--- Continue an in-progress rebase
---@param repo_state RepoState
function M._rebase_continue(repo_state)
  vim.notify("[gitlad] Continuing rebase...", vim.log.levels.INFO)

  git.rebase_continue({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        -- Check if rebase is complete or still in progress
        if git.rebase_in_progress({ cwd = repo_state.repo_root }) then
          vim.notify("[gitlad] Rebase continued - more commits to process", vim.log.levels.INFO)
        else
          vim.notify("[gitlad] Rebase complete", vim.log.levels.INFO)
        end
        repo_state:refresh_status(true)
      else
        vim.notify(
          "[gitlad] Rebase continue failed: " .. (err or "unknown error"),
          vim.log.levels.ERROR
        )
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Skip the current commit during rebase
---@param repo_state RepoState
function M._rebase_skip(repo_state)
  vim.notify("[gitlad] Skipping commit...", vim.log.levels.INFO)

  git.rebase_skip({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        -- Check if rebase is complete or still in progress
        if git.rebase_in_progress({ cwd = repo_state.repo_root }) then
          vim.notify("[gitlad] Commit skipped - more commits to process", vim.log.levels.INFO)
        else
          vim.notify("[gitlad] Rebase complete", vim.log.levels.INFO)
        end
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Skip failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Abort the current rebase
---@param repo_state RepoState
function M._rebase_abort(repo_state)
  vim.notify("[gitlad] Aborting rebase...", vim.log.levels.INFO)

  git.rebase_abort({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Rebase aborted", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Abort failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Transform a commit reference for interactive rebase to include the selected commit.
--- Git's `rebase -i <commit>` rebases commits AFTER the specified commit (exclusive).
--- By appending `^` (parent), we make it inclusive of the selected commit.
--- This matches magit's default behavior (magit-rebase-interactive-include-selected = t).
---@param commit string The commit hash or ref
---@return string The transformed commit ref with ^ appended
function M._include_commit_in_rebase(commit)
  return commit .. "^"
end

--- Start an interactive rebase
--- If a commit is at point, uses that as the target (rebases commits after it)
--- Otherwise prompts for a commit to rebase from
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? { commit: string } Context with commit at point
function M._rebase_interactive(repo_state, popup_data, context)
  local args = build_rebase_args(popup_data)
  -- Always add --interactive for this action
  if not vim.tbl_contains(args, "--interactive") then
    table.insert(args, "--interactive")
  end

  -- If we have a commit at point, use it as the target
  if context and context.commit then
    do_rebase(repo_state, M._include_commit_in_rebase(context.commit), args)
    return
  end

  -- Otherwise, prompt for a commit using commit selector
  local commit_select = require("gitlad.ui.views.commit_select")
  commit_select.open(repo_state, function(commit)
    if commit then
      do_rebase(repo_state, commit.hash, args)
    end
  end, { prompt = "Interactive rebase from" })
end

return M
