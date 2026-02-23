---@mod gitlad.ui.views.diff.save Diff buffer save operations
---@brief [[
--- Handles saving edited diff buffer content back to the worktree or git index.
--- Used by editable diff buffers (staged, unstaged, worktree, three_way sources).
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")

--- Save lines to the worktree (disk).
--- Writes the given lines to repo_root/path.
---@param repo_root string Repository root path
---@param path string File path relative to repo root
---@param lines string[] Lines to write
---@param cb fun(err: string|nil) Callback with nil on success, error message on failure
function M.save_worktree(repo_root, path, lines, cb)
  local full_path = repo_root .. "/" .. path
  local ok, err = pcall(vim.fn.writefile, lines, full_path)
  if ok then
    cb(nil)
  else
    cb("Failed to write " .. path .. ": " .. tostring(err))
  end
end

--- Save lines to the git index.
--- Two-step async operation:
--- 1. `git hash-object -w --stdin` — create blob from content, get OID
--- 2. `git update-index --cacheinfo 100644,<OID>,<path>` — point index at new blob
---@param repo_root string Repository root path
---@param path string File path relative to repo root
---@param lines string[] Lines to write
---@param cb fun(err: string|nil) Callback with nil on success, error message on failure
function M.save_index(repo_root, path, lines, cb)
  -- Step 1: hash-object -w --stdin
  cli.run_async_with_stdin(
    { "hash-object", "-w", "--stdin" },
    lines,
    { cwd = repo_root, internal = true },
    function(result)
      if result.code ~= 0 then
        local err = table.concat(result.stderr, "\n")
        vim.schedule(function()
          cb("hash-object failed: " .. err)
        end)
        return
      end

      -- Get OID from stdout (first line, trimmed)
      local oid = (result.stdout[1] or ""):gsub("%s+$", "")
      if oid == "" then
        vim.schedule(function()
          cb("hash-object returned empty OID")
        end)
        return
      end

      -- Step 2: update-index --cacheinfo
      local cacheinfo = string.format("100644,%s,%s", oid, path)
      cli.run_async(
        { "update-index", "--cacheinfo", cacheinfo },
        { cwd = repo_root, internal = true },
        function(result2)
          if result2.code ~= 0 then
            local err2 = table.concat(result2.stderr, "\n")
            vim.schedule(function()
              cb("update-index failed: " .. err2)
            end)
          else
            vim.schedule(function()
              cb(nil)
            end)
          end
        end
      )
    end
  )
end

return M
