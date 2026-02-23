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

--- Wait for tab page count to reach a target value
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

--- Create a repo with both staged and unstaged changes
local function create_repo_with_both_changes()
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.lua", "line1\nline2\nline3\nline4\nline5\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  -- Stage a change (modify line 2)
  helpers.create_file(child, repo, "file.lua", "line1\nline2_staged\nline3\nline4\nline5\n")
  helpers.git(child, repo, "add file.lua")

  -- Make an unstaged change (modify line 4)
  helpers.create_file(
    child,
    repo,
    "file.lua",
    "line1\nline2_staged\nline3\nline4_unstaged\nline5\n"
  )

  return repo
end

--- Create a repo with only staged changes
local function create_repo_staged_only()
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.lua", "original\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  helpers.create_file(child, repo, "file.lua", "modified\n")
  helpers.git(child, repo, "add file.lua")

  return repo
end

--- Create a repo with only unstaged changes
local function create_repo_unstaged_only()
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "file.lua", "original\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  helpers.create_file(child, repo, "file.lua", "modified\n")

  return repo
end

--- Create a repo with changes in multiple files
local function create_repo_multiple_files()
  local repo = helpers.create_test_repo(child)

  helpers.create_file(child, repo, "alpha.lua", "alpha_v1\n")
  helpers.create_file(child, repo, "beta.lua", "beta_v1\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, "commit -m 'initial'")

  -- Stage alpha
  helpers.create_file(child, repo, "alpha.lua", "alpha_v2\n")
  helpers.git(child, repo, "add alpha.lua")

  -- Unstaged beta
  helpers.create_file(child, repo, "beta.lua", "beta_v2\n")

  return repo
end

--- Open the 3-way diff viewer via source.produce_three_way
local function open_three_way_diff(repo)
  child.lua(string.format(
    [[
    local source = require("gitlad.ui.views.diff.source")
    source.produce_three_way(%q, function(spec, err)
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

--- Get a value from the active view by evaluating an expression.
--- The expression is evaluated with `_v` bound to the active DiffView.
local function view_get(expr)
  return child.lua_get(
    "(function() local _v = require('gitlad.ui.views.diff').get_active(); return "
      .. expr
      .. " end)()"
  )
end

-- =============================================================================
-- Tests
-- =============================================================================

T["3-way diff"] = MiniTest.new_set()

T["3-way diff"]["opens with correct layout: 4 windows"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  local win_count = child.lua_get("vim.fn.winnr('$')")
  eq(win_count, 4)
end

T["3-way diff"]["has correct tab title"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  local label = child.lua_get(
    [[vim.api.nvim_tabpage_get_var(vim.api.nvim_get_current_tabpage(), "gitlad_label")]]
  )
  eq(label:match("3%-way") ~= nil, true)
end

T["3-way diff"]["shows files from both staged and unstaged"] = function()
  local repo = create_repo_multiple_files()
  open_three_way_diff(repo)

  local file_count = view_get("#_v.diff_spec.file_pairs")
  eq(file_count, 2)
end

T["3-way diff"]["has three_way flag set on active view"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  eq(view_get("_v.three_way"), true)
end

T["3-way diff"]["buffer triple is created (not buffer pair)"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  eq(view_get("_v.buffer_triple ~= nil"), true)
  eq(view_get("_v.buffer_pair == nil"), true)
end

T["3-way diff"]["staged-only file: HEAD and INDEX/WORKTREE differ"] = function()
  local repo = create_repo_staged_only()
  open_three_way_diff(repo)

  local left_lines = view_get("_v.buffer_triple.left_lines")
  local mid_lines = view_get("_v.buffer_triple.mid_lines")
  local right_lines = view_get("_v.buffer_triple.right_lines")

  -- HEAD=original, INDEX=WORKTREE=modified
  local found_original_left = false
  local found_modified_mid = false
  for _, line in ipairs(left_lines) do
    if line:match("original") then
      found_original_left = true
    end
  end
  for _, line in ipairs(mid_lines) do
    if line:match("modified") then
      found_modified_mid = true
    end
  end
  eq(found_original_left, true)
  eq(found_modified_mid, true)
  eq(#right_lines, #mid_lines)
end

T["3-way diff"]["unstaged-only file: HEAD/INDEX and WORKTREE differ"] = function()
  local repo = create_repo_unstaged_only()
  open_three_way_diff(repo)

  local left_lines = view_get("_v.buffer_triple.left_lines")
  local right_lines = view_get("_v.buffer_triple.right_lines")

  local found_original_left = false
  for _, line in ipairs(left_lines) do
    if line:match("original") then
      found_original_left = true
    end
  end
  eq(found_original_left, true)

  local found_modified_right = false
  for _, line in ipairs(right_lines) do
    if line:match("modified") then
      found_modified_right = true
    end
  end
  eq(found_modified_right, true)
end

T["3-way diff"]["q closes the view"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  eq(child.lua_get("vim.fn.tabpagenr('$')"), 2)

  -- Focus a diff buffer and press q
  child.lua([[
    local view = require("gitlad.ui.views.diff").get_active()
    vim.api.nvim_set_current_win(view.buffer_triple.mid_winnr)
  ]])
  child.type_keys("q")
  wait_for_tab_count(1)

  eq(child.lua_get("vim.fn.tabpagenr('$')"), 1)
end

T["3-way diff"]["gj/gk navigate between files"] = function()
  local repo = create_repo_multiple_files()
  open_three_way_diff(repo)

  eq(view_get("_v.selected_file"), 1)

  -- Focus a diff buffer
  child.lua([[
    local view = require("gitlad.ui.views.diff").get_active()
    vim.api.nvim_set_current_win(view.buffer_triple.mid_winnr)
  ]])
  child.type_keys("gj")
  helpers.wait_short(child, 100)

  eq(view_get("_v.selected_file"), 2)

  child.type_keys("gk")
  helpers.wait_short(child, 100)

  eq(view_get("_v.selected_file"), 1)
end

T["3-way diff"]["gr refreshes the view"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  -- Call refresh directly via Lua instead of keypress to avoid blocking
  child.lua([[
    local view = require("gitlad.ui.views.diff").get_active()
    view:refresh()
  ]])
  helpers.wait_short(child, 500)

  -- View should still be open
  eq(view_get("not _v._closed"), true)
end

T["3-way diff"]["source type is three_way for staging view"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  local source_type = view_get("_v.diff_spec.source.type")
  eq(source_type, "three_way")
end

T["3-way diff"]["empty diff shows no changes message"] = function()
  local repo = helpers.create_test_repo(child)
  helpers.create_file(child, repo, "file.lua", "content\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  open_three_way_diff(repo)

  local mid_lines = child.lua_get(
    "(function() local v = require('gitlad.ui.views.diff').get_active(); return vim.api.nvim_buf_get_lines(v.buffer_triple.mid_bufnr, 0, -1, false) end)()"
  )

  local found_no_changes = false
  for _, line in ipairs(mid_lines) do
    if line:match("No changes") then
      found_no_changes = true
    end
  end
  eq(found_no_changes, true)
end

T["3-way diff"]["windows are scrollbound"] = function()
  local repo = create_repo_with_both_changes()
  open_three_way_diff(repo)

  local left_sb = child.lua_get(
    "(function() local v = require('gitlad.ui.views.diff').get_active(); return vim.api.nvim_get_option_value('scrollbind', { win = v.buffer_triple.left_winnr, scope = 'local' }) end)()"
  )
  local mid_sb = child.lua_get(
    "(function() local v = require('gitlad.ui.views.diff').get_active(); return vim.api.nvim_get_option_value('scrollbind', { win = v.buffer_triple.mid_winnr, scope = 'local' }) end)()"
  )
  local right_sb = child.lua_get(
    "(function() local v = require('gitlad.ui.views.diff').get_active(); return vim.api.nvim_get_option_value('scrollbind', { win = v.buffer_triple.right_winnr, scope = 'local' }) end)()"
  )

  eq(left_sb, true)
  eq(mid_sb, true)
  eq(right_sb, true)
end

return T
