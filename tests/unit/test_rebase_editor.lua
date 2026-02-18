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

-- Test expand_action_abbreviations
T["expand_abbreviations"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Create a scratch buffer for each test
      _G._test_buf = vim.api.nvim_create_buf(false, true)
    end,
    post_case = function()
      if _G._test_buf and vim.api.nvim_buf_is_valid(_G._test_buf) then
        vim.api.nvim_buf_delete(_G._test_buf, { force = true })
      end
      _G._test_buf = nil
    end,
  },
})

T["expand_abbreviations"]["expands single-char actions to full words"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "p abc1234 First commit",
    "f def5678 Second commit",
    "s ghi9012 Third commit",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 First commit")
  eq(lines[2], "fixup def5678 Second commit")
  eq(lines[3], "squash ghi9012 Third commit")
end

T["expand_abbreviations"]["expands all action abbreviations"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "p abc1234 commit1",
    "r abc1234 commit2",
    "e abc1234 commit3",
    "s abc1234 commit4",
    "f abc1234 commit5",
    "d abc1234 commit6",
    "x echo hello",
    "b",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 commit1")
  eq(lines[2], "reword abc1234 commit2")
  eq(lines[3], "edit abc1234 commit3")
  eq(lines[4], "squash abc1234 commit4")
  eq(lines[5], "fixup abc1234 commit5")
  eq(lines[6], "drop abc1234 commit6")
  eq(lines[7], "exec echo hello")
  -- "b" alone without trailing space/content is NOT matched by the pattern
  eq(lines[8], "b")
end

T["expand_abbreviations"]["leaves full action words unchanged"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "pick abc1234 First commit",
    "reword def5678 Second commit",
    "fixup ghi9012 Third commit",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 First commit")
  eq(lines[2], "reword def5678 Second commit")
  eq(lines[3], "fixup ghi9012 Third commit")
end

T["expand_abbreviations"]["skips comment lines"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "p abc1234 First commit",
    "# This is a comment",
    "# p abc1234 Should not expand",
    "f def5678 Second commit",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 First commit")
  eq(lines[2], "# This is a comment")
  eq(lines[3], "# p abc1234 Should not expand")
  eq(lines[4], "fixup def5678 Second commit")
end

T["expand_abbreviations"]["skips empty lines"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "p abc1234 First commit",
    "",
    "f def5678 Second commit",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 First commit")
  eq(lines[2], "")
  eq(lines[3], "fixup def5678 Second commit")
end

T["expand_abbreviations"]["handles custom comment char"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "p abc1234 First commit",
    "; This is a comment with semicolon",
    "f def5678 Second commit",
  })

  rebase_editor._expand_action_abbreviations(buf, ";")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 First commit")
  eq(lines[2], "; This is a comment with semicolon")
  eq(lines[3], "fixup def5678 Second commit")
end

T["expand_abbreviations"]["does not expand unrecognized prefixes"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "z abc1234 Not a valid action",
    "q abc1234 Not a valid action",
    "xyz abc1234 Not a valid prefix",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "z abc1234 Not a valid action")
  eq(lines[2], "q abc1234 Not a valid action")
  eq(lines[3], "xyz abc1234 Not a valid prefix")
end

T["expand_abbreviations"]["handles mixed abbreviated and full actions"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "pick abc1234 Already full",
    "f def5678 Abbreviated",
    "reword ghi9012 Already full",
    "s jkl3456 Abbreviated",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 Already full")
  eq(lines[2], "fixup def5678 Abbreviated")
  eq(lines[3], "reword ghi9012 Already full")
  eq(lines[4], "squash jkl3456 Abbreviated")
end

T["expand_abbreviations"]["expands multi-char prefixes"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "pi abc1234 commit1",
    "rew abc1234 commit2",
    "sq abc1234 commit3",
    "fi abc1234 commit4",
    "dr abc1234 commit5",
    "ex echo hello",
    "br abc1234 commit7",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "pick abc1234 commit1")
  eq(lines[2], "reword abc1234 commit2")
  eq(lines[3], "squash abc1234 commit3")
  eq(lines[4], "fixup abc1234 commit4")
  eq(lines[5], "drop abc1234 commit5")
  eq(lines[6], "exec echo hello")
  eq(lines[7], "break abc1234 commit7")
end

T["expand_abbreviations"]["'e' prefers edit over exec"] = function()
  local rebase_editor = require("gitlad.ui.views.rebase_editor")
  local buf = _G._test_buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "e abc1234 ambiguous prefix",
    "ed abc1234 clearly edit",
    "ex echo hello",
  })

  rebase_editor._expand_action_abbreviations(buf, "#")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[1], "edit abc1234 ambiguous prefix")
  eq(lines[2], "edit abc1234 clearly edit")
  eq(lines[3], "exec echo hello")
end

-- Test resolve_action_prefix directly
T["resolve_prefix"] = MiniTest.new_set()

T["resolve_prefix"]["resolves single-char prefixes"] = function()
  local re = require("gitlad.ui.views.rebase_editor")
  eq(re._resolve_action_prefix("p"), "pick")
  eq(re._resolve_action_prefix("r"), "reword")
  eq(re._resolve_action_prefix("e"), "edit")
  eq(re._resolve_action_prefix("s"), "squash")
  eq(re._resolve_action_prefix("f"), "fixup")
  eq(re._resolve_action_prefix("d"), "drop")
  eq(re._resolve_action_prefix("x"), "exec")
  eq(re._resolve_action_prefix("b"), "break")
end

T["resolve_prefix"]["resolves multi-char prefixes"] = function()
  local re = require("gitlad.ui.views.rebase_editor")
  eq(re._resolve_action_prefix("pi"), "pick")
  eq(re._resolve_action_prefix("pic"), "pick")
  eq(re._resolve_action_prefix("rew"), "reword")
  eq(re._resolve_action_prefix("ed"), "edit")
  eq(re._resolve_action_prefix("ex"), "exec")
  eq(re._resolve_action_prefix("sq"), "squash")
  eq(re._resolve_action_prefix("fi"), "fixup")
  eq(re._resolve_action_prefix("dr"), "drop")
  eq(re._resolve_action_prefix("br"), "break")
end

T["resolve_prefix"]["returns full words unchanged"] = function()
  local re = require("gitlad.ui.views.rebase_editor")
  eq(re._resolve_action_prefix("pick"), "pick")
  eq(re._resolve_action_prefix("reword"), "reword")
  eq(re._resolve_action_prefix("edit"), "edit")
  eq(re._resolve_action_prefix("exec"), "exec")
  eq(re._resolve_action_prefix("break"), "break")
end

T["resolve_prefix"]["returns nil for unrecognized prefixes"] = function()
  local re = require("gitlad.ui.views.rebase_editor")
  eq(re._resolve_action_prefix("z"), nil)
  eq(re._resolve_action_prefix("abc"), nil)
  eq(re._resolve_action_prefix("picks"), nil)
end

-- Test git module has rebase_instantly
T["git"] = MiniTest.new_set()

T["git"]["has rebase_instantly function"] = function()
  local git = require("gitlad.git")
  expect.equality(type(git.rebase_instantly), "function")
end

return T
