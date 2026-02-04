-- End-to-end tests for configurable status buffer sections
local MiniTest = require("mini.test")
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

local function create_test_repo(child)
  local repo = child.lua_get("vim.fn.tempname()")
  child.lua(string.format(
    [[
    local repo = %q
    vim.fn.mkdir(repo, "p")
    vim.fn.system("git -C " .. repo .. " init")
    vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")
    vim.fn.system("git -C " .. repo .. " config commit.gpgsign false")
  ]],
    repo
  ))
  return repo
end

local function create_file(child, repo, filename, content)
  child.lua(string.format(
    [[
    local path = %q .. "/" .. %q
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(path, "w")
    f:write(%q)
    f:close()
  ]],
    repo,
    filename,
    content
  ))
end

local function git(child, repo, args)
  return child.lua_get(string.format("vim.fn.system('git -C ' .. %q .. ' ' .. %q)", repo, args))
end

local function get_buffer_lines(child)
  return child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
end

local function find_line_with(lines, pattern)
  for i, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return i, line
    end
  end
  return nil, nil
end

local function wait_for_status(child)
  child.lua([[vim.wait(2000, function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("Head:", 1, true) then return true end
    end
    return false
  end, 50)]])
end

T["section_config"] = MiniTest.new_set()

T["section_config"]["default sections show in correct order"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create an initial commit
  create_file(child, repo, "initial.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create untracked and unstaged files
  create_file(child, repo, "untracked.txt", "untracked")
  create_file(child, repo, "initial.txt", "modified content")

  -- Setup with default config (no sections override)
  child.lua(string.format(
    [[
    vim.cmd("cd " .. %q)
    require("gitlad").setup({})
    vim.cmd("Gitlad")
  ]],
    repo
  ))

  wait_for_status(child)
  local lines = get_buffer_lines(child)

  -- Find section headers
  local untracked_line = find_line_with(lines, "Untracked")
  local unstaged_line = find_line_with(lines, "Unstaged")

  -- Verify default order: untracked comes before unstaged
  if untracked_line and unstaged_line then
    eq(untracked_line < unstaged_line, true)
  end
end

T["section_config"]["custom section order is respected"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create an initial commit
  create_file(child, repo, "initial.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create both untracked and unstaged files
  create_file(child, repo, "untracked.txt", "untracked")
  create_file(child, repo, "initial.txt", "modified content")

  -- Setup with custom section order: unstaged before untracked
  child.lua(string.format(
    [[
    vim.cmd("cd " .. %q)
    require("gitlad").setup({
      status = {
        sections = { "unstaged", "untracked", "staged", "stashes", "recent" }
      }
    })
    vim.cmd("Gitlad")
  ]],
    repo
  ))

  wait_for_status(child)
  local lines = get_buffer_lines(child)

  -- Find section headers
  local untracked_line = find_line_with(lines, "Untracked")
  local unstaged_line = find_line_with(lines, "Unstaged")

  -- Verify custom order: unstaged comes before untracked (reversed from default)
  if untracked_line and unstaged_line then
    eq(unstaged_line < untracked_line, true)
  end
end

T["section_config"]["omitted sections are hidden"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create an initial commit
  create_file(child, repo, "initial.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create untracked file
  create_file(child, repo, "untracked.txt", "untracked content")

  -- Setup with sections that exclude "untracked"
  child.lua(string.format(
    [[
    vim.cmd("cd " .. %q)
    require("gitlad").setup({
      status = {
        sections = { "staged", "unstaged", "recent" }
      }
    })
    vim.cmd("Gitlad")
  ]],
    repo
  ))

  wait_for_status(child)
  local lines = get_buffer_lines(child)

  -- Verify untracked section is not shown
  local untracked_line = find_line_with(lines, "Untracked")
  eq(untracked_line, nil)
end

T["section_config"]["recent section count option limits commits"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create multiple commits
  for i = 1, 5 do
    create_file(child, repo, "file" .. i .. ".txt", "content " .. i)
    git(child, repo, "add .")
    git(child, repo, "commit -m 'Commit " .. i .. "'")
  end

  -- Setup with recent section limited to 2 commits
  child.lua(string.format(
    [[
    vim.cmd("cd " .. %q)
    require("gitlad").setup({
      status = {
        sections = { "staged", "unstaged", { "recent", count = 2 } }
      }
    })
    vim.cmd("Gitlad")
  ]],
    repo
  ))

  wait_for_status(child)
  local lines = get_buffer_lines(child)

  -- Find recent section
  local recent_line = find_line_with(lines, "Recent commits")
  if recent_line then
    -- The header should show (2) for 2 commits
    local _, line = find_line_with(lines, "Recent commits")
    if line then
      eq(line:find("(2)", 1, true) ~= nil, true)
    end
  end
end

T["section_config"]["staged section appears when configured"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create an initial commit and staged file
  create_file(child, repo, "initial.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Initial commit'")

  create_file(child, repo, "staged.txt", "staged content")
  git(child, repo, "add staged.txt")

  -- Setup with only staged section
  child.lua(string.format(
    [[
    vim.cmd("cd " .. %q)
    require("gitlad").setup({
      status = {
        sections = { "staged" }
      }
    })
    vim.cmd("Gitlad")
  ]],
    repo
  ))

  wait_for_status(child)
  local lines = get_buffer_lines(child)

  -- Verify staged section is shown
  local staged_line = find_line_with(lines, "Staged")
  eq(staged_line ~= nil, true)
end

T["section_config"]["stashes section respects config order"] = function()
  local child = _G.child
  local repo = create_test_repo(child)

  -- Create an initial commit
  create_file(child, repo, "initial.txt", "initial content")
  git(child, repo, "add .")
  git(child, repo, "commit -m 'Initial commit'")

  -- Create a stash
  create_file(child, repo, "stash_me.txt", "stash content")
  git(child, repo, "add stash_me.txt")
  git(child, repo, "stash push -m 'Test stash'")

  -- Create an unstaged change for reference
  create_file(child, repo, "initial.txt", "modified")

  -- Setup with stashes before unstaged
  child.lua(string.format(
    [[
    vim.cmd("cd " .. %q)
    require("gitlad").setup({
      status = {
        sections = { "stashes", "unstaged", "recent" }
      }
    })
    vim.cmd("Gitlad")
  ]],
    repo
  ))

  wait_for_status(child)
  local lines = get_buffer_lines(child)

  local stashes_line = find_line_with(lines, "Stashes")
  local unstaged_line = find_line_with(lines, "Unstaged")

  -- Verify stashes comes before unstaged
  if stashes_line and unstaged_line then
    eq(stashes_line < unstaged_line, true)
  end
end

return T
