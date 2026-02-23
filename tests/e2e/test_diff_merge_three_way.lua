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

-- =============================================================================
-- Tests
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

  child.lua([[
    local view = require("gitlad.ui.views.diff").get_active()
    vim.api.nvim_set_current_win(view.buffer_triple.mid_winnr)
  ]])
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

return T
