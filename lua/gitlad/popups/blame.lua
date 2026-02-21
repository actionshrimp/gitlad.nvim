---@mod gitlad.popups.blame Blame popup
---@brief [[
--- Transient-style blame popup with switches for blame options.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local prompt = require("gitlad.utils.prompt")

--- Create and show the blame popup
---@param repo_state RepoState
---@param context? { blame_buffer: table } Optional blame buffer reference
function M.open(repo_state, context)
  local blame_buffer = context and context.blame_buffer or nil

  local blame_popup = popup
    .builder()
    :name("Blame")
    -- Switches (short flags for blame)
    :switch("w", "w", "Ignore whitespace", { cli_prefix = "-" })
    :switch("M", "M", "Detect moved lines", { cli_prefix = "-" })
    :switch("C", "C", "Detect copied lines", { cli_prefix = "-" })
    -- Actions
    :group_heading("Blame")
    :action("b", "Blame current file", function(popup_data)
      M._blame_current(repo_state, popup_data, blame_buffer)
    end)
    :action("r", "Blame at revision", function(popup_data)
      M._blame_at_revision(repo_state, popup_data, blame_buffer)
    end)
    :build()

  blame_popup:show()
end

--- Blame the current file (or file from existing blame buffer)
---@param repo_state RepoState
---@param popup_data PopupData
---@param blame_buffer table|nil
function M._blame_current(repo_state, popup_data, blame_buffer)
  local extra_args = popup_data:get_arguments()

  if blame_buffer then
    -- Re-blame with new switches
    blame_buffer.extra_args = extra_args
    blame_buffer:refresh()
  else
    -- Open blame for current file
    local file = vim.fn.expand("%:.")
    if file == "" then
      vim.notify("[gitlad] No file to blame", vim.log.levels.WARN)
      return
    end
    local blame_view = require("gitlad.ui.views.blame")
    blame_view.open_file(repo_state, file, nil, extra_args)
  end
end

--- Blame at a specific revision
---@param repo_state RepoState
---@param popup_data PopupData
---@param blame_buffer table|nil
function M._blame_at_revision(repo_state, popup_data, blame_buffer)
  local extra_args = popup_data:get_arguments()

  prompt.prompt_for_ref({ prompt = "Blame at revision: " }, function(revision)
    if not revision or revision == "" then
      return
    end

    if blame_buffer then
      -- Re-blame at revision with new switches
      blame_buffer.revision = revision
      blame_buffer.extra_args = extra_args
      blame_buffer:refresh()
    else
      local file = vim.fn.expand("%:.")
      if file == "" then
        vim.notify("[gitlad] No file to blame", vim.log.levels.WARN)
        return
      end
      local blame_view = require("gitlad.ui.views.blame")
      blame_view.open_file(repo_state, file, revision, extra_args)
    end
  end)
end

return M
