local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start fresh child process for each test (matches other e2e tests)
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

T["hook output"] = MiniTest.new_set()

T["hook output"]["commit with pre-commit hook succeeds"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua([[require("gitlad").setup()]])

  -- Create a pre-commit hook that outputs text to stdout
  helpers.create_hook(
    child,
    repo,
    "pre-commit",
    'echo "Running pre-commit checks..."\necho "Lint: OK"\n'
  )

  -- Create and stage a file
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  -- Open gitlad
  helpers.open_gitlad(child, repo)

  -- Open commit popup and start commit
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")

  -- Wait for commit editor to load
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG", 3000)
  helpers.wait_for_buffer_content(child, "# Press C-c C-c to commit", 2000)

  -- Type a commit message at start of buffer
  child.type_keys("ggItest commit with hook<Esc>")

  -- Submit the commit with ZZ
  child.type_keys("ZZ")

  -- Wait for buffer to return to status
  helpers.wait_for_buffer(child, "gitlad://status", 10000)

  -- Poll for commit to appear in log (may take a moment)
  local log
  for _ = 1, 50 do
    log = helpers.git(child, repo, "log --oneline 2>&1")
    if log:match("test commit with hook") then
      break
    end
    vim.loop.sleep(100)
  end

  -- Verify the commit was actually created
  eq(log:match("test commit with hook") ~= nil, true)

  -- Clean up
  helpers.cleanup_repo(child, repo)
end

T["hook output"]["commit without hooks does not show output viewer"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua([[require("gitlad").setup()]])

  -- No hooks configured

  -- Create and stage a file
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  -- Open gitlad
  helpers.open_gitlad(child, repo)

  -- Open commit popup and start commit
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")

  -- Wait for commit editor to load
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG", 3000)
  helpers.wait_for_buffer_content(child, "# Press C-c C-c to commit", 2000)

  -- Type a commit message
  child.type_keys("ggItest commit no hooks<Esc>")

  -- Submit the commit with ZZ
  child.type_keys("ZZ")

  -- Wait for buffer to return to status
  helpers.wait_for_buffer(child, "gitlad://status", 10000)

  -- After commit, we should be back in the status buffer with only 1 window
  -- (no output viewer window since no hooks produced output)
  local win_count = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count, 1)

  -- Verify the commit was created
  local log = helpers.git(child, repo, "log --oneline")
  eq(log:match("test commit no hooks") ~= nil, true)

  -- Clean up
  helpers.cleanup_repo(child, repo)
end

T["hook output"]["extend (amend no-edit) with hook runs successfully"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  child.lua([[require("gitlad").setup()]])

  -- Create initial commit
  helpers.create_file(child, repo, "initial.txt", "initial")
  helpers.git(child, repo, "add initial.txt")
  helpers.git(child, repo, "commit -m 'initial commit'")

  -- Create a pre-commit hook that outputs text
  helpers.create_hook(child, repo, "pre-commit", 'echo "Hook running for amend"\n')

  -- Stage a change
  helpers.create_file(child, repo, "initial.txt", "amended content")
  helpers.git(child, repo, "add initial.txt")

  -- Open gitlad
  helpers.open_gitlad(child, repo)

  -- Open commit popup and press 'e' for extend
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("e")

  -- Wait for the amend to complete
  local found = helpers.wait_for_message(child, "Commit extended", 10000)
  eq(found, true)

  -- Clean up
  helpers.cleanup_repo(child, repo)
end

T["hook output"]["config never suppresses output viewer"] = function()
  local child = _G.child
  local repo = helpers.create_test_repo(child)

  -- Set config to never show hook output
  child.lua([[require("gitlad").setup({ output = { hook_output = "never" } })]])

  -- Create a pre-commit hook that outputs text
  helpers.create_hook(child, repo, "pre-commit", 'echo "This should not show"\n')

  -- Create and stage a file
  helpers.create_file(child, repo, "test.txt", "hello")
  helpers.git(child, repo, "add test.txt")

  -- Open gitlad
  helpers.open_gitlad(child, repo)

  -- Open commit popup and start commit
  child.type_keys("c")
  helpers.wait_for_popup(child)
  child.type_keys("c")

  -- Wait for commit editor
  helpers.wait_for_buffer(child, "COMMIT_EDITMSG", 3000)
  helpers.wait_for_buffer_content(child, "# Press C-c C-c to commit", 2000)

  -- Type message and submit
  child.type_keys("ggItest commit never mode<Esc>")
  child.type_keys("ZZ")

  -- Wait for buffer to return to status
  helpers.wait_for_buffer(child, "gitlad://status", 10000)

  -- After commit, only 1 window (status buffer, no output viewer)
  local win_count = child.lua_get([[vim.fn.winnr('$')]])
  eq(win_count, 1)

  -- Poll for commit to appear in log
  local log
  for _ = 1, 50 do
    log = helpers.git(child, repo, "log --oneline 2>&1")
    if log:match("test commit never mode") then
      break
    end
    vim.loop.sleep(100)
  end

  -- Verify the commit was created
  eq(log:match("test commit never mode") ~= nil, true)

  -- Clean up
  helpers.cleanup_repo(child, repo)
end

return T
