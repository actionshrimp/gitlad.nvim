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
--- Uses a template repo for faster setup (cp -r instead of git init + config)
---@param child table MiniTest child process
---@return string repo_path Path to the temporary repository
function M.create_test_repo(child)
  local tmp_dir = child.lua_get("vim.fn.tempname()")

  child.lua(string.format(
    [[
    -- Lazily create template repo on first use
    if not _G._gitlad_test_template then
      local template = vim.fn.tempname() .. "_template"
      vim.fn.mkdir(template, "p")
      vim.fn.system("git -C " .. template .. " init -b main")
      vim.fn.system("git -C " .. template .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. template .. " config user.name 'Test User'")
      vim.fn.system("git -C " .. template .. " config commit.gpgsign false")
      _G._gitlad_test_template = template
    end

    -- Copy template to new location (much faster than git init + config)
    vim.fn.system("cp -r " .. _G._gitlad_test_template .. " " .. %q)
  ]],
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

--- Wait until the status buffer is loaded and has meaningful content
--- Checks for "Head:" which indicates git status has been fetched
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 5000 for parallel test resilience)
function M.wait_for_status(child, timeout)
  timeout = timeout or 5000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      local bufname = vim.api.nvim_buf_get_name(0)
      if not bufname:match("gitlad://status") then return false end
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      -- Wait for actual git status to be fetched (Head: line appears)
      for _, line in ipairs(lines) do
        if line:match("^Head:") then return true end
      end
      return false
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
---@param timeout? number Timeout in milliseconds (default 5000 for parallel test resilience)
function M.wait_for_buffer(child, pattern, timeout)
  timeout = timeout or 5000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local bufname = vim.api.nvim_buf_get_name(0)
        return bufname:match(%q) ~= nil
      end, 10)
      return ok
    end)()]],
    timeout,
    pattern
  ))
  if not success then
    local actual = child.lua_get([[vim.api.nvim_buf_get_name(0)]])
    error(
      string.format(
        "wait_for_buffer timed out after %dms waiting for %q, got %q",
        timeout,
        pattern,
        actual
      )
    )
  end
end

--- Wait until the current buffer contains specific text
---@param child table MiniTest child process
---@param text string Text to search for (plain text, not pattern)
---@param timeout? number Timeout in milliseconds (default 2000)
---@return boolean success Whether the content was found
function M.wait_for_buffer_content(child, text, timeout)
  timeout = timeout or 2000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local content = table.concat(lines, "\n")
        return content:find(%q, 1, true) ~= nil
      end, 10)
      return ok
    end)()]],
    timeout,
    text
  ))
  return success
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
---@param ms? number Milliseconds to wait (default 200 for parallel test resilience)
function M.wait_short(child, ms)
  ms = ms or 200
  child.lua(string.format([[vim.wait(%d, function() return false end)]], ms))
end

--- Check if a popup switch is enabled by checking for the SwitchEnabled highlight
--- on the line matching the given pattern
---@param child table MiniTest child process
---@param pattern string Lua pattern to match the switch line (e.g. "%-f.*force%-with%-lease")
---@return boolean
function M.popup_switch_enabled(child, pattern)
  return child.lua_get(string.format(
    [[(function()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local ns = vim.api.nvim_get_namespaces()["gitlad_popup"]
    if not ns then return false end
    for i, line in ipairs(lines) do
      if line:match(%q) then
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns, {i-1, 0}, {i-1, -1}, {details=true})
        for _, mark in ipairs(marks) do
          if mark[4] and mark[4].hl_group == "GitladPopupSwitchEnabled" then
            return true
          end
        end
        return false
      end
    end
    return false
  end)()]],
    pattern
  ))
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

--- Wait until the current buffer has a specific filetype
---@param child table MiniTest child process
---@param filetype string Expected filetype
---@param timeout? number Timeout in milliseconds (default 1000)
function M.wait_for_filetype(child, filetype, timeout)
  timeout = timeout or 1000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        return vim.bo.filetype == %q
      end, 10)
      return ok
    end)()]],
    timeout,
    filetype
  ))
  if not success then
    local actual = child.lua_get([[vim.bo.filetype]])
    error(
      string.format(
        "wait_for_filetype timed out after %dms waiting for %q, got %q",
        timeout,
        filetype,
        actual
      )
    )
  end
end

--- Wait until window count reaches expected value
---@param child table MiniTest child process
---@param count number Expected window count
---@param timeout? number Timeout in milliseconds (default 500)
function M.wait_for_win_count(child, count, timeout)
  timeout = timeout or 500
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      return vim.fn.winnr('$') == %d
    end, 10)
  ]],
    timeout,
    count
  ))
end

--- Wait until a diff expansion is visible (contains @@ header)
--- Use after pressing TAB to expand a file diff
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 2000)
---@return boolean success Whether diff content was found
function M.wait_for_diff_expanded(child, timeout)
  timeout = timeout or 2000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("^@@") or line:match("^%%s+@@") then
            return true
          end
        end
        return false
      end, 10)
      return ok
    end)()]],
    timeout
  ))
  return success
end

--- Wait until diff is collapsed (no @@ headers visible)
---@param child table MiniTest child process
---@param timeout? number Timeout in milliseconds (default 1000)
---@return boolean success Whether diff was collapsed
function M.wait_for_diff_collapsed(child, timeout)
  timeout = timeout or 1000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("^@@") or line:match("^%%s+@@") then
            return false
          end
        end
        return true
      end, 10)
      return ok
    end)()]],
    timeout
  ))
  return success
end

--- Wait until vim messages contain specific text
---@param child table MiniTest child process
---@param text string Text to search for in messages
---@param timeout? number Timeout in milliseconds (default 2000)
---@return boolean success Whether the message was found
function M.wait_for_message(child, text, timeout)
  timeout = timeout or 2000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local messages = vim.fn.execute("messages")
        return messages:find(%q, 1, true) ~= nil
      end, 10)
      return ok
    end)()]],
    timeout,
    text
  ))
  return success
end

--- Wait for status buffer to contain specific content
--- More reliable than wait_for_status when you need to verify specific files/sections appear
---@param child table MiniTest child process
---@param text string Text that must appear in the status buffer (e.g., filename or section header)
---@param timeout? number Timeout in milliseconds (default 3000)
---@return boolean success Whether the content was found
function M.wait_for_status_content(child, text, timeout)
  timeout = timeout or 3000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local bufname = vim.api.nvim_buf_get_name(0)
        if not bufname:match("gitlad://status") then return false end
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local content = table.concat(lines, "\n")
        return content:find(%q, 1, true) ~= nil
      end, 10)
      return ok
    end)()]],
    timeout,
    text
  ))
  return success
end

--- Navigate to a line containing specific text and return its line number
--- Waits for the text to appear first, then moves cursor to that line
---@param child table MiniTest child process
---@param text string Text to find and navigate to
---@param timeout? number Timeout in milliseconds (default 2000)
---@return number|nil line_number The line number (1-indexed), or nil if not found
function M.goto_line_with(child, text, timeout)
  timeout = timeout or 2000
  local line_num = child.lua_get(string.format(
    [[(function()
      local found_line = nil
      vim.wait(%d, function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for i, line in ipairs(lines) do
          if line:find(%q, 1, true) then
            found_line = i
            return true
          end
        end
        return false
      end, 10)
      if found_line then
        vim.cmd(tostring(found_line))
      end
      return found_line
    end)()]],
    timeout,
    text
  ))
  return line_num
end

--- Wait for expansion state of a file in the status buffer
--- Useful after pressing visibility keys (1/2/3/4/Tab) to ensure state is updated
---@param child table MiniTest child process
---@param file_key string The key in expanded_files (e.g., "unstaged:file.txt")
---@param expected_state boolean Expected state (true=expanded, false=collapsed)
---@param timeout? number Timeout in milliseconds (default 5000)
---@return boolean success Whether the expected state was found
function M.wait_for_expansion_state(child, file_key, expected_state, timeout)
  timeout = timeout or 5000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local status = require("gitlad.ui.views.status")
        local buffer = status.get_buffer()
        if buffer and buffer.expanded_files then
          local actual = buffer.expanded_files[%q]
          local expected = %s
          if expected == false then
            -- nil also counts as collapsed (key removed from table)
            return actual == false or actual == nil
          end
          return actual == expected
        end
        return false
      end, 50)
      return ok
    end)()]],
    timeout,
    file_key,
    tostring(expected_state)
  ))
  return success
end

--- Wait for git status to contain expected content
--- Useful after staging/unstaging operations to ensure git state has settled
---@param child table MiniTest child process
---@param repo_path string Repository path
---@param expected string Text that must appear in git status --porcelain output
---@param timeout? number Timeout in milliseconds (default 20000 for parallel test resilience)
---@return boolean success Whether the expected status was found
function M.wait_for_git_status(child, repo_path, expected, timeout)
  timeout = timeout or 20000
  local success = child.lua_get(string.format(
    [[(function()
      local ok = vim.wait(%d, function()
        local status = vim.fn.system("git -C %s status --porcelain")
        return status:find(%q, 1, true) ~= nil
      end, 200)
      return ok
    end)()]],
    timeout,
    repo_path,
    expected
  ))
  return success
end

return M
