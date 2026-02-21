---@mod gitlad.popups.cherrypick Cherry-pick popup
---@brief [[
--- Transient-style cherry-pick popup with switches, options, and actions.
--- Shows different actions based on whether a cherry-pick is in progress.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class CherryPickContext
---@field commit string|nil Selected commit hash from status buffer

--- Create and show the cherry-pick popup
---@param repo_state RepoState
---@param context? CherryPickContext Optional context with pre-selected commit
function M.open(repo_state, context)
  -- Check if cherry-pick is in progress
  git.get_sequencer_state({ cwd = repo_state.repo_root }, function(state)
    vim.schedule(function()
      if state.cherry_pick_in_progress then
        M._open_in_progress_popup(repo_state, state)
      else
        M._open_normal_popup(repo_state, context)
      end
    end)
  end)
end

--- Open popup when cherry-pick is NOT in progress
---@param repo_state RepoState
---@param context? CherryPickContext
function M._open_normal_popup(repo_state, context)
  local cherrypick_popup = popup
    .builder()
    :name("Cherry-pick")
    -- Switches
    :switch("x", "x", "Add 'cherry picked from' reference", { cli_prefix = "-" })
    :switch("e", "edit", "Edit commit message")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("f", "ff", "Attempt fast-forward if possible")
    -- Options
    :option("m", "mainline", "", "Mainline parent number (for merge commits)")
    -- Actions
    :group_heading("Cherry-pick")
    :action("A", "Pick", function(popup_data)
      M._cherry_pick(repo_state, popup_data, context, false)
    end)
    :action("a", "Apply (no commit)", function(popup_data)
      M._cherry_pick(repo_state, popup_data, context, true)
    end)
    :build()

  cherrypick_popup:show()
end

--- Open popup when cherry-pick IS in progress
---@param repo_state RepoState
---@param state SequencerState
function M._open_in_progress_popup(repo_state, state)
  local short_oid = state.sequencer_head_oid and state.sequencer_head_oid:sub(1, 7) or "unknown"

  local cherrypick_popup = popup
    .builder()
    :name("Cherry-pick (in progress: " .. short_oid .. ")")
    -- Actions for in-progress state
    :group_heading("Sequencer")
    :action("A", "Continue", function(_popup_data)
      M._cherry_pick_continue(repo_state)
    end)
    :action("s", "Skip", function(_popup_data)
      M._cherry_pick_skip(repo_state)
    end)
    :action("a", "Abort", function(_popup_data)
      M._cherry_pick_abort(repo_state)
    end)
    :build()

  cherrypick_popup:show()
end

--- Get commit to cherry-pick (from context or prompt user)
---@param context? CherryPickContext
---@param callback fun(commits: string[]|nil)
local function get_commits_to_pick(context, callback)
  if context and context.commit then
    callback({ context.commit })
    return
  end

  -- Prompt user for commit hash
  vim.ui.input({
    prompt = "Commit to cherry-pick: ",
  }, function(input)
    if not input or input == "" then
      callback(nil)
      return
    end
    callback({ input })
  end)
end

--- Cherry-pick commits
---@param repo_state RepoState
---@param popup_data PopupData
---@param context? CherryPickContext
---@param no_commit boolean Whether to use --no-commit flag
function M._cherry_pick(repo_state, popup_data, context, no_commit)
  get_commits_to_pick(context, function(commits)
    if not commits then
      return
    end

    local args = popup_data:get_arguments()
    if no_commit then
      table.insert(args, "--no-commit")
    end

    local output_mod = require("gitlad.ui.views.output")
    local viewer = output_mod.create({
      title = "Cherry-pick",
      command = "git cherry-pick " .. table.concat(args, " ") .. " " .. table.concat(commits, " "),
    })

    vim.notify("[gitlad] Cherry-picking...", vim.log.levels.INFO)

    git.cherry_pick(commits, args, {
      cwd = repo_state.repo_root,
      on_output_line = function(line, is_stderr)
        viewer:append(line, is_stderr)
      end,
    }, function(success, output, err)
      vim.schedule(function()
        viewer:complete(success and 0 or 1)
        if success then
          local msg = no_commit and "Cherry-picked (staged)" or "Cherry-picked commit"
          vim.notify("[gitlad] " .. msg, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          -- Check if this is a conflict
          if err and err:match("conflict") then
            vim.notify(
              "[gitlad] Cherry-pick has conflicts. Resolve them and press A to continue.",
              vim.log.levels.WARN
            )
          else
            vim.notify(
              "[gitlad] Cherry-pick failed: " .. (err or "unknown error"),
              vim.log.levels.ERROR
            )
          end
          repo_state:refresh_status(true)
        end
      end)
    end)
  end)
end

--- Continue an in-progress cherry-pick
---@param repo_state RepoState
function M._cherry_pick_continue(repo_state)
  local output_mod = require("gitlad.ui.views.output")
  local viewer =
    output_mod.create({ title = "Cherry-pick", command = "git cherry-pick --continue" })

  vim.notify("[gitlad] Continuing cherry-pick...", vim.log.levels.INFO)

  git.cherry_pick_continue({
    cwd = repo_state.repo_root,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(success, err)
    vim.schedule(function()
      viewer:complete(success and 0 or 1)
      if success then
        vim.notify("[gitlad] Cherry-pick continued", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Continue failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Skip the current commit during cherry-pick
---@param repo_state RepoState
function M._cherry_pick_skip(repo_state)
  vim.notify("[gitlad] Skipping commit...", vim.log.levels.INFO)

  git.cherry_pick_skip({ cwd = repo_state.repo_root }, function(success, err)
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

--- Abort an in-progress cherry-pick
---@param repo_state RepoState
function M._cherry_pick_abort(repo_state)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Abort cherry-pick? This will discard changes.",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    vim.notify("[gitlad] Aborting cherry-pick...", vim.log.levels.INFO)

    git.cherry_pick_abort({ cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Cherry-pick aborted", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Abort failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
