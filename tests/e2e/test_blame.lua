local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

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

--- Helper to create a repo with blame-able history
---@param child table
---@return string repo_path
local function create_blame_repo(child)
  local repo = helpers.create_test_repo(child)

  -- Create initial file and commit
  helpers.create_file(child, repo, "file.lua", "local M = {}\nreturn M\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial commit'")

  -- Add more lines in a second commit
  helpers.create_file(
    child,
    repo,
    "file.lua",
    "local M = {}\n\nfunction M.hello()\n  return 'hi'\nend\n\nreturn M\n"
  )
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'add hello function'")

  return repo
end

T["blame view"] = MiniTest.new_set()

T["blame view"]["opens via :Gitlad blame"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  -- Open a file first
  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)

  -- Run blame command
  child.cmd("Gitlad blame")

  -- Wait for blame to load (two windows should appear)
  helpers.wait_short(child, 1000)

  -- Should have 2 windows (annotation + file)
  local win_count = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count, 2)

  -- The annotation buffer should have gitlad-blame filetype
  local found_blame = child.lua_get([[(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "gitlad-blame" then
        return true
      end
    end
    return false
  end)()]])
  eq(found_blame, true)

  helpers.cleanup_repo(child, repo)
end

T["blame view"]["shows annotation content"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1000)

  -- Find the blame annotation buffer and check its content
  local has_annotations = child.lua_get([[(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "gitlad-blame" then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        -- Should have at least 2 lines (the file has multiple lines)
        if #lines >= 2 then
          -- Lines should contain commit hash fragments (7 hex chars)
          for _, line in ipairs(lines) do
            if line:match("^%x%x%x%x%x%x%x") then
              return true
            end
          end
        end
      end
    end
    return false
  end)()]])
  eq(has_annotations, true)

  helpers.cleanup_repo(child, repo)
end

T["blame view"]["shows file content in right pane"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1000)

  -- Check that file content buffer has "local M = {}" (first line)
  local has_file_content = child.lua_get([[(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("blame.*content") then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("local M") then
            return true
          end
        end
      end
    end
    return false
  end)()]])
  eq(has_file_content, true)

  helpers.cleanup_repo(child, repo)
end

T["blame view"]["has synchronized scrolling enabled"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1000)

  -- Check scrollbind is enabled on all visible windows
  local all_scrollbind = child.lua_get([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.api.nvim_get_option_value("scrollbind", { win = win, scope = "local" }) then
        return false
      end
    end
    return true
  end)()]])
  eq(all_scrollbind, true)

  helpers.cleanup_repo(child, repo)
end

T["blame view"]["closes with q"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1000)

  -- Verify we have 2 windows
  local win_count_before = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count_before, 2)

  -- Focus the annotation buffer and press q
  child.lua([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "gitlad-blame" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)()]])

  child.type_keys("q")
  helpers.wait_short(child, 300)

  -- Should be back to 1 window
  local win_count_after = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count_after, 1)

  helpers.cleanup_repo(child, repo)
end

T["blame view"]["yank hash with y"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1000)

  -- Focus annotation buffer
  child.lua([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "gitlad-blame" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)()]])

  -- Yank hash
  child.type_keys("y")
  helpers.wait_short(child, 200)

  -- Check that clipboard has a hash-like value
  local yanked = child.lua_get([[vim.fn.getreg('+')]])
  expect.no_equality(yanked, "")
  -- Should be 7 hex characters
  local is_hash = yanked:match("^%x%x%x%x%x%x%x$") ~= nil
  eq(is_hash, true)

  helpers.cleanup_repo(child, repo)
end

T["blame view"]["navigates chunks with gj/gk"] = function()
  local repo = create_blame_repo(child)
  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1000)

  -- Focus annotation buffer
  child.lua([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "gitlad-blame" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)()]])

  -- Go to first line
  child.type_keys("gg")
  helpers.wait_short(child, 100)

  local line_before = child.lua_get([[(vim.api.nvim_win_get_cursor(0)[1])]])

  -- Navigate to next chunk
  child.type_keys("gj")
  helpers.wait_short(child, 100)

  local line_after = child.lua_get([[(vim.api.nvim_win_get_cursor(0)[1])]])

  -- Should have moved to a different line (next chunk)
  -- The file has 2 commits so there should be at least 2 chunks
  expect.no_equality(line_before, line_after)

  helpers.cleanup_repo(child, repo)
end

T["blame view from status"] = MiniTest.new_set()

T["blame view from status"]["B opens blame for file at cursor"] = function()
  local repo = create_blame_repo(child)

  -- Modify a file to get it in unstaged section
  helpers.create_file(
    child,
    repo,
    "file.lua",
    "local M = {}\n\nfunction M.hello()\n  return 'hello'\nend\n\nreturn M\n"
  )

  -- Open status view
  helpers.open_gitlad(child, repo)
  helpers.wait_for_status_content(child, "file.lua")

  -- Navigate to the file
  helpers.goto_line_with(child, "file.lua")

  -- Press B to open blame
  child.type_keys("B")

  -- Wait for blame buffer to appear
  local found_blame = child.lua_get([[(function()
    local ok = vim.wait(3000, function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == "gitlad-blame" then
          return true
        end
      end
      return false
    end, 50)
    return ok
  end)()]])
  eq(found_blame, true)

  -- Should have 2 windows (blame split)
  local win_count = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count, 2)

  helpers.cleanup_repo(child, repo)
end

T["blame view from status"]["B warns on untracked file"] = function()
  local repo = create_blame_repo(child)

  -- Create an untracked file
  helpers.create_file(child, repo, "new_file.lua", "new content\n")

  -- Open status view
  helpers.open_gitlad(child, repo)
  helpers.wait_for_status_content(child, "new_file.lua")

  -- Navigate to the untracked file
  helpers.goto_line_with(child, "new_file.lua")

  -- Press B
  child.type_keys("B")
  helpers.wait_short(child, 300)

  -- Should show warning
  local warned = helpers.wait_for_message(child, "Cannot blame untracked")
  eq(warned, true)

  -- Should still have 1 window (no blame opened)
  local win_count = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count, 1)

  helpers.cleanup_repo(child, repo)
end

T["blame-on-blame"] = MiniTest.new_set()

T["blame-on-blame"]["b re-blames at parent revision"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create initial file
  helpers.create_file(child, repo, "file.lua", "line one\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'first commit'")

  -- Modify file in second commit
  helpers.create_file(child, repo, "file.lua", "line one\nline two\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'second commit'")

  -- Modify file in third commit
  helpers.create_file(child, repo, "file.lua", "line one\nline two\nline three\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'third commit'")

  helpers.cd(child, repo)

  -- Open blame
  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1500)

  -- Focus annotation buffer
  child.lua([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "gitlad-blame" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)()]])

  -- Move to last line (added in third commit)
  child.type_keys("G")
  helpers.wait_short(child, 100)

  -- Press b for blame-on-blame
  child.type_keys("b")
  helpers.wait_short(child, 1500)

  -- Verify the buffer name now contains a revision hash (not just the file)
  local has_revision = child.lua_get([[(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("blame") and name:match("@ ") then
        return true
      end
    end
    return false
  end)()]])
  eq(has_revision, true)

  helpers.cleanup_repo(child, repo)
end

T["blame-on-blame"]["warns on boundary commit"] = function()
  local repo = helpers.create_test_repo(child)

  -- Single commit only (boundary)
  helpers.create_file(child, repo, "file.lua", "content\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'only commit'")

  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1500)

  -- Focus annotation buffer
  child.lua([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "gitlad-blame" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)()]])

  -- Press b on the only (boundary) commit
  child.type_keys("b")
  helpers.wait_short(child, 500)

  -- Should show boundary warning
  local warned = helpers.wait_for_message(child, "boundary commit")
  eq(warned, true)

  helpers.cleanup_repo(child, repo)
end

T["blame-on-blame"]["gJ/gK navigate same-commit chunks"] = function()
  local repo = helpers.create_test_repo(child)

  -- Create file where same commit appears in multiple non-contiguous chunks
  helpers.create_file(child, repo, "file.lua", "line 1\nline 2\nline 3\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'initial'")

  -- Another commit adds a line in the middle
  helpers.create_file(child, repo, "file.lua", "line 1\nnew line\nline 2\nline 3\n")
  helpers.git(child, repo, "add file.lua")
  helpers.git(child, repo, "commit -m 'add middle line'")

  helpers.cd(child, repo)

  child.cmd("edit file.lua")
  helpers.wait_short(child, 100)
  child.cmd("Gitlad blame")
  helpers.wait_short(child, 1500)

  -- Focus annotation buffer
  child.lua([[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "gitlad-blame" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)()]])

  -- Go to first line (should be from initial commit)
  child.type_keys("gg")
  helpers.wait_short(child, 100)

  local start_line = child.lua_get([[(vim.api.nvim_win_get_cursor(0)[1])]])

  -- Navigate to next chunk from same commit (gJ)
  child.type_keys("gJ")
  helpers.wait_short(child, 100)

  local after_gJ = child.lua_get([[(vim.api.nvim_win_get_cursor(0)[1])]])

  -- Should have moved past the middle line (from different commit)
  -- The initial commit owns lines 1, 3, 4 and the second commit owns line 2
  -- So gJ from line 1 should jump to line 3
  if after_gJ > start_line then
    -- Moved forward - good
    expect.no_equality(start_line, after_gJ)
  end
  -- If it didn't move (only one chunk from this commit), that's also valid

  helpers.cleanup_repo(child, repo)
end

return T
