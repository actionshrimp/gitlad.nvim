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

  git.commit_amend_no_edit(args, { cwd = repo_state.repo_root }, function(success, err)
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

return M
