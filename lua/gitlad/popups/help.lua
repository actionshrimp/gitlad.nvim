---@mod gitlad.popups.help Help popup
---@brief [[
--- Transient-style help popup showing all keybindings.
--- Pressing a key executes that action (where applicable).
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")

---@class HelpPopupContext
---@field status_buffer StatusBuffer
---@field repo_state RepoState

--- Create and show the help popup
---@param status_buffer StatusBuffer
function M.open(status_buffer)
  local repo_state = status_buffer.repo_state

  local help_popup = popup
    .builder()
    :name("Help")
    :columns(2)
    -- Navigation
    :group_heading("Navigation")
    :action("j", "Next item", function()
      -- Just close, user can navigate normally
    end)
    :action("k", "Previous item", function()
      -- Just close, user can navigate normally
    end)
    :action("<Tab>", "Toggle inline diff", function()
      -- Context-dependent, just close
    end)
    :action("<S-Tab>", "Cycle visibility (1→2→3→4→1)", function()
      status_buffer:_cycle_visibility_level()
    end)
    :action("g1", "Show headers only", function()
      status_buffer:_apply_visibility_level(1)
    end)
    :action("g2", "Show items", function()
      status_buffer:_apply_visibility_level(2)
    end)
    :action("g3", "Show diffs", function()
      status_buffer:_apply_visibility_level(3)
    end)
    :action("g4", "Show all", function()
      status_buffer:_apply_visibility_level(4)
    end)
    :action("<CR>", "Visit file (diffview for conflicts)", function()
      -- Context-dependent, just close
    end)
    :action("e", "Edit file (diffview for conflicts)", function()
      -- Context-dependent, just close
    end)
    -- Staging
    :group_heading("Staging")
    :action("s", "Stage file/hunk at cursor", function()
      -- Context-dependent, just close
    end)
    :action("u", "Unstage file/hunk at cursor", function()
      -- Context-dependent, just close
    end)
    :action("S", "Stage all", function()
      status_buffer:_stage_all()
    end)
    :action("U", "Unstage all", function()
      status_buffer:_unstage_all()
    end)
    :action("x", "Discard changes at point", function()
      -- Context-dependent, just close
    end)
    -- Popups
    :group_heading("Popups")
    :action("c", "Commit", function()
      local commit_popup = require("gitlad.popups.commit")
      commit_popup.open(repo_state)
    end)
    :action("p", "Push", function()
      local push_popup = require("gitlad.popups.push")
      push_popup.open(repo_state)
    end)
    :action("f", "Fetch", function()
      local fetch_popup = require("gitlad.popups.fetch")
      fetch_popup.open(repo_state)
    end)
    :action("F", "Pull", function()
      local pull_popup = require("gitlad.popups.pull")
      pull_popup.open(repo_state)
    end)
    :action("b", "Branch", function()
      local branch_popup = require("gitlad.popups.branch")
      branch_popup.open(repo_state)
    end)
    :action("l", "Log", function()
      local log_popup = require("gitlad.popups.log")
      log_popup.open(repo_state)
    end)
    :action("d", "Diff", function()
      local diff_popup = require("gitlad.popups.diff")
      diff_popup.open(repo_state, {})
    end)
    :action("z", "Stash", function()
      local stash_popup = require("gitlad.popups.stash")
      stash_popup.open(repo_state)
    end)
    :action("A", "Cherry-pick", function()
      local cherrypick_popup = require("gitlad.popups.cherrypick")
      cherrypick_popup.open(repo_state)
    end)
    :action("_", "Revert", function()
      local revert_popup = require("gitlad.popups.revert")
      revert_popup.open(repo_state)
    end)
    :action("X", "Reset", function()
      local reset_popup = require("gitlad.popups.reset")
      reset_popup.open(repo_state)
    end)
    :action("r", "Rebase", function()
      local rebase_popup = require("gitlad.popups.rebase")
      rebase_popup.open(repo_state)
    end)
    :action("m", "Merge", function()
      local merge_popup = require("gitlad.popups.merge")
      merge_popup.open(repo_state)
    end)
    :action("'", "Submodule", function()
      local submodule_popup = require("gitlad.popups.submodule")
      submodule_popup.open(repo_state)
    end)
    :action("yr", "References", function()
      local refs_popup = require("gitlad.popups.refs")
      refs_popup.open(repo_state)
    end)
    -- Other
    :group_heading("Other")
    :action("ys", "Yank section value", function()
      status_buffer:_yank_section_value()
    end)
    :action("gr", "Refresh", function()
      repo_state:refresh_status(true)
    end)
    :action("$", "Git command history", function()
      local history_view = require("gitlad.ui.views.history")
      history_view.open()
    end)
    :action("q", "Close status buffer", function()
      -- This closes help; 'q' again will close status
    end)
    :action("?", "This help", function()
      -- Already in help, just close
    end)
    :build()

  help_popup:show()
end

return M
