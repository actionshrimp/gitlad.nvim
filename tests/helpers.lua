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
    vim.fn.system("git -C " .. %q .. " init")
    vim.fn.system("git -C " .. %q .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. %q .. " config user.name 'Test User'")
  ]],
    tmp_dir,
    tmp_dir,
    tmp_dir,
    tmp_dir
  ))

  return tmp_dir
end

--- Create a file in the test repo
---@param child table MiniTest child process
---@param repo_path string Repository path
---@param filename string File name
---@param content string File content
function M.create_file(child, repo_path, filename, content)
  child.lua(string.format(
    [[
    local path = %q .. "/" .. %q
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
  return child.lua_get(string.format([[vim.fn.system("git -C %s %s")]], repo_path, args))
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

return M
