---@mod gitlad.popups.worktree_merge wt merge popup
---@brief [[
--- Transient-style popup for running `wt merge`.
--- Invoked from the worktrunk worktree popup via the `m` action.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")

--- Create and show the wt merge popup
---@param repo_state RepoState
function M.open(repo_state)
  local merge_popup = popup
    .builder()
    :name("wt Merge")
    -- Switches (Arguments)
    :switch("s", "no-squash", "Skip squash")
    :switch("r", "no-rebase", "Skip rebase")
    :switch("R", "no-remove", "Keep worktree")
    :switch("v", "no-verify", "Skip hooks")
    -- Options
    :option("t", "target", "", "Target branch", { cli_prefix = "", separator = "=" })
    -- Actions
    :group_heading("Merge")
    :action("m", "Merge current branch into target", function(popup_data)
      M._run_merge(repo_state, popup_data)
    end)
    :build()

  merge_popup:show()
end

--- Execute wt merge with the given popup state
---@param repo_state RepoState
---@param popup_data PopupData
function M._run_merge(repo_state, popup_data)
  local wt = require("gitlad.worktrunk")

  -- Collect flags from switches
  local args = {}
  for _, sw in ipairs(popup_data.switches) do
    if sw.enabled then
      table.insert(args, "--" .. sw.cli)
    end
  end

  -- Target branch from option (empty = nil, let wt use its default)
  local target = nil
  for _, opt in ipairs(popup_data.options) do
    if opt.cli == "target" and opt.value ~= "" then
      target = opt.value
      break
    end
  end

  vim.notify("[gitlad] Running wt merge...", vim.log.levels.INFO)

  wt.merge(target, args, { cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] wt merge complete", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] wt merge failed: " .. (err or ""), vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
