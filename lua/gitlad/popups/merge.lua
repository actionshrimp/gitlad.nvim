---@mod gitlad.popups.merge Merge popup
---@brief [[
--- Transient-style merge popup with switches and actions.
--- Shows different actions based on whether a merge is in progress.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class MergeContext
---@field branch string|nil Selected branch to merge

--- Create and show the merge popup
---@param repo_state RepoState
---@param context? MergeContext Optional context with pre-selected branch
function M.open(repo_state, context)
  -- Check if merge is in progress
  git.get_merge_state({ cwd = repo_state.repo_root }, function(state)
    vim.schedule(function()
      if state.merge_in_progress then
        M._open_in_progress_popup(repo_state, state)
      else
        M._open_normal_popup(repo_state, context)
      end
    end)
  end)
end

--- Open popup when merge is NOT in progress
---@param repo_state RepoState
---@param context? MergeContext
function M._open_normal_popup(repo_state, context)
  local merge_popup = popup
    .builder()
    :name("Merge")
    -- Switches (mutually exclusive ff options)
    :switch(
      "f",
      "ff-only",
      "Fast-forward only",
      { exclusive_with = { "no-ff" } }
    )
    :switch("n", "no-ff", "No fast-forward", { exclusive_with = { "ff-only" } })
    :switch("b", "Xignore-space-change", "Ignore whitespace changes", { cli_prefix = "-" })
    :switch("w", "Xignore-all-space", "Ignore all whitespace", { cli_prefix = "-" })
    :switch("S", "gpg-sign", "GPG sign commit")
    -- Options with choices
    :choice_option(
      "s",
      "strategy",
      { "resolve", "recursive", "octopus", "ours", "subtree" },
      "Strategy"
    )
    :choice_option("X", "strategy-option", { "ours", "theirs", "patience" }, "Strategy option")
    :choice_option(
      "A",
      "Xdiff-algorithm",
      { "default", "minimal", "patience", "histogram" },
      "Diff algorithm",
      { cli_prefix = "-", separator = "=" }
    )
    -- Actions
    :group_heading("Merge")
    :action("m", "Merge", function(popup_data)
      M._merge(repo_state, popup_data, context, { edit = false, no_commit = false })
    end)
    :action("e", "Merge, edit message", function(popup_data)
      M._merge(repo_state, popup_data, context, { edit = true, no_commit = false })
    end)
    :action("n", "Merge, don't commit", function(popup_data)
      M._merge(repo_state, popup_data, context, { edit = false, no_commit = true })
    end)
    :action("s", "Squash merge", function(popup_data)
      M._merge(repo_state, popup_data, context, { edit = false, no_commit = false, squash = true })
    end)
    :build()

  merge_popup:show()
end

--- Open popup when merge IS in progress
---@param repo_state RepoState
---@param state MergeState
function M._open_in_progress_popup(repo_state, state)
  local short_oid = state.merge_head_oid and state.merge_head_oid:sub(1, 7) or "unknown"

  local merge_popup = popup
    .builder()
    :name("Merge (in progress: " .. short_oid .. ")")
    -- Actions for in-progress state
    :group_heading("Actions")
    :action("m", "Commit merge", function(_popup_data)
      M._merge_continue(repo_state)
    end)
    :action("a", "Abort merge", function(_popup_data)
      M._merge_abort(repo_state)
    end)
    :build()

  merge_popup:show()
end

--- Get branch to merge (from context or prompt user with branch list)
---@param repo_state RepoState
---@param context? MergeContext
---@param callback fun(branch: string|nil)
local function get_branch_to_merge(repo_state, context, callback)
  if context and context.branch then
    callback(context.branch)
    return
  end

  -- Get list of branches for selection
  git.branches({ cwd = repo_state.repo_root }, function(branches, err)
    if err then
      vim.schedule(function()
        vim.notify("[gitlad] Failed to get branches: " .. err, vim.log.levels.ERROR)
      end)
      callback(nil)
      return
    end

    -- Get remote branches too
    git.remote_branches({ cwd = repo_state.repo_root }, function(remote_branches, remote_err)
      vim.schedule(function()
        local branch_names = {}

        -- Add local branches (excluding current)
        if branches then
          for _, branch in ipairs(branches) do
            if not branch.current then
              table.insert(branch_names, branch.name)
            end
          end
        end

        -- Add remote branches
        if remote_branches and not remote_err then
          for _, branch in ipairs(remote_branches) do
            table.insert(branch_names, branch)
          end
        end

        if #branch_names == 0 then
          vim.notify("[gitlad] No branches to merge", vim.log.levels.INFO)
          callback(nil)
          return
        end

        vim.ui.select(branch_names, {
          prompt = "Branch to merge:",
        }, function(choice)
          callback(choice)
        end)
      end)
    end)
  end)
end

---@class MergeOpts
---@field edit boolean Open editor for merge commit message
---@field no_commit boolean Stage changes but don't commit
---@field squash boolean Squash merge (stage changes, don't commit)

--- Merge a branch
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? MergeContext
---@param opts MergeOpts
function M._merge(repo_state, popup_data, context, opts)
  get_branch_to_merge(repo_state, context, function(branch)
    if not branch then
      return
    end

    local args = popup_data:get_arguments()

    if opts.edit then
      table.insert(args, "--edit")
    else
      table.insert(args, "--no-edit")
    end

    if opts.no_commit then
      table.insert(args, "--no-commit")
    end

    if opts.squash then
      table.insert(args, "--squash")
    end

    local output_mod = require("gitlad.ui.views.output")
    local viewer = output_mod.create({
      title = "Merge",
      command = "git merge " .. table.concat(args, " ") .. " " .. branch,
    })

    vim.notify("[gitlad] Merging " .. branch .. "...", vim.log.levels.INFO)

    git.merge(branch, args, {
      cwd = repo_state.repo_root,
      on_output_line = function(line, is_stderr)
        viewer:append(line, is_stderr)
      end,
    }, function(success, output, err)
      vim.schedule(function()
        viewer:complete(success and 0 or 1)
        if success then
          local msg
          if opts.squash then
            msg = "Squash merged " .. branch .. " (staged, not committed)"
          elseif opts.no_commit then
            msg = "Merged " .. branch .. " (staged, not committed)"
          else
            msg = "Merged " .. branch
          end
          vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          -- Check if this is a conflict
          if err and (err:match("conflict") or err:match("CONFLICT")) then
            vim.notify(
              "[gitlad] Merge has conflicts. Resolve them and press 'm' to commit.",
              vim.log.levels.WARN
            )
          else
            vim.notify("[gitlad] Merge failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
          end
          repo_state:refresh_status(true)
        end
      end)
    end)
  end)
end

--- Continue/finish a merge by committing
---@param repo_state RepoState
function M._merge_continue(repo_state)
  local output_mod = require("gitlad.ui.views.output")
  local viewer = output_mod.create({ title = "Merge", command = "git commit --no-edit" })

  vim.notify("[gitlad] Committing merge...", vim.log.levels.INFO)

  git.merge_continue({
    cwd = repo_state.repo_root,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(success, err)
    vim.schedule(function()
      viewer:complete(success and 0 or 1)
      if success then
        vim.notify("[gitlad] Merge committed", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Commit failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Abort an in-progress merge
---@param repo_state RepoState
function M._merge_abort(repo_state)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Abort merge? This will discard changes.",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    vim.notify("[gitlad] Aborting merge...", vim.log.levels.INFO)

    git.merge_abort({ cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Merge aborted", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Abort failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
