---@diagnostic disable: undefined-field
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- Test the rebase editor module
T["rebase_editor"] = MiniTest.new_set()

T["rebase_editor"]["module loads without error"] = function()
  local ok, rebase_editor = pcall(require, "gitlad.ui.views.rebase_editor")
  expect.equality(ok, true)
  expect.equality(type(rebase_editor), "table")
  expect.equality(type(rebase_editor.open), "function")
  expect.equality(type(rebase_editor.submit), "function")
  expect.equality(type(rebase_editor.abort), "function")
  expect.equality(type(rebase_editor.close), "function")
  expect.equality(type(rebase_editor.is_active), "function")
end

T["rebase_editor"]["is_active returns false when no editor open"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  -- Ensure clean state
  rebase_editor.close()
  eq(rebase_editor.is_active(), false)
end

-- Test the client module
T["client"] = MiniTest.new_set()

T["client"]["module loads without error"] = function()
  local ok, client = pcall(require, "gitlad.client")
  expect.equality(ok, true)
  expect.equality(type(client), "table")
  expect.equality(type(client.get_nvim_remote_editor), "function")
  expect.equality(type(client.get_envs_git_editor), "function")
  expect.equality(type(client.client), "function")
  expect.equality(type(client.editor), "function")
end

T["client"]["get_nvim_remote_editor returns a string"] = function()
  local client = require("gitlad.client")
  local editor_cmd = client.get_nvim_remote_editor()
  expect.equality(type(editor_cmd), "string")
  -- Should contain nvim
  expect.equality(editor_cmd:find("nvim") ~= nil, true)
  -- Should contain headless flag
  expect.equality(editor_cmd:find("headless") ~= nil, true)
end

T["client"]["get_envs_git_editor returns env table"] = function()
  local client = require("gitlad.client")
  local env = client.get_envs_git_editor()
  expect.equality(type(env), "table")
  expect.equality(type(env.GIT_SEQUENCE_EDITOR), "string")
  expect.equality(type(env.GIT_EDITOR), "string")
  -- Both should be the same command
  expect.equality(env.GIT_SEQUENCE_EDITOR, env.GIT_EDITOR)
end

-- Test the prompt utility module
T["prompt"] = MiniTest.new_set()

T["prompt"]["module loads without error"] = function()
  local ok, prompt = pcall(require, "gitlad.utils.prompt")
  expect.equality(ok, true)
  expect.equality(type(prompt), "table")
  expect.equality(type(prompt.prompt_for_ref), "function")
end

T["prompt"]["global completion function exists"] = function()
  -- Load the module to register the global function
  require("gitlad.utils.prompt")
  expect.equality(type(_G.gitlad_complete_refs), "function")
end

-- Test that instant fixup functions are added to commit popup
T["commit_popup"] = MiniTest.new_set()

T["commit_popup"]["has instant fixup action"] = function()
  local popup = require("gitlad.ui.popup")

  -- Create a mock repo_state
  local mock_repo_state = {
    repo_root = "/tmp/test",
    status = {
      staged = {},
      unstaged = {},
    },
  }

  -- We can't easily test the popup builder without opening it,
  -- but we can verify the commit module has the expected functions
  local commit = require("gitlad.popups.commit")
  expect.equality(type(commit._do_instant_fixup), "function")
  expect.equality(type(commit._do_instant_squash), "function")
end

-- Test git module has rebase_instantly
T["git"] = MiniTest.new_set()

T["git"]["has rebase_instantly function"] = function()
  local git = require("gitlad.git")
  expect.equality(type(git.rebase_instantly), "function")
end

return T
