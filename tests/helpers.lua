-- Test helpers for gitlad.nvim
local M = {}

local child = nil

--- Get or create a child Neovim process for testing
---@return table MiniTest child process
function M.get_child()
  if child then
    return child
  end

  local MiniTest = require("mini.test")
  child = MiniTest.new_child_neovim()
  return child
end

--- Reset child process
function M.reset_child()
  if child then
    child.stop()
    child = nil
  end
end

--- Create a temporary git repository for testing
---@param child table MiniTest child process
---@return string repo_path Path to the temporary repository
function M.create_test_repo(child)
  local tmp_dir = child.lua_get("vim.fn.tempname()")

  child.lua(string.format(
    [[
    vim.fn.mkdir(%q, "p")
    vim.fn.system("git -C " .. %q .. " init -b main")
    vim.fn.system("git -C " .. %q .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. %q .. " config user.name 'Test User'")
    vim.fn.system("git -C " .. %q .. " config commit.gpgsign false")
  ]],
    tmp_dir,
    tmp_dir,
    tmp_dir,
    tmp_dir,
    tmp_dir
  ))

  return tmp_dir
end

--- Create a file in the test repo (creates parent directories if needed)
---@param child table MiniTest child process
---@param repo_path string Repository path
---@param filename string File name (can include subdirectories like "dir/file.txt")
---@param content string File content
function M.create_file(child, repo_path, filename, content)
  child.lua(string.format(
    [[
    local path = %q .. "/" .. %q
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(path, "w")
    f:write(%q)
    f:close()
  ]],
    repo_path,
    filename,
    content
  ))
end

--- Run a git command in the test repo
---@param child table MiniTest child process
---@param repo_path string Repository path
---@param args string Git command arguments
---@return string output Command output
function M.git(child, repo_path, args)
  return child.lua_get(string.format([[vim.fn.system(%q)]], "git -C " .. repo_path .. " " .. args))
end

--- Wait for async operations to complete
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 1000)
function M.wait_async(child, timeout)
  timeout = timeout or 1000
  child.lua(string.format(
    [[
    vim.wait(%d, function() return false end)
  ]],
    timeout
  ))
end

--- Clean up a test repository
---@param child table MiniTest child process
---@param repo_path string Repository path
function M.cleanup_repo(child, repo_path)
  child.lua(string.format(
    [[
    vim.fn.delete(%q, "rf")
  ]],
    repo_path
  ))
end

-- =============================================================================
-- Smart Wait Helpers (condition-based waits for faster tests)
-- =============================================================================

--- Wait until the status buffer is loaded and has content
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 1000)
function M.wait_for_status(child, timeout)
  timeout = timeout or 1000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      local bufname = vim.api.nvim_buf_get_name(0)
      if not bufname:match("gitlad://status") then return false end
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      return #lines > 1
    end, 10)
  ]],
    timeout
  ))
end

--- Wait until a popup window opens (window count > 1)
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 500)
function M.wait_for_popup(child, timeout)
  timeout = timeout or 500
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      return #vim.api.nvim_list_wins() > 1
    end, 10)
  ]],
    timeout
  ))
end

--- Wait until popup window closes (window count == 1)
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 300)
function M.wait_for_popup_closed(child, timeout)
  timeout = timeout or 300
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      return #vim.api.nvim_list_wins() == 1
    end, 10)
  ]],
    timeout
  ))
end

--- Wait until the current buffer name matches a pattern
---@param child table MiniTest child process
---@param pattern string Lua pattern to match against buffer name
---@param timeout? number Timeout in milliseconds (default 1000)
function M.wait_for_buffer(child, pattern, timeout)
  timeout = timeout or 1000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      local bufname = vim.api.nvim_buf_get_name(0)
      return bufname:match(%q) ~= nil
    end, 10)
  ]],
    timeout,
    pattern
  ))
end

--- Wait until the current buffer contains specific text
---@param child table MiniTest child process
---@param text string Text to search for (plain text, not pattern)
---@param timeout? number Timeout in milliseconds (default 1000)
function M.wait_for_buffer_content(child, text, timeout)
  timeout = timeout or 1000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local content = table.concat(lines, "\n")
      return content:find(%q, 1, true) ~= nil
    end, 10)
  ]],
    timeout,
    text
  ))
end

--- Wait until a global variable is set (useful for async callbacks)
---@param child table MiniTest child process
---@param var_name string Name of the global variable (e.g., "_G.my_result")
---@param timeout? number Timeout in milliseconds (default 1000)
function M.wait_for_var(child, var_name, timeout)
  timeout = timeout or 1000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      return %s ~= nil
    end, 10)
  ]],
    timeout,
    var_name
  ))
end

--- Wait a short fixed time (for UI updates that can't be condition-checked)
--- Use sparingly - prefer condition-based waits when possible
---@param child table MiniTest child process
---@param ms? number Milliseconds to wait (default 50)
function M.wait_short(child, ms)
  ms = ms or 50
  child.lua(string.format([[vim.wait(%d, function() return false end)]], ms))
end

--- Open gitlad status view and wait for it to load
---@param child table MiniTest child process
---@param repo_path string Repository path
---@param timeout? number Timeout in milliseconds (default 1000)
function M.open_gitlad(child, repo_path, timeout)
  child.lua(string.format([[vim.cmd("cd %s")]], repo_path))
  child.cmd("Gitlad")
  M.wait_for_status(child, timeout or 1000)
end

--- Change directory in child process
---@param child table MiniTest child process
---@param dir string Directory path
function M.cd(child, dir)
  child.lua(string.format([[vim.cmd("cd %s")]], dir))
end

return M
