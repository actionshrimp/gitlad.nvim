---@mod gitlad A snappy git interface for Neovim
---@brief [[
--- gitlad.nvim is a git interface inspired by magit, fugitive, and lazygit.
--- It aims to be fast, well-tested, and provide excellent UX through
--- transient-style popup menus.
---@brief ]]

local M = {}

local config = require("gitlad.config")

---@class GitladSetupOptions
---@field refresh_on_focus? boolean Auto-refresh when Neovim gains focus (default: true)
---@field watch_gitdir? boolean Watch .git directory for changes (default: true)
---@field signs? table Signs configuration for status buffer

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
