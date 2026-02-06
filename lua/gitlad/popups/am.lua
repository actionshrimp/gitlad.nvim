---@mod gitlad.popups.am Apply patches (git am) popup
---@brief [[
--- Transient-style popup for applying mailbox-format patches (git am).
--- Keybinding: w (matches vanilla magit, unchanged by evil-collection)
---
--- Sequencer-aware: shows different actions based on whether git am is in progress.
---
--- Normal state:
---   w w  Apply patch file(s)
---   w m  Apply maildir
---
--- In-progress state:
---   w w  Continue (git am --continue)
---   w s  Skip current patch (git am --skip)
---   w a  Abort (git am --abort)
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

--- Create and show the am popup
---@param repo_state RepoState
function M.open(repo_state)
  -- Check if am is in progress
  local git_patch = require("gitlad.git.git_patch")
  local am_state = git_patch.get_am_state({ cwd = repo_state.repo_root })

  if am_state.am_in_progress then
    M._open_in_progress_popup(repo_state, am_state)
  else
    M._open_normal_popup(repo_state)
  end
end

--- Open popup when am is NOT in progress
---@param repo_state RepoState
function M._open_normal_popup(repo_state)
  local am_popup = popup
    .builder()
    :name("Apply patches")
    -- Switches
    :switch("3", "3way", "Fall back on 3-way merge")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("k", "keep", "Keep subject line intact")
    :switch("b", "keep-non-patch", "Limit email cruft removal")
    :switch("d", "committer-date-is-author-date", "Use author date as committer date")
    :switch("t", "ignore-date", "Use current time as author date")
    -- Actions
    :group_heading("Apply")
    :action("w", "Apply patch file(s)", function(popup_data)
      M._am_apply(repo_state, popup_data)
    end)
    :action("m", "Apply maildir", function(popup_data)
      M._am_maildir(repo_state, popup_data)
    end)
    :build()

  am_popup:show()
end

--- Open popup when am IS in progress
---@param repo_state RepoState
---@param am_state AmState
function M._open_in_progress_popup(repo_state, am_state)
  local progress = ""
  if am_state.current_patch and am_state.last_patch then
    progress = am_state.current_patch .. "/" .. am_state.last_patch
  end

  local name = "Apply patches"
  if progress ~= "" then
    name = name .. " (in progress: " .. progress .. ")"
  else
    name = name .. " (in progress)"
  end

  local am_popup = popup
    .builder()
    :name(name)
    -- Actions for in-progress state
    :group_heading("Sequencer")
    :action("w", "Continue", function(_popup_data)
      M._am_continue(repo_state)
    end)
    :action("s", "Skip", function(_popup_data)
      M._am_skip(repo_state)
    end)
    :action("a", "Abort", function(_popup_data)
      M._am_abort(repo_state)
    end)
    :build()

  am_popup:show()
end

--- Apply patch files using git am
---@param repo_state RepoState
---@param popup_data PopupData
function M._am_apply(repo_state, popup_data)
  vim.ui.input({
    prompt = "Patch file(s): ",
    completion = "file",
  }, function(input)
    if not input or input == "" then
      return
    end

    local args = popup_data:get_arguments()
    -- Split input on spaces to allow multiple files
    local files = vim.split(input, "%s+", { trimempty = true })

    vim.notify("[gitlad] Applying patches...", vim.log.levels.INFO)

    git.am(files, args, { cwd = repo_state.repo_root }, function(success, output, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Patches applied", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          if err and (err:match("conflict") or err:match("patch does not apply")) then
            vim.notify(
              "[gitlad] Patch has conflicts. Resolve them and press w to continue.",
              vim.log.levels.WARN
            )
          else
            vim.notify(
              "[gitlad] git am failed: " .. (err or output or "unknown error"),
              vim.log.levels.ERROR
            )
          end
          repo_state:refresh_status(true)
        end
      end)
    end)
  end)
end

--- Apply maildir patches using git am
---@param repo_state RepoState
---@param popup_data PopupData
function M._am_maildir(repo_state, popup_data)
  vim.ui.input({
    prompt = "Maildir path: ",
    completion = "dir",
  }, function(input)
    if not input or input == "" then
      return
    end

    local args = popup_data:get_arguments()

    vim.notify("[gitlad] Applying maildir patches...", vim.log.levels.INFO)

    git.am({ input }, args, { cwd = repo_state.repo_root }, function(success, output, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] Maildir patches applied", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          if err and (err:match("conflict") or err:match("patch does not apply")) then
            vim.notify(
              "[gitlad] Patch has conflicts. Resolve them and press w to continue.",
              vim.log.levels.WARN
            )
          else
            vim.notify(
              "[gitlad] git am failed: " .. (err or output or "unknown error"),
              vim.log.levels.ERROR
            )
          end
          repo_state:refresh_status(true)
        end
      end)
    end)
  end)
end

--- Continue an in-progress git am
---@param repo_state RepoState
function M._am_continue(repo_state)
  vim.notify("[gitlad] Continuing git am...", vim.log.levels.INFO)

  git.am_continue({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] git am continued", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Continue failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Skip the current patch during git am
---@param repo_state RepoState
function M._am_skip(repo_state)
  vim.notify("[gitlad] Skipping patch...", vim.log.levels.INFO)

  git.am_skip({ cwd = repo_state.repo_root }, function(success, err)
    vim.schedule(function()
      if success then
        vim.notify("[gitlad] Patch skipped", vim.log.levels.INFO)
        repo_state:refresh_status(true)
      else
        vim.notify("[gitlad] Skip failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        repo_state:refresh_status(true)
      end
    end)
  end)
end

--- Abort an in-progress git am
---@param repo_state RepoState
function M._am_abort(repo_state)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Abort git am? This will discard applied patches.",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    vim.notify("[gitlad] Aborting git am...", vim.log.levels.INFO)

    git.am_abort({ cwd = repo_state.repo_root }, function(success, err)
      vim.schedule(function()
        if success then
          vim.notify("[gitlad] git am aborted", vim.log.levels.INFO)
          repo_state:refresh_status(true)
        else
          vim.notify("[gitlad] Abort failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
