-- End-to-end tests for local branch upstream workflow
-- Tests the common workflow where upstream is a local branch (e.g. from another worktree)
-- rather than a remote ref like origin/main.
--
-- When branch.<name>.remote = "." and branch.<name>.merge = "refs/heads/<branch>",
-- git treats a local branch as the upstream. This is common in worktree-based workflows.
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
      _G.child = child
    end,
    post_case = function()
      if _G.child then
        _G.child.stop()
        _G.child = nil
      end
    end,
  },
})

--- Helper: create a repo with a main branch that has commits ahead of a feature branch,
--- with the feature branch tracking main as a local upstream.
--- Returns repo_path. Leaves the child on the feature branch.
local function setup_local_upstream_repo(child)
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create feature branch from here
  helpers.git(child, repo, "checkout -b feature")

  -- Add a commit on feature
  helpers.create_file(child, repo, "feature.txt", "feature work")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature work"')

  -- Go back to main and add a commit ahead
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "file.txt", "updated on main")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Update file on main"')

  -- Switch back to feature
  helpers.git(child, repo, "checkout feature")

  -- Set main as local upstream: remote = ".", merge = "refs/heads/main"
  helpers.git(child, repo, "config branch.feature.remote .")
  helpers.git(child, repo, "config branch.feature.merge refs/heads/main")

  return repo
end

T["local upstream"] = MiniTest.new_set()

T["local upstream"]["status shows local branch as upstream with ahead/behind counts"] = function()
  local child = _G.child
  local repo = setup_local_upstream_repo(child)

  helpers.open_gitlad(child, repo)

  -- The status buffer should show "main" as the upstream
  -- (not "origin/main" - there's no remote involved)
  local found_upstream = helpers.wait_for_status_content(child, "main", 3000)
  eq(found_upstream, true)

  -- Get full buffer content for inspection
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local content = table.concat(lines, "\n")

  -- Should show the branch is tracking main (local upstream)
  -- The Merge: line shows the upstream
  local has_merge_line = content:find("Merge:") ~= nil
  eq(has_merge_line, true)

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["merge line highlights local upstream with local ref style"] = function()
  local child = _G.child
  local repo = setup_local_upstream_repo(child)

  helpers.open_gitlad(child, repo)

  -- Wait for the Merge line to appear
  local found_merge = helpers.wait_for_status_content(child, "Merge:", 3000)
  eq(found_merge, true)

  -- The Merge line ref should be highlighted as GitladRefCombined (local/red style)
  -- NOT GitladRefRemote (green/remote style)
  local has_local_hl = helpers.status_line_has_highlight(child, "^Merge:", "GitladRefCombined")
  eq(has_local_hl, true)

  local has_remote_hl = helpers.status_line_has_highlight(child, "^Merge:", "GitladRefRemote")
  eq(has_remote_hl, false)

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["rebase popup shows local upstream ref"] = function()
  local child = _G.child
  local repo = setup_local_upstream_repo(child)

  helpers.open_gitlad(child, repo)

  -- Open rebase popup
  child.type_keys("r")
  helpers.wait_for_popup(child)

  -- Get popup content
  child.lua([[
    _popup_buf = vim.api.nvim_get_current_buf()
    _popup_lines = vim.api.nvim_buf_get_lines(_popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[_popup_lines]])

  -- The upstream action should show "main" (the local upstream)
  -- not "@{upstream}, setting it" (which means no upstream is configured)
  local found_main_upstream = false
  for _, line in ipairs(lines) do
    -- Should show "u  main" as the upstream action label
    if line:match("u%s+main") then
      found_main_upstream = true
    end
  end
  eq(found_main_upstream, true)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["rebase onto local upstream succeeds"] = function()
  local child = _G.child
  local repo = setup_local_upstream_repo(child)

  -- Verify starting state: feature is 1 ahead, 1 behind main
  local log_before = helpers.git(child, repo, "log --oneline --all")

  helpers.open_gitlad(child, repo)

  -- Open rebase popup
  child.type_keys("r")
  helpers.wait_for_popup(child)

  -- Press u to rebase onto upstream (which is local branch "main")
  child.type_keys("u")

  -- Wait for rebase to complete - status should refresh
  -- After successful rebase, we should see "Rebase complete" message
  local got_message = helpers.wait_for_message(child, "Rebase complete", 5000)
  eq(got_message, true)

  -- Verify the rebase actually worked:
  -- feature should now be based on top of main's latest commit
  -- The "Update file on main" commit should be an ancestor of feature
  local merge_base = helpers.git(child, repo, "merge-base main feature")
  local main_head = helpers.git(child, repo, "rev-parse main")
  -- After rebase, feature's base should be main's HEAD
  eq(vim.trim(merge_base), vim.trim(main_head))

  -- feature should still have its own commit on top
  local feature_log = helpers.git(child, repo, "log --oneline feature ^main")
  eq(feature_log:find("Add feature work") ~= nil, true)

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["rebase onto local upstream with conflicts shows in-progress state"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create initial commit on main
  helpers.create_file(child, repo, "shared.txt", "original")
  helpers.git(child, repo, "add shared.txt")
  helpers.git(child, repo, 'commit -m "Initial"')

  -- Create feature branch
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "shared.txt", "feature version")
  helpers.git(child, repo, "add shared.txt")
  helpers.git(child, repo, 'commit -m "Feature change"')

  -- Go back to main and make a conflicting change
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "shared.txt", "main version")
  helpers.git(child, repo, "add shared.txt")
  helpers.git(child, repo, 'commit -m "Main change"')

  -- Switch to feature, set local upstream
  helpers.git(child, repo, "checkout feature")
  helpers.git(child, repo, "config branch.feature.remote .")
  helpers.git(child, repo, "config branch.feature.merge refs/heads/main")

  helpers.open_gitlad(child, repo)

  -- Open rebase popup and rebase onto upstream
  child.type_keys("r")
  helpers.wait_for_popup(child)
  child.type_keys("u")

  -- Should get a conflict notification
  local got_conflict = helpers.wait_for_message(child, "resolve conflicts", 5000)
  eq(got_conflict, true)

  -- Wait for status buffer to be restored and refreshed
  helpers.wait_for_buffer(child, "gitlad://status", 5000)
  helpers.wait_for_status_content(child, "Rebasing", 5000)

  -- Rebase popup should now show in-progress actions
  child.type_keys("r")
  helpers.wait_for_popup(child)

  child.lua([[
    _popup_buf = vim.api.nvim_get_current_buf()
    _popup_lines = vim.api.nvim_buf_get_lines(_popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[_popup_lines]])

  local found_continue = false
  local found_abort = false
  for _, line in ipairs(lines) do
    if line:match("r%s+Continue") then
      found_continue = true
    end
    if line:match("a%s+Abort") then
      found_abort = true
    end
  end
  eq(found_continue, true)
  eq(found_abort, true)

  -- Abort to clean up
  child.type_keys("a")
  helpers.wait_for_message(child, "Rebase aborted", 3000)

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["setting local upstream via branch popup updates status view"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create main with a commit
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create feature branch with an extra commit
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature work")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature work"')

  -- Open status WITHOUT upstream configured
  helpers.open_gitlad(child, repo)

  -- Verify no Merge line initially
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  local content = table.concat(lines, "\n")
  eq(content:find("Merge:") == nil, true)

  -- Mock prompt_for_ref to auto-respond with "main" (simulates user typing in b u prompt)
  child.lua([[
    local prompt = require("gitlad.utils.prompt")
    _G._original_prompt_for_ref = prompt.prompt_for_ref
    prompt.prompt_for_ref = function(opts, callback)
      vim.schedule(function()
        callback("main")
      end)
    end
  ]])

  -- Open branch popup and press u to set upstream
  child.type_keys("b")
  helpers.wait_for_popup(child)
  child.type_keys("u")

  -- Wait for async config operations to complete
  helpers.wait_short(child, 500)

  -- Close popup to return to status view
  child.type_keys("q")
  helpers.wait_for_popup_closed(child)
  helpers.wait_for_buffer(child, "gitlad://status", 3000)

  -- Wait for status to show the Merge line with the local upstream
  -- The on_config_change handler triggers refresh_status(true) in the background
  local found_merge = helpers.wait_for_status_content(child, "Merge:", 5000)
  eq(found_merge, true)

  -- Verify the upstream branch name appears
  local found_main = helpers.wait_for_status_content(child, "main", 3000)
  eq(found_main, true)

  -- Should show unpushed commits (feature has 1 commit not in main)
  local found_unpushed = helpers.wait_for_status_content(child, "Unmerged into", 3000)
  eq(found_unpushed, true)

  -- Restore original prompt
  child.lua([[
    local prompt = require("gitlad.utils.prompt")
    prompt.prompt_for_ref = _G._original_prompt_for_ref
  ]])

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["setting slashed local branch as upstream works via branch popup"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create main with a commit
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create a branch with a slash in its name (common convention)
  helpers.git(child, repo, "checkout -b feature/conflict-merge")
  helpers.create_file(child, repo, "conflict.txt", "conflict work")
  helpers.git(child, repo, "add conflict.txt")
  helpers.git(child, repo, 'commit -m "Add conflict file"')

  -- Go back to main
  helpers.git(child, repo, "checkout main")

  -- Open status on main, no upstream set
  helpers.open_gitlad(child, repo)

  -- Mock prompt_for_ref to return "feature/conflict-merge" (a local branch with slash)
  child.lua([[
    local prompt = require("gitlad.utils.prompt")
    _G._original_prompt_for_ref = prompt.prompt_for_ref
    prompt.prompt_for_ref = function(opts, callback)
      vim.schedule(function()
        callback("feature/conflict-merge")
      end)
    end
  ]])

  -- Open branch popup and press u to set upstream
  child.type_keys("b")
  helpers.wait_for_popup(child)
  child.type_keys("u")

  -- Wait for async config operations to complete
  helpers.wait_short(child, 500)

  -- Close popup to return to status view
  child.type_keys("q")
  helpers.wait_for_popup_closed(child)
  helpers.wait_for_buffer(child, "gitlad://status", 3000)

  -- Verify git config was set correctly (remote = ".", not "feature")
  child.lua(string.format(
    [[
    _G._debug_remote = vim.fn.system("git -C %s config branch.main.remote"):gsub("%%s+", "")
    _G._debug_merge = vim.fn.system("git -C %s config branch.main.merge"):gsub("%%s+", "")
  ]],
    repo,
    repo
  ))
  local debug_remote = child.lua_get([[_G._debug_remote]])
  local debug_merge = child.lua_get([[_G._debug_merge]])
  eq(debug_remote, ".")
  eq(debug_merge, "refs/heads/feature/conflict-merge")

  -- Wait for status to show the Merge line with the local upstream
  local found_merge = helpers.wait_for_status_content(child, "Merge:", 5000)
  eq(found_merge, true)

  -- Verify the upstream branch name appears (the full slashed name)
  local found_upstream = helpers.wait_for_status_content(child, "feature/conflict-merge", 3000)
  eq(found_upstream, true)

  -- Restore original prompt
  child.lua([[
    local prompt = require("gitlad.utils.prompt")
    prompt.prompt_for_ref = _G._original_prompt_for_ref
  ]])

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["push popup shows local branch name as upstream label"] = function()
  local child = _G.child
  local repo = setup_local_upstream_repo(child)

  helpers.open_gitlad(child, repo)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Get popup content
  child.lua([[
    _popup_buf = vim.api.nvim_get_current_buf()
    _popup_lines = vim.api.nvim_buf_get_lines(_popup_buf, 0, -1, false)
  ]])
  local lines = child.lua_get([[_popup_lines]])

  -- The upstream action (u) should show "main" (the local upstream branch name)
  -- NOT "./main" or "@{upstream}, setting it"
  local found_main_upstream = false
  local found_dot_slash = false
  for _, line in ipairs(lines) do
    if line:match("u%s+main") then
      found_main_upstream = true
    end
    -- Make sure we don't show "./main" which is the broken behavior
    if line:match("%./main") then
      found_dot_slash = true
    end
  end
  eq(found_main_upstream, true)
  eq(found_dot_slash, false)

  child.type_keys("q")
  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["push to upstream succeeds with local upstream"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Create a simple fast-forward scenario:
  -- main has initial commit, feature has main + extra commit
  -- So "git push . feature:refs/heads/main" can fast-forward main
  helpers.create_file(child, repo, "file.txt", "initial content")
  helpers.git(child, repo, "add file.txt")
  helpers.git(child, repo, 'commit -m "Initial commit"')

  -- Create feature branch from main (includes all of main's history)
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "feature.txt", "feature work")
  helpers.git(child, repo, "add feature.txt")
  helpers.git(child, repo, 'commit -m "Add feature work"')

  -- Set main as local upstream
  helpers.git(child, repo, "config branch.feature.remote .")
  helpers.git(child, repo, "config branch.feature.merge refs/heads/main")

  -- Record main's HEAD before push
  local main_before = helpers.git(child, repo, "rev-parse main")

  helpers.open_gitlad(child, repo)

  -- Open push popup
  child.type_keys("p")
  helpers.wait_for_popup(child)

  -- Press u to push to upstream (local branch "main")
  child.type_keys("u")

  -- Wait for push to complete
  local got_message = helpers.wait_for_message(child, "Push complete", 5000)
  eq(got_message, true)

  -- Verify the push actually worked:
  -- "git push . feature:refs/heads/main" fast-forwards main to include feature's commits
  local main_after = helpers.git(child, repo, "rev-parse main")
  -- main should have moved (not the same as before)
  eq(vim.trim(main_before) ~= vim.trim(main_after), true)

  -- feature's HEAD should now equal main's HEAD (fast-forward)
  local feature_head = helpers.git(child, repo, "rev-parse feature")
  eq(vim.trim(main_after), vim.trim(feature_head))

  helpers.cleanup_repo(child, repo)
end

T["local upstream"]["fetch upstream with local upstream shows nothing to fetch"] = function()
  local child = _G.child
  local repo = setup_local_upstream_repo(child)

  helpers.open_gitlad(child, repo)

  -- Open fetch popup
  child.type_keys("f")
  helpers.wait_for_popup(child)

  -- Press u to fetch from upstream
  child.type_keys("u")

  -- Should show "nothing to fetch" message since upstream is local
  local got_message = helpers.wait_for_message(child, "local branch", 3000)
  eq(got_message, true)

  helpers.cleanup_repo(child, repo)
end

return T
