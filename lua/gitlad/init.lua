---@mod gitlad A snappy git interface for Neovim
---@brief [[
--- gitlad.nvim is a git interface inspired by magit, fugitive, and lazygit.
--- It aims to be fast, well-tested, and provide excellent UX through
--- transient-style popup menus.
---@brief ]]

local M = {}

local config = require("gitlad.config")

---@class GitladSetupOptions
---@field signs? table Signs configuration for status buffer
---@field commit_editor? table Commit editor configuration
---@field worktree? table Worktree configuration
---@field status? table Status buffer configuration
---@field show_tags_in_refs? boolean Whether to show tags alongside branch names in refs (default: false)

--- Setup gitlad with user options
---@param opts? GitladSetupOptions
function M.setup(opts)
  config.setup(opts)

  -- Setup highlight groups
  require("gitlad.ui.hl").setup()

  -- Register user commands
  vim.api.nvim_create_user_command("Gitlad", function(cmd_opts)
    require("gitlad.commands").execute(cmd_opts.args)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      return require("gitlad.commands").complete(arg_lead)
    end,
    desc = "Gitlad git interface",
  })

  -- Warn before quitting with pending worktree operations.
  -- Uses QuitPre + temporarily marking the buffer as modified to prevent :q.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = vim.api.nvim_create_augroup("gitlad_quit_guard", { clear = true }),
    callback = function()
      require("gitlad.state.pending_ops")._quit_guard()
    end,
  })

  -- Convenience alias
  vim.api.nvim_create_user_command("G", function(cmd_opts)
    require("gitlad.commands").execute(cmd_opts.args)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      return require("gitlad.commands").complete(arg_lead)
    end,
    desc = "Gitlad git interface (alias)",
  })
end

--- Get current configuration
---@return GitladConfig
function M.get_config()
  return config.get()
end

return M
