---@mod gitlad.popups.refs Refs popup
---@brief [[
--- Transient-style refs popup with actions to show refs buffer.
--- Shows all references (branches, tags) compared against a base ref.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Open refs view with given base ref
---@param repo_state RepoState
---@param base_ref string The ref to compare against
local function open_refs_view(repo_state, base_ref)
  vim.notify("[gitlad] Loading refs...", vim.log.levels.INFO)

  -- Open the refs view
  local refs_view = require("gitlad.ui.views.refs")
  refs_view.open(repo_state, base_ref)
end

--- Create and show the refs popup
---@param repo_state RepoState
function M.open(repo_state)
  local refs_popup = popup
    .builder()
    :name("References")
    -- Actions
    :group_heading("Show refs")
    :action("y", "Show refs at HEAD", function(_popup_data)
      M._show_refs_head(repo_state)
    end)
    :action("r", "Show refs at current branch", function(_popup_data)
      M._show_refs_current(repo_state)
    end)
    :action("o", "Show refs at other ref...", function(_popup_data)
      M._show_refs_other(repo_state)
    end)
    :build()

  refs_popup:show()
end

--- Show refs compared with HEAD
---@param repo_state RepoState
function M._show_refs_head(repo_state)
  open_refs_view(repo_state, "HEAD")
end

--- Show refs compared with current branch
---@param repo_state RepoState
function M._show_refs_current(repo_state)
  local branch = repo_state.status and repo_state.status.branch
  if branch and branch ~= "" and branch ~= "(detached)" then
    open_refs_view(repo_state, branch)
  else
    -- Fallback to HEAD if detached
    open_refs_view(repo_state, "HEAD")
  end
end

--- Show refs compared with other ref (prompts for ref selection)
---@param repo_state RepoState
function M._show_refs_other(repo_state)
  -- Get all refs (branches and tags)
  git.refs({ cwd = repo_state.repo_root }, function(refs, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get refs: " .. err, vim.log.levels.ERROR)
        return
      end

      if not refs or #refs == 0 then
        vim.notify("[gitlad] No refs found", vim.log.levels.WARN)
        return
      end

      -- Build list of ref names (prioritize local branches)
      local ref_names = {}
      for _, ref in ipairs(refs) do
        table.insert(ref_names, ref.name)
      end

      vim.ui.select(ref_names, {
        prompt = "Select ref to compare against:",
      }, function(choice)
        if not choice then
          return
        end

        open_refs_view(repo_state, choice)
      end)
    end)
  end)
end

return M
