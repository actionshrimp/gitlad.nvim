---@mod gitlad.popups.revert Revert popup
---@brief [[
--- Transient-style revert popup with switches, options, and actions.
--- Shows different actions based on whether a revert is in progress.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class RevertContext
---@field commit string|nil Selected commit hash from status buffer

--- Create and show the revert popup
---@param repo_state RepoState
---@param context? RevertContext Optional context with pre-selected commit
function M.open(repo_state, context)
  -- Check if revert is in progress
  git.get_sequencer_state({ cwd = repo_state.repo_root }, function(state)
    vim.schedule(function()
      if state.revert_in_progress then
        M._open_in_progress_popup(repo_state, state)
      else
        M._open_normal_popup(repo_state, context)
      end
    end)
  end)
end

--- Open popup when revert is NOT in progress
---@param repo_state RepoState
---@param context? RevertContext
function M._open_normal_popup(repo_state, context)
  local revert_popup = popup
    .builder()
    :name("Revert")
    -- Switches
    :switch("e", "edit", "Edit commit message", { enabled = true })
    :switch("E", "no-edit", "Don't edit commit message")
    :switch("s", "signoff", "Add Signed-off-by line")
    -- Options
    :option("m", "mainline", "", "Mainline parent number (for merge commits)")
    -- Actions
    :group_heading("Revert")
    :action("V", "Revert", function(popup_data)
      M._revert(repo_state, popup_data, context, false)
    end)
    :action("v", "Revert changes (no commit)", function(popup_data)
      M._revert(repo_state, popup_data, context, true)
    end)
    :build()

  revert_popup:show()
end

--- Open popup when revert IS in progress
---@param repo_state RepoState
---@param state SequencerState
function M._open_in_progress_popup(repo_state, state)
  local short_oid = state.sequencer_head_oid and state.sequencer_head_oid:sub(1, 7) or "unknown"

  local revert_popup = popup
    .builder()
    :name("Revert (in progress: " .. short_oid .. ")")
    -- Actions for in-progress state
    :group_heading("Sequencer")
    :action("V", "Continue", function(_popup_data)
      M._revert_continue(repo_state)
    end)
    :action("s", "Skip", function(_popup_data)
      M._revert_skip(repo_state)
    end)
    :action("a", "Abort", function(_popup_data)
      M._revert_abort(repo_state)
    end)
    :build()

  revert_popup:show()
end

--- Get commit to revert (from context or prompt user)
---@param context? RevertContext
---@param callback fun(commits: string[]|nil)
local function get_commits_to_revert(context, callback)
  if context and context.commit then
    callback({ context.commit })
    return
  end

  -- Prompt user for commit hash
  vim.ui.input({
    prompt = "Commit to revert: ",
  }, function(input)
    if not input or input == "" then
      callback(nil)
      return
    end
    callback({ input })
  end)
end

--- Revert commits
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? RevertContext
---@param no_commit boolean Whether to use --no-commit flag
function M._revert(repo_state, popup_data, context, no_commit)
  get_commits_to_revert(context, function(commits)
    if not commits then
      return
    end

    local args = popup_data:get_arguments()
    if no_commit then
      table.insert(args, "--no-commit")
    end

    local output_mod = require("gitlad.ui.views.output")
    local viewer = output_mod.create({
      title = "Revert",
      command = "git revert " .. table.concat(args, " ") .. " " .. table.concat(commits, " "),
    })

    vim.notify("[gitlad] Reverting...", vim.log.levels.INFO)

    git.revert(commits, args, {
      cwd = repo_state.repo_root,
      on_output_line = function(line, is_stderr)
        viewer:append(line, is_stderr)
      end,
    }, function(success, output, err)
      vim.schedule(function()
        viewer:complete(success and 0 or 1)
        if success then
          local msg = no_commit and "Reverted (staged)" or "Reverted commit"
          vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          -- Check if this is a conflict
          if err and err:match("conflict") then
            vim.notify(
              "[gitlad] Revert has conflicts. Resolve them and press V to continue.",
              vim.log.levels.WARN
            )
          else
            vim.notify("[gitlad] Revert failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
          end
          repo_state:refresh_status(true)
        end
      end)
    end)
  end)
end

--- Continue an in-progress revert
---@param repo_state RepoState
function M._revert_continue(repo_state)
  local output_mod = require("gitlad.ui.views.output")
  local viewer = output_mod.create({ title = "Revert", command = "git revert --continue" })

  vim.notify("[gitlad] Continuing revert...", vim.log.levels.INFO)

  git.revert_continue({
    cwd = repo_state.repo_root,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(success, err)
    vim.schedule(function()
      viewer:complete(success and 0 or 1)
      if success then
        vim.notify("[gitlad] Revert continued", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Continue failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Skip the current commit during revert
---@param repo_state RepoState
function M._revert_skip(repo_state)
  vim.notify("[gitlad] Skipping commit...", vim.log.levels.INFO)

  git.revert_skip({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Skipped commit", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Skip failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Abort an in-progress revert
---@param repo_state RepoState
function M._revert_abort(repo_state)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Abort revert? This will discard changes.",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    vim.notify("[gitlad] Aborting revert...", vim.log.levels.INFO)

    git.revert_abort({ cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Revert aborted", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Abort failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
