local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[require("gitlad").setup({})]])
    end,
    post_once = child.stop,
  },
})

-- =============================================================================
-- Helpers
-- =============================================================================

local function wait_for_tab_count(target, timeout)
  timeout = timeout or 3000
  child.lua(string.format(
    [[
    vim.wait(%d, function()
      return vim.fn.tabpagenr('$') == %d
    end, 10)
  ]],
    timeout,
    target
  ))
end

--- Create a repo with a merge conflict
---@return string repo_path
local function create_repo_with_merge_conflict()
  local repo = helpers.create_test_repo(child)

  -- Create base file
  helpers.create_file(child, repo, "file.lua", "line1\nline2\nline3\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'base'")

  -- Create a branch and make changes
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "file.lua", "line1\nfeature_line2\nline3\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'feature change'")

  -- Go back to main and make conflicting changes
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "file.lua", "line1\nmain_line2\nline3\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'main change'")

  -- Attempt merge (will conflict)
  child.lua(string.format(
    [[
    vim.fn.system('cd %q && git merge feature 2>&1 || true')
  ]],
    repo
  ))

  return repo
end

--- Create a repo with multiple conflicted files
---@return string repo_path
local function create_repo_with_multiple_conflicts()
  local repo = helpers.create_test_repo(child)

  -- Create base files
  helpers.create_file(child, repo, "a.lua", "aaa\n")
  helpers.create_file(child, repo, "b.lua", "bbb\n")
  helpers.git(child, repo, "add a.lua b.lua")
  helpers.git(child, repo, "commit -m 'base'")

  -- Feature branch
  helpers.git(child, repo, "checkout -b feature")
  helpers.create_file(child, repo, "a.lua", "aaa_feature\n")
  helpers.create_file(child, repo, "b.lua", "bbb_feature\n")
  helpers.git(child, repo, "add a.lua b.lua")
  helpers.git(child, repo, "commit -m 'feature'")

  -- Main conflicting changes
  helpers.git(child, repo, "checkout main")
  helpers.create_file(child, repo, "a.lua", "aaa_main\n")
  helpers.create_file(child, repo, "b.lua", "bbb_main\n")
  helpers.git(child, repo, "add a.lua b.lua")
  helpers.git(child, repo, "commit -m 'main'")

  -- Merge (will conflict)
  child.lua(string.format([[vim.fn.system('cd %q && git merge feature 2>&1 || true')]], repo))

  return repo
end

--- Open the merge 3-way diff viewer
local function open_merge_three_way(repo)
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_merge(%q, function(spec, err)
      if spec then
        vim.schedule(function()
          require("gitlad.ui.views.diff").open(spec)
        end)
      end
    end)
  ]],
    repo
  ))
  wait_for_tab_count(2)
end

--- Get a value from the active view
local function view_get(expr)
  return child.lua_get(
    "(function() local _v = require('gitlad.ui.views.diff').get_active(); return "
      .. expr
      .. " end)()"
  )
end

--- Get a buffer option from the active view's buffer_triple
local function triple_buf_opt(buf_field, opt_name)
  return child.lua_get(
    string.format(
      "(function() local _v = require('gitlad.ui.views.diff').get_active(); return vim.bo[_v.buffer_triple.%s].%s end)()",
      buf_field,
      opt_name
    )
  )
end

--- Check if buffer lines contain a pattern
local function buf_has_pattern(buf_field, pattern)
  return child.lua_get(string.format(
    [[(function()
      local _v = require('gitlad.ui.views.diff').get_active()
      local lines = vim.api.nvim_buf_get_lines(_v.buffer_triple.%s, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:match(%q) then return true end
      end
      return false
    end)()]],
    buf_field,
    pattern
  ))
end

--- Focus a window in the active view
local function focus_win(win_field)
  child.lua(string.format(
    [[
    local view = require("gitlad.ui.views.diff").get_active()
    vim.api.nvim_set_current_win(view.buffer_triple.%s)
  ]],
    win_field
  ))
end

-- =============================================================================
-- Basic layout tests
-- =============================================================================

T["merge 3-way"] = MiniTest.new_set()

T["merge 3-way"]["opens with correct layout: 4 windows"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count, 4)
end

T["merge 3-way"]["source type is merge"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(view_get("_v.diff_spec.source.type"), "merge")
end

T["merge 3-way"]["has three_way flag set"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(view_get("_v.three_way"), true)
end

T["merge 3-way"]["shows conflicted file in panel"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  local file_count = view_get("#_v.diff_spec.file_pairs")
  eq(file_count >= 1, true)
end

T["merge 3-way"]["q closes the view"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(child.lua_get("vim.fn.tabpagenr('$')"), 2)

  focus_win("mid_winnr")
  child.type_keys("q")
  wait_for_tab_count(1)

  eq(child.lua_get("vim.fn.tabpagenr('$')"), 1)
end

T["merge 3-way"]["empty merge (no conflicts) shows no changes"] = function()
  -- Create a repo without merge conflicts
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.lua", "content\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  open_merge_three_way(repo)

  -- Should show empty diff (no unmerged files)
  local file_count = view_get("#_v.diff_spec.file_pairs")
  eq(file_count, 0)
end

-- =============================================================================
-- Label tests
-- =============================================================================

T["merge 3-way"]["tab title contains OURS|WORKTREE|THEIRS"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  local label = child.lua_get(
    [[vim.api.nvim_tabpage_get_var(vim.api.nvim_get_current_tabpage(), "gitlad_label")]]
  )
  eq(label:match("OURS") ~= nil, true)
  eq(label:match("WORKTREE") ~= nil, true)
  eq(label:match("THEIRS") ~= nil, true)
end

-- =============================================================================
-- Editability tests
-- =============================================================================

T["merge 3-way"]["mid buffer is editable (acwrite, modifiable)"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(triple_buf_opt("mid_bufnr", "buftype"), "acwrite")
  eq(triple_buf_opt("mid_bufnr", "modifiable"), true)
end

T["merge 3-way"]["left buffer is read-only"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(triple_buf_opt("left_bufnr", "buftype"), "nofile")
  eq(triple_buf_opt("left_bufnr", "modifiable"), false)
end

T["merge 3-way"]["right buffer is read-only"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(triple_buf_opt("right_bufnr", "buftype"), "nofile")
  eq(triple_buf_opt("right_bufnr", "modifiable"), false)
end

T["merge 3-way"]["editable mode is mid_only"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  local mode = view_get("_v.buffer_triple._editable")
  eq(mode, "mid_only")
end

-- =============================================================================
-- Content tests
-- =============================================================================

T["merge 3-way"]["mid buffer contains conflict markers from worktree"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(buf_has_pattern("mid_bufnr", "^<<<<<<<"), true)
end

T["merge 3-way"]["left buffer shows clean OURS content (no conflict markers)"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(buf_has_pattern("left_bufnr", "^<<<<<<<"), false)
  eq(buf_has_pattern("left_bufnr", "^>>>>>>>"), false)
  eq(buf_has_pattern("left_bufnr", "^======="), false)
end

T["merge 3-way"]["left buffer contains OURS version (main_line2)"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(buf_has_pattern("left_bufnr", "main_line2"), true)
end

T["merge 3-way"]["right buffer contains THEIRS version (feature_line2)"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  eq(buf_has_pattern("right_bufnr", "feature_line2"), true)
end

-- =============================================================================
-- Save tests
-- =============================================================================

T["merge 3-way"]["edit mid buffer and :w saves to disk"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  -- Replace mid buffer content with resolved version
  child.lua([[
    local view = require("gitlad.ui.views.diff").get_active()
    local lines = vim.api.nvim_buf_get_lines(view.buffer_triple.mid_bufnr, 0, -1, false)
    local new_lines = {}
    local in_conflict = false
    for _, line in ipairs(lines) do
      if line:match("^<<<<<<<") then
        in_conflict = true
      elseif line:match("^=======") and in_conflict then
        -- skip
      elseif line:match("^>>>>>>>") and in_conflict then
        in_conflict = false
        table.insert(new_lines, "resolved_line2")
      elseif not in_conflict then
        table.insert(new_lines, line)
      end
    end
    vim.api.nvim_buf_set_lines(view.buffer_triple.mid_bufnr, 0, -1, false, new_lines)
  ]])

  -- Focus mid window and save
  focus_win("mid_winnr")
  child.lua([[vim.cmd("write")]])

  -- Wait for async save to complete
  helpers.wait_short(child, 300)

  -- Read the worktree file to verify it was saved
  local saved = child.lua_get(string.format(
    [[(function()
      local lines = vim.fn.readfile(%q .. "/file.lua")
      for _, line in ipairs(lines) do
        if line:match("resolved_line2") then return true end
      end
      return false
    end)()]],
    repo
  ))
  eq(saved, true)
end

-- =============================================================================
-- Stage tests
-- =============================================================================

T["merge 3-way"]["s stages the current file"] = function()
  local repo = create_repo_with_merge_conflict()
  open_merge_three_way(repo)

  -- First resolve the conflict by writing the file directly
  child.lua(
    string.format(
      [[vim.fn.writefile({"line1", "resolved_line2", "line3"}, %q .. "/file.lua")]],
      repo
    )
  )

  -- Focus a diff buffer and press s
  focus_win("mid_winnr")
  child.type_keys("s")

  -- Wait for git add to complete
  helpers.wait_short(child, 500)

  -- After staging, no unmerged files should remain
  local unmerged = child.lua_get(string.format(
    [[(function()
      local result = vim.fn.system('cd ' .. %q .. ' && git status --porcelain=v2')
      local count = 0
      for line in result:gmatch("[^\n]+") do
        if line:match("^u ") then count = count + 1 end
      end
      return count
    end)()]],
    repo
  ))
  eq(unmerged, 0)
end

-- =============================================================================
-- Multiple files tests
-- =============================================================================

T["merge 3-way"]["multiple conflicted files navigate with gj/gk"] = function()
  local repo = create_repo_with_multiple_conflicts()
  open_merge_three_way(repo)

  -- Should have 2 files
  local file_count = view_get("#_v.diff_spec.file_pairs")
  eq(file_count, 2)

  -- First file should be selected
  eq(view_get("_v.selected_file"), 1)

  -- Navigate to next file
  focus_win("mid_winnr")
  child.type_keys("gj")
  helpers.wait_short(child, 100)

  eq(view_get("_v.selected_file"), 2)

  -- Navigate back
  child.type_keys("gk")
  helpers.wait_short(child, 100)

  eq(view_get("_v.selected_file"), 1)
end

return T
