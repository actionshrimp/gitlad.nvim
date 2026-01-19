---@mod gitlad.popups.reset Reset popup
---@brief [[
--- Transient-style reset popup with actions for different reset modes.
--- Follows magit reset popup patterns.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Prompt user for target ref and execute reset
---@param repo_state RepoState
---@param context? { commit: string } Optional commit from cursor context
---@param prompt string Prompt to show user
---@param reset_fn fun(ref: string, opts: table, callback: fun(success: boolean, err: string|nil))
---@param mode_name string Mode name for notification
local function reset_with_prompt(repo_state, context, prompt, reset_fn, mode_name)
  -- If we have a commit from context, use it directly
  if context and context.commit then
    vim.notify("[gitlad] Resetting (" .. mode_name .. ")...", vim.log.levels.INFO)
    reset_fn(context.commit, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Reset to " .. context.commit:sub(1, 7), vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Reset failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
    return
  end

  -- Otherwise prompt for target
  vim.ui.input({
    prompt = prompt,
    default = "HEAD~1",
  }, function(ref)
    if not ref or ref == "" then
      return
    end

    vim.notify("[gitlad] Resetting (" .. mode_name .. ")...", vim.log.levels.INFO)
    reset_fn(ref, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Reset to " .. ref, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Reset failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

--- Check if there are uncommitted changes (staged or unstaged)
---@param status GitStatusResult|nil
---@return boolean
local function has_uncommitted_changes(status)
  if not status then
    return false
  end
  return (status.staged and #status.staged > 0) or (status.unstaged and #status.unstaged > 0)
end

--- Prompt for target ref with confirmation for destructive operations
--- Refreshes status first and only shows confirmation if there are uncommitted changes
---@param repo_state RepoState
---@param context? { commit: string } Optional commit from cursor context
---@param prompt string Prompt to show user
---@param reset_fn fun(ref: string, opts: table, callback: fun(success: boolean, err: string|nil))
---@param mode_name string Mode name for notification
---@param warning string Warning message for confirmation
local function reset_with_confirmation(repo_state, context, prompt, reset_fn, mode_name, warning)
  -- Get the target ref first
  local target_ref = context and context.commit or nil

  local function execute_reset(ref)
    vim.notify("[gitlad] Resetting (" .. mode_name .. ")...", vim.log.levels.INFO)
    reset_fn(ref, { cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Reset to " .. ref, vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Reset failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end

  local function do_reset(ref)
    -- Force refresh status first to check for uncommitted changes
    repo_state:refresh_status(true, function()
      vim.schedule(function()
        -- Only show confirmation if there are uncommitted changes
        if has_uncommitted_changes(repo_state.status) then
          vim.ui.select({ "Yes", "No" }, {
            prompt = warning .. " Continue?",
          }, function(choice)
            if choice ~= "Yes" then
              return
            end
            execute_reset(ref)
          end)
        else
          -- No uncommitted changes, proceed directly
          execute_reset(ref)
        end
      end)
    end)
  end

  if target_ref then
    do_reset(target_ref)
  else
    vim.ui.input({
      prompt = prompt,
      default = "HEAD~1",
    }, function(ref)
      if not ref or ref == "" then
        return
      end
      do_reset(ref)
    end)
  end
end

--- Get current branch name for prompt
---@param repo_state RepoState
---@return string
local function get_branch_name(repo_state)
  local status = repo_state.status
  if status and status.branch then
    return status.branch
  end
  return "HEAD"
end

--- Create and show the reset popup
---@param repo_state RepoState
---@param context? { commit: string } Optional commit at point for context-aware operations
function M.open(repo_state, context)
  local branch = get_branch_name(repo_state)
  local context_label = context and (" to " .. context.commit:sub(1, 7)) or ""

  local reset_popup = popup
    .builder()
    :name("Reset")
    :group_heading("Reset this")
    :action("m", "mixed    (HEAD and index)" .. context_label, function(_popup_data)
      reset_with_prompt(repo_state, context, "Reset " .. branch .. " to: ", function(ref, opts, cb)
        git.reset(ref, "mixed", opts, cb)
      end, "mixed")
    end)
    :action("s", "soft     (HEAD only)" .. context_label, function(_popup_data)
      reset_with_prompt(
        repo_state,
        context,
        "Soft reset " .. branch .. " to: ",
        function(ref, opts, cb)
          git.reset(ref, "soft", opts, cb)
        end,
        "soft"
      )
    end)
    :action("h", "hard     (HEAD, index and worktree)" .. context_label, function(_popup_data)
      reset_with_confirmation(
        repo_state,
        context,
        "Hard reset " .. branch .. " to: ",
        function(ref, opts, cb)
          git.reset(ref, "hard", opts, cb)
        end,
        "hard",
        "This will discard all uncommitted changes."
      )
    end)
    :action(
      "k",
      "keep     (HEAD and index, keeping uncommitted)" .. context_label,
      function(_popup_data)
        reset_with_prompt(
          repo_state,
          context,
          "Reset " .. branch .. " to: ",
          function(ref, opts, cb)
            git.reset_keep(ref, opts, cb)
          end,
          "keep"
        )
      end
    )
    :action("i", "index    (only)", function(_popup_data)
      M._reset_index(repo_state)
    end)
    :action("w", "worktree (only)" .. context_label, function(_popup_data)
      reset_with_confirmation(repo_state, context, "Reset worktree to: ", function(ref, opts, cb)
        git.reset_worktree(ref, opts, cb)
      end, "worktree", "This will discard all uncommitted changes in the working tree.")
    end)
    :build()

  reset_popup:show()
end

--- Reset index only (unstage all)
---@param repo_state RepoState
function M._reset_index(repo_state)
  vim.notify("[gitlad] Resetting index...", vim.log.levels.INFO)
  git.reset_index({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Index reset (all files unstaged)", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Reset failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
