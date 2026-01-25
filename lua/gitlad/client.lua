---@mod gitlad.client RPC client for editor integration
---@brief [[
--- Handles communication between git editor processes and the main Neovim instance.
--- When git invokes an editor (e.g., for interactive rebase), we spawn a headless
--- Neovim that connects back to the main instance via RPC, allowing us to open
--- the file in a custom buffer with our keybindings.
---@brief ]]

local M = {}

local fn = vim.fn
local fmt = string.format

---@class RpcConnection
---@field address string
---@field channel_id number|nil
---@field mode "tcp"|"pipe"
local RpcConnection = {}
RpcConnection.__index = RpcConnection

--- Create a new RPC connection
---@param address string Server address
---@return RpcConnection
function RpcConnection.new(address)
  local instance = {
    address = address,
    channel_id = nil,
    mode = address:match(":%d+$") and "tcp" or "pipe",
  }
  return setmetatable(instance, RpcConnection)
end

--- Connect to the RPC server
function RpcConnection:connect()
  self.channel_id = fn.sockconnect(self.mode, self.address, { rpc = true })
end

--- Disconnect from the RPC server
function RpcConnection:disconnect()
  if self.channel_id then
    fn.chanclose(self.channel_id)
    self.channel_id = nil
  end
end

--- Send a command synchronously
---@param cmd string Vim command to execute
function RpcConnection:send_cmd(cmd)
  vim.rpcrequest(self.channel_id, "nvim_command", cmd)
end

--- Send a command asynchronously
---@param cmd string Vim command to execute
function RpcConnection:send_cmd_async(cmd)
  vim.rpcnotify(self.channel_id, "nvim_command", cmd)
end

--- Create and connect an RPC connection
---@param address string Server address
---@return RpcConnection
local function create_connection(address)
  local rpc = RpcConnection.new(address)
  rpc:connect()
  return rpc
end

--- Get the command to spawn a headless Neovim that connects back via RPC
--- This command is suitable for use as GIT_SEQUENCE_EDITOR
---@return string editor_cmd Shell command for headless editor
function M.get_nvim_remote_editor()
  -- Get the path to gitlad plugin
  local source_path = debug.getinfo(1, "S").source
  -- Remove the leading @ and the filename to get the plugin root
  local gitlad_path = source_path:sub(2, -#"lua/gitlad/client.lua" - 1)
  local nvim_path = fn.shellescape(vim.v.progpath)

  local runtimepath_cmd = fn.shellescape(fmt("set runtimepath^=%s", fn.fnameescape(tostring(gitlad_path))))
  local lua_cmd = fn.shellescape("lua require('gitlad.client').client()")

  local shell_cmd = {
    nvim_path,
    "--headless",
    "--clean",
    "--noplugin",
    "-n",
    "-R",
    "-c",
    runtimepath_cmd,
    "-c",
    lua_cmd,
  }

  return table.concat(shell_cmd, " ")
end

--- Get environment variables for git editor integration
---@return table<string, string> env Environment variables to pass to git
function M.get_envs_git_editor()
  local nvim_cmd = M.get_nvim_remote_editor()
  return {
    GIT_SEQUENCE_EDITOR = nvim_cmd,
    GIT_EDITOR = nvim_cmd,
  }
end

--- Entry point for the headless client
--- Called when git invokes our editor command
--- Starts a server and connects to the parent process via RPC
function M.client()
  local nvim_server = vim.env.NVIM
  if not nvim_server then
    -- Not running inside a Neovim terminal, exit with error
    vim.cmd("cq")
    return
  end

  -- Get the file path from arguments
  local file_target = fn.fnamemodify(fn.argv()[1], ":p")

  -- Start our own server for the parent to communicate back
  local client_address = fn.serverstart()

  -- Send RPC to main Neovim to open the editor
  local lua_cmd = fmt('lua require("gitlad.client").editor(%q, %q)', file_target, client_address)
  local rpc_server = create_connection(nvim_server)
  rpc_server:send_cmd(lua_cmd)

  -- Don't disconnect - we need to keep running until the parent tells us to quit
  -- The parent will send "qall" (success) or "cq" (abort) when done
end

--- Invoked by the headless client to open the appropriate editor in the main Neovim
---@param target string Path to file to edit (e.g., git-rebase-todo)
---@param client_address string RPC address of the headless client for signaling completion
function M.editor(target, client_address)
  local rpc_client = create_connection(client_address)

  --- Callback to signal the headless client to exit
  ---@param success boolean Whether the edit was successful
  local function on_close(success)
    if success then
      rpc_client:send_cmd_async("qall")
    else
      rpc_client:send_cmd_async("cq")
    end
    rpc_client:disconnect()
  end

  -- Determine which editor to open based on the file
  if target:match("git%-rebase%-todo$") then
    -- Interactive rebase todo list
    local rebase_editor = require("gitlad.ui.views.rebase_editor")
    rebase_editor.open(target, on_close)
  elseif target:match("COMMIT_EDITMSG$") then
    -- Commit message (during rebase reword, etc.)
    -- For now, just open in a regular buffer
    -- TODO: Could integrate with commit_editor.lua
    M._open_simple_editor(target, on_close)
  elseif target:match("MERGE_MSG$") then
    -- Merge message
    M._open_simple_editor(target, on_close)
  else
    -- Unknown file type, open in simple editor
    M._open_simple_editor(target, on_close)
  end
end

--- Open a simple editor buffer for files we don't have special handling for
--- Uses standard ZZ/ZQ/C-c C-c/C-c C-k keybindings
---@param target string Path to file
---@param on_close fun(success: boolean) Callback when editor closes
function M._open_simple_editor(target, on_close)
  local keymap = require("gitlad.utils.keymap")

  -- Open the file
  vim.cmd("edit " .. fn.fnameescape(target))
  local bufnr = vim.api.nvim_get_current_buf()

  local closed = false
  local function close_with_status(success)
    if closed then
      return
    end
    closed = true

    if success then
      vim.cmd("write")
    end

    -- Close the buffer
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      on_close(success)
    end)
  end

  -- Set up keymaps
  keymap.set(bufnr, "n", "ZZ", function()
    close_with_status(true)
  end, "Save and close")

  keymap.set(bufnr, "n", "ZQ", function()
    close_with_status(false)
  end, "Abort")

  keymap.set(bufnr, "n", "<C-c><C-c>", function()
    close_with_status(true)
  end, "Save and close")

  keymap.set(bufnr, "n", "<C-c><C-k>", function()
    close_with_status(false)
  end, "Abort")

  keymap.set(bufnr, "i", "<C-c><C-c>", function()
    vim.cmd("stopinsert")
    close_with_status(true)
  end, "Save and close")

  keymap.set(bufnr, "i", "<C-c><C-k>", function()
    vim.cmd("stopinsert")
    close_with_status(false)
  end, "Abort")

  -- Cleanup autocommand
  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = bufnr,
    once = true,
    callback = function()
      -- If buffer is unloaded without explicit close, treat as abort
      if not closed then
        closed = true
        on_close(false)
      end
    end,
  })
end

return M
