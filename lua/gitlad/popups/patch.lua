---@mod gitlad.popups.patch Patch popup
---@brief [[
--- Transient-style patch popup for creating and applying patches.
--- Keybinding: W (matches vanilla magit, unchanged by evil-collection)
---
--- Actions:
---   W c  Create patches (git format-patch)
---   W a  Apply plain patch (git apply, no commits)
---   W s  Save diff as patch file
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local git = require("gitlad.git")

---@class PatchContext
---@field commit string|nil Selected commit hash (used as range base for format-patch)
---@field file_path string|nil Current file path (for saving diff as patch)
---@field staged boolean|nil Whether context is from staged section

--- Create and show the patch popup
---@param repo_state RepoState
---@param context? PatchContext
function M.open(repo_state, context)
  local patch_popup = popup
    .builder()
    :name("Patch")
    -- Actions
    :group_heading("Create")
    :action("c", "Create patches", function(popup_data)
      M._create_patches(repo_state, popup_data, context)
    end)
    :group_heading("Apply")
    :action("a", "Apply plain patch", function(popup_data)
      M._apply_plain_patch(repo_state, popup_data, context)
    end)
    :action("w", "Apply patches (git am)", function(_popup_data)
      -- Shortcut into the am popup
      require("gitlad.popups.am").open(repo_state)
    end)
    :group_heading("Save")
    :action("s", "Save diff as patch", function(_popup_data)
      M._save_diff_as_patch(repo_state, context)
    end)
    :build()

  patch_popup:show()
end

--- Create patches from a commit range (git format-patch)
---@param repo_state RepoState
---@param _popup_data PopupData
---@param context? PatchContext
function M._create_patches(repo_state, _popup_data, context)
  -- Build a sub-popup with format-patch options
  local create_popup = popup
    .builder()
    :name("Create patches")
    -- Switches
    :switch("l", "cover-letter", "Generate cover letter")
    :switch("R", "rfc", "Use [RFC PATCH] prefix")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("n", "numbered", "Force numbered patches")
    -- Options
    :option("v", "reroll-count", "", "Reroll count (version number)")
    :option("o", "output-directory", "", "Output directory")
    :option("p", "subject-prefix", "", "Subject prefix")
    -- Action
    :group_heading("Create")
    :action("c", "Create", function(create_data)
      local default_range = context and context.commit and (context.commit .. "^..HEAD") or nil
      vim.ui.input({
        prompt = "Range or count: ",
        default = default_range or "-1",
      }, function(input)
        if not input or input == "" then
          return
        end

        local args = create_data:get_arguments()

        vim.notify("[gitlad] Creating patches...", vim.log.levels.INFO)

        git.format_patch(input, args, { cwd = repo_state.repo_root }, function(success, output, err)
          vim.schedule(function()
            if success then
              vim.notify("[gitlad] Patches created:\n" .. (output or ""), vim.log.levels.INFO)
            else
              vim.notify(
                "[gitlad] format-patch failed: " .. (err or "unknown error"),
                vim.log.levels.ERROR
              )
            end
          end)
        end)
      end)
    end)
    :build()

  create_popup:show()
end

--- Apply a plain patch file (git apply - no commits)
---@param repo_state RepoState
---@param _popup_data PopupData
---@param context? PatchContext
function M._apply_plain_patch(repo_state, _popup_data, context)
  -- Default to file at point if it looks like a patch file
  local default_file = nil
  if context and context.file_path then
    if context.file_path:match("%.patch$") or context.file_path:match("%.diff$") then
      default_file = context.file_path
    end
  end

  -- Build a sub-popup with apply options
  local apply_popup = popup
    .builder()
    :name("Apply patch")
    -- Switches
    :switch("3", "3way", "Fall back on 3-way merge")
    :switch("i", "index", "Also apply to index")
    :switch("c", "cached", "Only apply to index")
    :switch("R", "reverse", "Apply in reverse")
    -- Action
    :group_heading("Apply")
    :action("a", "Apply", function(apply_data)
      -- Prompt for patch file
      vim.ui.input({
        prompt = "Patch file: ",
        default = default_file,
        completion = "file",
      }, function(input)
        if not input or input == "" then
          return
        end

        local args = apply_data:get_arguments()

        vim.notify("[gitlad] Applying patch...", vim.log.levels.INFO)

        git.apply_patch_file(
          input,
          args,
          { cwd = repo_state.repo_root },
          function(success, output, err)
            vim.schedule(function()
              if success then
                vim.notify("[gitlad] Patch applied", vim.log.levels.INFO)
                repo_state:refresh_status(true)
              else
                vim.notify(
                  "[gitlad] Apply failed: " .. (err or "unknown error"),
                  vim.log.levels.ERROR
                )
              end
            end)
          end
        )
      end)
    end)
    :build()

  apply_popup:show()
end

--- Save current diff as a patch file
---@param repo_state RepoState
---@param context? PatchContext
function M._save_diff_as_patch(repo_state, context)
  -- Determine what diff to save
  local diff_args = { "diff" }
  local default_name = "patch.diff"

  if context and context.staged then
    table.insert(diff_args, "--cached")
    default_name = "staged.patch"
  end

  if context and context.file_path then
    table.insert(diff_args, "--")
    table.insert(diff_args, context.file_path)
    -- Use filename as base for patch name
    local basename = context.file_path:match("([^/]+)$") or context.file_path
    default_name = basename .. ".patch"
  end

  vim.ui.input({
    prompt = "Save patch to: ",
    default = default_name,
    completion = "file",
  }, function(input)
    if not input or input == "" then
      return
    end

    local cli = require("gitlad.git.cli")
    cli.run_async(diff_args, { cwd = repo_state.repo_root }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.notify("[gitlad] Failed to generate diff", vim.log.levels.ERROR)
          return
        end

        if #result.stdout == 0 then
          vim.notify("[gitlad] No diff to save", vim.log.levels.WARN)
          return
        end

        -- Resolve output path relative to repo root
        local output_path = input
        if not output_path:match("^/") then
          output_path = repo_state.repo_root .. "/" .. output_path
        end

        local file = io.open(output_path, "w")
        if not file then
          vim.notify("[gitlad] Cannot write to: " .. output_path, vim.log.levels.ERROR)
          return
        end

        file:write(table.concat(result.stdout, "\n"))
        if #result.stdout > 0 then
          file:write("\n")
        end
        file:close()

        vim.notify("[gitlad] Patch saved: " .. input, vim.log.levels.INFO)
      end)
    end)
  end)
end

return M
