---@mod gitlad.git.git_patch Patch operations
---@brief [[
--- Git patch operations: format-patch, apply, am (mailbox apply).
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local errors = require("gitlad.utils.errors")

-- =============================================================================
-- Format Patch (git format-patch)
-- =============================================================================

--- Create patch files from commits
---@param range string Commit range (e.g., "origin/main..HEAD", "-3", "abc1234")
---@param args string[] Extra arguments (from popup switches, e.g., {"--cover-letter", "-v2"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.format_patch(range, args, opts, callback)
  local format_args = { "format-patch" }
  vim.list_extend(format_args, args)
  table.insert(format_args, range)

  cli.run_async(format_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

-- =============================================================================
-- Apply Patch (git apply - plain patch, no commits)
-- =============================================================================

--- Apply a plain patch file (git apply - does NOT create commits)
---@param file string Path to patch file
---@param args string[] Extra arguments (e.g., {"--3way", "--index"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.apply_patch_file(file, args, opts, callback)
  local apply_args = { "apply" }
  vim.list_extend(apply_args, args)
  table.insert(apply_args, "--")
  table.insert(apply_args, file)

  cli.run_async(apply_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

-- =============================================================================
-- AM (git am - apply mailbox patches, creates commits)
-- =============================================================================

--- Apply patch files using git am (creates commits)
---@param files string[] Path(s) to patch files or maildir
---@param args string[] Extra arguments (from popup switches, e.g., {"--3way", "--signoff"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.am(files, args, opts, callback)
  local am_args = { "am" }
  vim.list_extend(am_args, args)
  vim.list_extend(am_args, files)

  cli.run_async(am_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Continue an in-progress git am
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.am_continue(opts, callback)
  cli.run_async({ "am", "--continue" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Skip the current patch during git am
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.am_skip(opts, callback)
  cli.run_async({ "am", "--skip" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress git am
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.am_abort(opts, callback)
  cli.run_async({ "am", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

-- =============================================================================
-- AM State Detection
-- =============================================================================

---@class AmState
---@field am_in_progress boolean Whether a git am is in progress
---@field current_patch string|nil The current patch being applied (e.g., "0001")
---@field last_patch string|nil The last patch number (e.g., "0003")

--- Check if a git am is in progress
--- git am uses the rebase-apply directory (without a rebasing file)
---@param opts? GitCommandOptions
---@return AmState
function M.get_am_state(opts)
  local git_dir = cli.find_git_dir(opts and opts.cwd or nil)
  if not git_dir then
    return {
      am_in_progress = false,
      current_patch = nil,
      last_patch = nil,
    }
  end

  local state = {
    am_in_progress = false,
    current_patch = nil,
    last_patch = nil,
  }

  -- git am uses rebase-apply/ directory
  -- To distinguish from rebase: rebase-apply/rebasing exists during rebase,
  -- rebase-apply/applying exists during am
  local rebase_apply = git_dir .. "/rebase-apply"
  if vim.fn.isdirectory(rebase_apply) == 1 then
    local applying = rebase_apply .. "/applying"
    if vim.fn.filereadable(applying) == 1 then
      state.am_in_progress = true

      -- Read current patch number
      local next_file = rebase_apply .. "/next"
      if vim.fn.filereadable(next_file) == 1 then
        local content = vim.fn.readfile(next_file)
        if content[1] then
          state.current_patch = vim.trim(content[1])
        end
      end

      -- Read total patch count
      local last_file = rebase_apply .. "/last"
      if vim.fn.filereadable(last_file) == 1 then
        local content = vim.fn.readfile(last_file)
        if content[1] then
          state.last_patch = vim.trim(content[1])
        end
      end
    end
  end

  return state
end

return M
