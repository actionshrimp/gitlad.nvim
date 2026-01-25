---@mod gitlad.popups.commit Commit popup
---@brief [[
--- Transient-style commit popup with switches, options, and actions.
--- Follows magit commit popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")

---@class CommitPopupContext
---@field repo_state RepoState
---@field popup PopupData

--- Create and show the commit popup
---@param repo_state RepoState
function M.open(repo_state)
  local commit_popup = popup
    .builder()
    :name("Commit")
    -- Switches
    :switch("a", "all", "Stage all modified and deleted files")
    :switch("e", "allow-empty", "Allow empty commit")
    :switch("v", "verbose", "Show diff of changes to be committed")
    :switch("n", "no-verify", "Disable hooks")
    -- Options
    :option("A", "author", "", "Override the author")
    :option("S", "signoff", "", "Add Signed-off-by trailer", { cli_prefix = "--", separator = "" })
    -- Actions
    :group_heading("Create")
    :action("c", "Commit", function(popup_data)
      M._do_commit(repo_state, popup_data, false)
    end)
    :group_heading("Edit HEAD")
    :action("e", "Extend", function(popup_data)
      M._do_extend(repo_state, popup_data)
    end)
    :action("w", "Reword", function(popup_data)
      M._do_reword(repo_state, popup_data)
    end)
    :action("a", "Amend", function(popup_data)
      M._do_commit(repo_state, popup_data, true)
    end)
    :group_heading("Instant")
    :action("F", "Instant fixup", function(popup_data)
      M._do_instant_fixup(repo_state, popup_data)
    end)
    :action("S", "Instant squash", function(popup_data)
      M._do_instant_squash(repo_state, popup_data)
    end)
    :build()

  commit_popup:show()
end

--- Check if commit can proceed (has staged changes or appropriate flags)
---@param repo_state RepoState
---@param args string[]
---@param amend boolean
---@return boolean can_commit
---@return string|nil error_message
local function can_commit(repo_state, args, amend)
  -- Amend doesn't require staged changes
  if amend then
    return true, nil
  end

  -- Check for flags that bypass staged changes requirement
  local has_all = false
  local has_allow_empty = false
  for _, arg in ipairs(args) do
    if arg == "--all" then
      has_all = true
    elseif arg == "--allow-empty" then
      has_allow_empty = true
    end
  end

  if has_all or has_allow_empty then
    return true, nil
  end

  -- Check if there are staged changes
  local status = repo_state.status
  if not status then
    return false, "Status not loaded"
  end

  local has_staged = status.staged and #status.staged > 0
  if not has_staged then
    return false, "Nothing staged. Use -a to stage all changes, or -e to allow empty commit."
  end

  return true, nil
end

--- Perform a commit (opens editor buffer)
---@param repo_state RepoState
---@param popup_data PopupData
---@param amend boolean Whether this is an amend
function M._do_commit(repo_state, popup_data, amend)
  local commit_editor = require("gitlad.ui.views.commit_editor")
  local args = popup_data:get_arguments()

  if amend then
    table.insert(args, "--amend")
  end

  -- Validate that we can commit
  local ok, err = can_commit(repo_state, args, amend)
  if not ok then
    vim.notify("[gitlad] " .. err, vim.log.levels.WARN)
    return
  end

  commit_editor.open(repo_state, args)
end

--- Extend the current commit (amend without editing message)
---@param repo_state RepoState
---@param popup_data PopupData
function M._do_extend(repo_state, popup_data)
  local git = require("gitlad.git")
  local args = popup_data:get_arguments()

  -- Use streaming version to show hook output
  git.commit_amend_no_edit_streaming(args, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Commit extended", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Extend failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Reword the current commit (amend message only, ignore staged changes)
---@param repo_state RepoState
---@param popup_data PopupData
function M._do_reword(repo_state, popup_data)
  local commit_editor = require("gitlad.ui.views.commit_editor")
  local args = popup_data:get_arguments()

  -- Add --amend and --only flags
  -- --only with no paths means "only commit what's already in HEAD, ignore index"
  table.insert(args, "--amend")
  table.insert(args, "--only")

  commit_editor.open(repo_state, args)
end

--- Execute the instant fixup/squash operation
---@param repo_state RepoState
---@param target_hash string Target commit hash
---@param args string[] Extra commit arguments
---@param is_squash boolean Whether this is squash (true) or fixup (false)
local function execute_instant_operation(repo_state, target_hash, args, is_squash)
  local git = require("gitlad.git")

  -- Determine commit flag
  local commit_flag = is_squash and ("--squash=" .. target_hash) or ("--fixup=" .. target_hash)
  local commit_args = vim.list_extend({ commit_flag }, args)

  local operation_name = is_squash and "squash" or "fixup"

  vim.notify("[gitlad] Creating " .. operation_name .. " commit...", vim.log.levels.INFO)

  -- Step 1: Create the fixup/squash commit
  -- Use commit_fixup which doesn't pass -F (--fixup generates its own message)
  git.commit_fixup(commit_args, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if not success then
        vim.notify(
          "[gitlad] Failed to create " .. operation_name .. " commit: " .. (err or "unknown"),
          vim.log.levels.ERROR
        )
        return
      end

      vim.notify("[gitlad] Rebasing to apply " .. operation_name .. "...", vim.log.levels.INFO)

      -- Step 2: Instant rebase to apply the fixup/squash
      -- Rebase from target's parent
      git.rebase_instantly(target_hash .. "~1", {}, { cwd = repo_state.repo_root }, function(rebase_success, output, rebase_err)
        vim.schedule(function()
          if rebase_success then
            vim.notify("[gitlad] " .. operation_name:sub(1, 1):upper() .. operation_name:sub(2) .. " applied successfully", vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            -- Check if rebase is in progress (conflicts)
            if git.rebase_in_progress({ cwd = repo_state.repo_root }) then
              vim.notify(
                "[gitlad] Rebase stopped due to conflicts - resolve and use rebase popup to continue",
                vim.log.levels.WARN
              )
            else
              vim.notify("[gitlad] Rebase failed: " .. (rebase_err or "unknown"), vim.log.levels.ERROR)
            end
            repo_state:refresh_status(true)
          end
        end)
      end)
    end)
  end)
end

--- Perform instant fixup
--- Creates a fixup commit and immediately rebases to apply it
---@param repo_state RepoState
---@param popup_data PopupData
function M._do_instant_fixup(repo_state, popup_data)
  local commit_select = require("gitlad.ui.views.commit_select")
  local args = popup_data:get_arguments()

  -- Validate staged changes
  local status = repo_state.status
  local has_staged = status and status.staged and #status.staged > 0

  -- Check for --all flag which stages everything
  local has_all = vim.tbl_contains(args, "--all")

  if not has_staged and not has_all then
    vim.notify(
      "[gitlad] Nothing staged for fixup. Stage changes first or use -a to stage all.",
      vim.log.levels.WARN
    )
    return
  end

  -- Open commit selector
  commit_select.open(repo_state, function(commit)
    if commit then
      execute_instant_operation(repo_state, commit.hash, args, false)
    end
  end, { prompt = "Fixup commit" })
end

--- Perform instant squash
--- Creates a squash commit and immediately rebases to apply it
---@param repo_state RepoState
---@param popup_data PopupData
function M._do_instant_squash(repo_state, popup_data)
  local commit_select = require("gitlad.ui.views.commit_select")
  local args = popup_data:get_arguments()

  -- Validate staged changes
  local status = repo_state.status
  local has_staged = status and status.staged and #status.staged > 0

  -- Check for --all flag which stages everything
  local has_all = vim.tbl_contains(args, "--all")

  if not has_staged and not has_all then
    vim.notify(
      "[gitlad] Nothing staged for squash. Stage changes first or use -a to stage all.",
      vim.log.levels.WARN
    )
    return
  end

  -- Open commit selector
  commit_select.open(repo_state, function(commit)
    if commit then
      execute_instant_operation(repo_state, commit.hash, args, true)
    end
  end, { prompt = "Squash into commit" })
end

return M
