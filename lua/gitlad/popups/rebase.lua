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
  local onto_heading = string.format("Rebase %s onto", branch)

  -- Build dynamic labels for rebase targets (like magit)
  -- When configured: show the actual ref (e.g., "origin/feature-branch")
  -- When not configured: show explanatory text
  local pushremote_label = "pushRemote, setting that"
  local upstream_label = "@{upstream}, setting it"

  if status then
    -- Get the effective push target (handles fallback from push_remote to upstream-derived)
    local push_ref, _ = get_push_target(status)
    if push_ref then
      pushremote_label = push_ref
    end

    -- Check if upstream is configured
    if status.upstream then
      upstream_label = status.upstream
    end
  end

  local rebase_popup = popup
    .builder()
    :name("Rebase")
    -- Arguments section (following magit)
    :switch("k", "keep-empty", "Keep empty commits")
    :switch("r", "rebase-merges", "Rebase merges")
    :switch("u", "update-refs", "Update branches")
    :switch("d", "committer-date-is-author-date", "Use author date as committer date")
    :switch("t", "ignore-date", "Use current time as author date")
    :switch("a", "autosquash", "Autosquash")
    :switch("A", "autostash", "Autostash", { enabled = true })
    :switch("i", "interactive", "Interactive")
    :switch("h", "no-verify", "Disable hooks")
    -- Rebase <branch> onto section
    :group_heading(onto_heading)
    :action("p", pushremote_label, function(popup_data)
      M._rebase_pushremote(repo_state, popup_data)
    end)
    :action("u", upstream_label, function(popup_data)
      M._rebase_upstream(repo_state, popup_data)
    end)
    :action("e", "elsewhere", function(popup_data)
      M._rebase_elsewhere(repo_state, popup_data)
    end)
    -- Rebase section
    :group_heading("Rebase")
    :action("i", "interactively", function(popup_data)
      M._rebase_interactive(repo_state, popup_data, context)
    end)
    :action("s", "a subset", function(popup_data)
      M._rebase_subset(repo_state, popup_data)
    end)
    :action("m", "to modify a commit", function(popup_data)
      M._rebase_modify(repo_state, popup_data, context)
    end)
    :action("w", "to reword a commit", function(popup_data)
      M._rebase_reword(repo_state, popup_data, context)
    end)
    :action("k", "to remove a commit", function(popup_data)
      M._rebase_remove(repo_state, popup_data, context)
    end)
    :action("f", "to autosquash", function(popup_data)
      M._rebase_autosquash(repo_state, popup_data)
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
--- Like magit's "p" action: rebases onto pushRemote and sets it if needed
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_pushremote(repo_state, popup_data)
  local status = repo_state.status
  if not status or not status.branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  local branch = status.branch
  local opts = { cwd = repo_state.repo_root }

  -- Get the effective push remote (explicit pushRemote or fallback to pushDefault)
  git.get_push_remote(branch, opts, function(push_remote_name, _err)
    vim.schedule(function()
      if push_remote_name and push_remote_name ~= "" then
        -- Push remote is configured, rebase onto it
        local target = push_remote_name .. "/" .. branch
        local args = build_rebase_args(popup_data)
        do_rebase(repo_state, target, args)
      else
        -- No push remote configured, prompt user to select one
        git.remote_names(opts, function(remotes, rem_err)
          vim.schedule(function()
            if rem_err or not remotes or #remotes == 0 then
              vim.notify("[gitlad] No remotes configured", vim.log.levels.WARN)
              return
            end

            local prompt_text = "Set branch." .. branch .. ".pushRemote and rebase there"
            vim.ui.select(remotes, { prompt = prompt_text .. ":" }, function(choice)
              if not choice then
                return
              end

              -- Set the pushRemote config
              git.set_push_remote(branch, choice, opts, function(success, set_err)
                vim.schedule(function()
                  if success then
                    -- Now rebase onto that remote
                    local target = choice .. "/" .. branch
                    local args = build_rebase_args(popup_data)
                    do_rebase(repo_state, target, args)
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

--- Rebase onto upstream (the configured tracking branch)
--- Like magit's "u" action: rebases onto upstream and sets it if needed
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_upstream(repo_state, popup_data)
  local status = repo_state.status
  if not status or not status.branch then
    vim.notify("[gitlad] No current branch", vim.log.levels.ERROR)
    return
  end

  local branch = status.branch
  local opts = { cwd = repo_state.repo_root }

  -- Check if we have an upstream configured
  if status.upstream then
    local args = build_rebase_args(popup_data)
    do_rebase(repo_state, status.upstream, args)
    return
  end

  -- No upstream configured, prompt user to set it
  M._configure_and_rebase_upstream(repo_state, popup_data, branch)
end

--- Configure upstream and rebase (when upstream is not set)
---@param repo_state RepoState
---@param popup_data PopupData
---@param branch string Current branch name
function M._configure_and_rebase_upstream(repo_state, popup_data, branch)
  local opts = { cwd = repo_state.repo_root }

  -- Use the prompt module for ref completion
  local prompt_module = require("gitlad.utils.prompt")
  prompt_module.prompt_for_ref({
    prompt = "Set upstream of " .. branch .. " and rebase: ",
    cwd = repo_state.repo_root,
  }, function(upstream)
    if not upstream or upstream == "" then
      return
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

        -- Now rebase onto the newly configured upstream
        local args = build_rebase_args(popup_data)
        do_rebase(repo_state, upstream, args)
      end)
    end)
  end)
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

  -- Pass git editor environment for commit message editing during conflict resolution
  -- When conflicts are resolved, git may want to open an editor to confirm/edit the commit message
  local opts = {
    cwd = repo_state.repo_root,
    env = client.get_envs_git_editor(),
  }

  git.rebase_continue(opts, function(success, err)
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

  -- Otherwise, prompt for a ref (accepts any ref: SHA, branch, HEAD~n, etc.)
  local prompt_module = require("gitlad.utils.prompt")
  prompt_module.prompt_for_ref({ prompt = "Interactive rebase from: " }, function(ref)
    if ref then
      do_rebase(repo_state, M._include_commit_in_rebase(ref), args)
    end
  end)
end

--- Rebase a subset of commits (prompts for start and end)
--- Uses git rebase --onto <newbase> <start> <end>
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_subset(repo_state, popup_data)
  local prompt_module = require("gitlad.utils.prompt")

  -- First, prompt for the newbase (where to rebase onto)
  prompt_module.prompt_for_ref({
    prompt = "Rebase subset onto: ",
    cwd = repo_state.repo_root,
  }, function(newbase)
    if not newbase or newbase == "" then
      return
    end

    -- Then prompt for the start commit (exclusive - commits after this)
    prompt_module.prompt_for_ref({
      prompt = "Start of subset (exclusive): ",
      cwd = repo_state.repo_root,
    }, function(start_commit)
      if not start_commit or start_commit == "" then
        return
      end

      -- Finally prompt for the end commit (inclusive - up to and including this)
      prompt_module.prompt_for_ref({
        prompt = "End of subset (inclusive): ",
        cwd = repo_state.repo_root,
      }, function(end_commit)
        if not end_commit or end_commit == "" then
          return
        end

        -- Use git rebase --onto newbase start end
        -- The git.rebase function builds: git rebase [args] [target]
        -- So we pass: args = [popup_args, "--onto", newbase, start_commit], target = end_commit
        local args = build_rebase_args(popup_data)
        table.insert(args, "--onto")
        table.insert(args, newbase)
        table.insert(args, start_commit)

        -- Check if interactive mode is enabled
        local is_interactive = vim.tbl_contains(args, "--interactive")
          or vim.tbl_contains(args, "-i")

        local opts = { cwd = repo_state.repo_root }
        if is_interactive then
          opts.env = client.get_envs_git_editor()
        end

        vim.notify("[gitlad] Rebasing subset onto " .. newbase .. "...", vim.log.levels.INFO)

        git.rebase(end_commit, args, opts, function(success, output, err)
          vim.schedule(function()
            open_status_buffer(repo_state)

            if success then
              vim.notify("[gitlad] Rebase complete", vim.log.levels.INFO)
              repo_state:refresh_status(true)
            else
              if git.rebase_in_progress({ cwd = repo_state.repo_root }) then
                vim.notify(
                  "[gitlad] Rebase stopped - resolve conflicts and use rebase popup to continue",
                  vim.log.levels.WARN
                )
              else
                vim.notify(
                  "[gitlad] Rebase failed: " .. (err or "unknown error"),
                  vim.log.levels.ERROR
                )
              end
              repo_state:refresh_status(true)
            end
          end)
        end)
      end)
    end)
  end)
end

--- Modify a commit (interactive rebase with "edit" action)
--- This stops at the commit for amending
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? { commit: string } Context with commit at point
function M._rebase_modify(repo_state, popup_data, context)
  local function do_modify(commit)
    -- Create a temporary script that changes "pick" to "edit" for the target commit
    -- Use GIT_SEQUENCE_EDITOR to modify the todo list
    local args = build_rebase_args(popup_data)
    if not vim.tbl_contains(args, "--interactive") then
      table.insert(args, "--interactive")
    end

    local opts = {
      cwd = repo_state.repo_root,
      env = {
        -- Use sed to change "pick <hash>" to "edit <hash>" for the first line only
        GIT_SEQUENCE_EDITOR = "sed -i.bak '1s/^pick/edit/'",
      },
    }

    vim.notify(
      "[gitlad] Starting rebase to modify " .. commit:sub(1, 7) .. "...",
      vim.log.levels.INFO
    )
    do_rebase(repo_state, M._include_commit_in_rebase(commit), args)
  end

  if context and context.commit then
    do_modify(context.commit)
    return
  end

  local prompt_module = require("gitlad.utils.prompt")
  prompt_module.prompt_for_ref({
    prompt = "Modify commit: ",
    cwd = repo_state.repo_root,
  }, function(ref)
    if ref then
      do_modify(ref)
    end
  end)
end

--- Reword a commit (interactive rebase with "reword" action)
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? { commit: string } Context with commit at point
function M._rebase_reword(repo_state, popup_data, context)
  local function do_reword(commit)
    local args = build_rebase_args(popup_data)
    if not vim.tbl_contains(args, "--interactive") then
      table.insert(args, "--interactive")
    end

    -- For reword, we need to use GIT_SEQUENCE_EDITOR to change the action
    local opts = {
      cwd = repo_state.repo_root,
      env = vim.tbl_extend("force", client.get_envs_git_editor(), {
        GIT_SEQUENCE_EDITOR = "sed -i.bak '1s/^pick/reword/'",
      }),
    }

    vim.notify(
      "[gitlad] Starting rebase to reword " .. commit:sub(1, 7) .. "...",
      vim.log.levels.INFO
    )

    git.rebase(M._include_commit_in_rebase(commit), args, opts, function(success, output, err)
      vim.schedule(function()
        open_status_buffer(repo_state)

        if success then
          vim.notify("[gitlad] Rebase complete", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
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

  if context and context.commit then
    do_reword(context.commit)
    return
  end

  local prompt_module = require("gitlad.utils.prompt")
  prompt_module.prompt_for_ref({
    prompt = "Reword commit: ",
    cwd = repo_state.repo_root,
  }, function(ref)
    if ref then
      do_reword(ref)
    end
  end)
end

--- Remove a commit (interactive rebase with "drop" action)
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? { commit: string } Context with commit at point
function M._rebase_remove(repo_state, popup_data, context)
  local function do_remove(commit)
    local args = build_rebase_args(popup_data)
    if not vim.tbl_contains(args, "--interactive") then
      table.insert(args, "--interactive")
    end

    local opts = {
      cwd = repo_state.repo_root,
      env = {
        GIT_SEQUENCE_EDITOR = "sed -i.bak '1s/^pick/drop/'",
      },
    }

    vim.notify(
      "[gitlad] Starting rebase to remove " .. commit:sub(1, 7) .. "...",
      vim.log.levels.INFO
    )

    git.rebase(M._include_commit_in_rebase(commit), args, opts, function(success, output, err)
      vim.schedule(function()
        open_status_buffer(repo_state)

        if success then
          vim.notify("[gitlad] Commit removed", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
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

  if context and context.commit then
    do_remove(context.commit)
    return
  end

  local prompt_module = require("gitlad.utils.prompt")
  prompt_module.prompt_for_ref({
    prompt = "Remove commit: ",
    cwd = repo_state.repo_root,
  }, function(ref)
    if ref then
      do_remove(ref)
    end
  end)
end

--- Autosquash rebase (rebases with --autosquash)
--- Automatically reorders and applies fixup!/squash! commits
---@param repo_state RepoState
---@param popup_data PopupData
function M._rebase_autosquash(repo_state, popup_data)
  local prompt_module = require("gitlad.utils.prompt")

  prompt_module.prompt_for_ref({
    prompt = "Autosquash rebase from: ",
    cwd = repo_state.repo_root,
  }, function(ref)
    if not ref or ref == "" then
      return
    end

    local args = build_rebase_args(popup_data)
    -- Always add --autosquash for this action
    if not vim.tbl_contains(args, "--autosquash") then
      table.insert(args, "--autosquash")
    end
    -- Autosquash requires interactive mode
    if not vim.tbl_contains(args, "--interactive") then
      table.insert(args, "--interactive")
    end

    local opts = {
      cwd = repo_state.repo_root,
      env = {
        -- Use true to auto-accept the todo list (non-interactive autosquash)
        GIT_SEQUENCE_EDITOR = "true",
      },
    }

    vim.notify("[gitlad] Running autosquash rebase...", vim.log.levels.INFO)

    git.rebase(M._include_commit_in_rebase(ref), args, opts, function(success, output, err)
      vim.schedule(function()
        open_status_buffer(repo_state)

        if success then
          vim.notify("[gitlad] Autosquash rebase complete", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
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
  end)
end

return M
