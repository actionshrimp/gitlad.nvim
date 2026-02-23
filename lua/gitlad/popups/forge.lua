---@mod gitlad.popups.forge Forge popup
---@brief [[
--- Transient-style forge popup for GitHub integration.
--- Opened via N keybinding in status buffer.
---@brief ]]

local M = {}

local popup = require("gitlad.ui.popup")
local forge = require("gitlad.forge")

--- Open the forge popup
--- Detects the forge provider first, then shows the popup.
---@param repo_state RepoState
function M.open(repo_state)
  local provider = forge.get(repo_state.repo_root)

  if provider then
    M._show_popup(repo_state, provider)
    return
  end

  -- Detect provider (async)
  vim.notify("[gitlad] Detecting forge provider...", vim.log.levels.INFO)
  forge.detect(repo_state.repo_root, function(detected_provider, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Forge: " .. err, vim.log.levels.WARN)
        return
      end

      if not detected_provider then
        vim.notify("[gitlad] No forge provider detected", vim.log.levels.WARN)
        return
      end

      M._show_popup(repo_state, detected_provider)
    end)
  end)
end

--- Show the forge popup with detected provider
---@param repo_state RepoState
---@param provider ForgeProvider
function M._show_popup(repo_state, provider)
  local title = "Forge ("
    .. provider.provider_type
    .. ": "
    .. provider.owner
    .. "/"
    .. provider.repo
    .. ")"

  local forge_popup = popup
    .builder()
    :name(title)
    :group_heading("Pull Requests")
    :action("l", "List pull requests", function()
      M._list_prs(repo_state, provider)
    end)
    :action("v", "View current branch PR", function()
      M._view_current_pr(repo_state, provider)
    end)
    :action("c", "Checkout PR branch", function()
      M._checkout_pr(repo_state)
    end)
    :group_heading("Actions")
    :action("n", "Create pull request", function()
      M._create_pr(repo_state)
    end)
    :action("m", "Merge pull request", function()
      M._merge_pr(repo_state)
    end)
    :action("C", "Close pull request", function()
      M._close_pr(repo_state)
    end)
    :action("R", "Reopen pull request", function()
      M._reopen_pr(repo_state)
    end)
    :action("o", "Open in browser", function()
      M._open_in_browser(repo_state)
    end)
    :build()

  forge_popup:show()
end

--- List pull requests (opens PR list view)
---@param repo_state RepoState
---@param provider ForgeProvider
function M._list_prs(repo_state, provider)
  local pr_list_view = require("gitlad.ui.views.pr_list")
  pr_list_view.open(repo_state, provider, {})
end

--- View the PR for the current branch
---@param repo_state RepoState
---@param provider ForgeProvider
function M._view_current_pr(repo_state, provider)
  local branch = repo_state.status and repo_state.status.branch
  if not branch or branch == "" then
    vim.notify("[gitlad] No branch detected", vim.log.levels.WARN)
    return
  end

  vim.notify("[gitlad] Finding PR for branch: " .. branch .. "...", vim.log.levels.INFO)

  provider:list_prs({ state = "open", limit = 50 }, function(prs, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to list PRs: " .. err, vim.log.levels.ERROR)
        return
      end

      if not prs then
        vim.notify("[gitlad] No PRs found", vim.log.levels.INFO)
        return
      end

      -- Find PR matching current branch
      for _, pr in ipairs(prs) do
        if pr.head_ref == branch then
          local pr_detail_view = require("gitlad.ui.views.pr_detail")
          pr_detail_view.open(repo_state, provider, pr.number)
          return
        end
      end

      vim.notify("[gitlad] No open PR found for branch: " .. branch, vim.log.levels.INFO)
    end)
  end)
end

--- Checkout a PR branch
---@param repo_state RepoState
function M._checkout_pr(repo_state)
  vim.ui.input({ prompt = "PR number: " }, function(input)
    if not input or input == "" then
      return
    end

    local pr_number = tonumber(input)
    if not pr_number then
      vim.notify("[gitlad] Invalid PR number: " .. input, vim.log.levels.ERROR)
      return
    end

    local output = require("gitlad.ui.views.output")
    local viewer = output.create({
      title = "PR Checkout",
      command = "gh pr checkout " .. pr_number,
    })

    vim.fn.jobstart({ "gh", "pr", "checkout", tostring(pr_number) }, {
      cwd = repo_state.repo_root,
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              vim.schedule(function()
                viewer:append(line, false)
              end)
            end
          end
        end
      end,
      on_stderr = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              vim.schedule(function()
                viewer:append(line, true)
              end)
            end
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          viewer:complete(code)
          if code == 0 then
            vim.notify("[gitlad] Checked out PR #" .. pr_number, vim.log.levels.INFO)
            repo_state:refresh_status(true)
          else
            vim.notify("[gitlad] Failed to checkout PR #" .. pr_number, vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

--- Run a gh CLI command with streaming output viewer
---@param repo_state RepoState
---@param cmd string[] Command array
---@param title string Viewer title
---@param on_success? fun() Optional success callback
function M.run_gh_command(repo_state, cmd, title, on_success)
  local output = require("gitlad.ui.views.output")
  local viewer = output.create({
    title = title,
    command = table.concat(cmd, " "),
  })

  vim.fn.jobstart(cmd, {
    cwd = repo_state.repo_root,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.schedule(function()
              viewer:append(line, false)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.schedule(function()
              viewer:append(line, true)
            end)
          end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        viewer:complete(code)
        if code == 0 then
          if on_success then
            on_success()
          end
          repo_state:refresh_status(true)
        end
      end)
    end,
  })
end

--- Create a new PR (opens gh pr create --web)
---@param repo_state RepoState
function M._create_pr(repo_state)
  M.run_gh_command(repo_state, { "gh", "pr", "create", "--web" }, "Create PR", function()
    vim.notify("[gitlad] PR creation opened in browser", vim.log.levels.INFO)
  end)
end

--- Merge a PR
---@param repo_state RepoState
function M._merge_pr(repo_state)
  vim.ui.input({ prompt = "PR number to merge: " }, function(input)
    if not input or input == "" then
      return
    end

    local pr_number = tonumber(input)
    if not pr_number then
      vim.notify("[gitlad] Invalid PR number: " .. input, vim.log.levels.ERROR)
      return
    end

    -- Prompt for merge strategy
    vim.ui.select({ "merge", "squash", "rebase" }, {
      prompt = "Merge strategy:",
    }, function(choice)
      if not choice then
        return
      end

      M.run_gh_command(
        repo_state,
        { "gh", "pr", "merge", tostring(pr_number), "--" .. choice },
        "Merge PR #" .. pr_number,
        function()
          vim.notify(
            "[gitlad] PR #" .. pr_number .. " merged (" .. choice .. ")",
            vim.log.levels.INFO
          )
        end
      )
    end)
  end)
end

--- Close a PR
---@param repo_state RepoState
function M._close_pr(repo_state)
  vim.ui.input({ prompt = "PR number to close: " }, function(input)
    if not input or input == "" then
      return
    end

    local pr_number = tonumber(input)
    if not pr_number then
      vim.notify("[gitlad] Invalid PR number: " .. input, vim.log.levels.ERROR)
      return
    end

    M.run_gh_command(
      repo_state,
      { "gh", "pr", "close", tostring(pr_number) },
      "Close PR #" .. pr_number,
      function()
        vim.notify("[gitlad] PR #" .. pr_number .. " closed", vim.log.levels.INFO)
      end
    )
  end)
end

--- Reopen a PR
---@param repo_state RepoState
function M._reopen_pr(repo_state)
  vim.ui.input({ prompt = "PR number to reopen: " }, function(input)
    if not input or input == "" then
      return
    end

    local pr_number = tonumber(input)
    if not pr_number then
      vim.notify("[gitlad] Invalid PR number: " .. input, vim.log.levels.ERROR)
      return
    end

    M.run_gh_command(
      repo_state,
      { "gh", "pr", "reopen", tostring(pr_number) },
      "Reopen PR #" .. pr_number,
      function()
        vim.notify("[gitlad] PR #" .. pr_number .. " reopened", vim.log.levels.INFO)
      end
    )
  end)
end

--- Open the current branch's PR in browser
---@param repo_state RepoState
function M._open_in_browser(repo_state)
  M.run_gh_command(repo_state, { "gh", "pr", "view", "--web" }, "Open PR in browser", function()
    vim.notify("[gitlad] PR opened in browser", vim.log.levels.INFO)
  end)
end

return M
