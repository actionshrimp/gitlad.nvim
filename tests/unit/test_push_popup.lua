local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Push popup builder tests
T["push popup"] = MiniTest.new_set()

T["push popup"]["creates popup with correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  -- Build the same popup structure as push.lua
  local data = popup
    .builder()
    :name("Push")
    :switch("f", "force-with-lease", "Force with lease (safer)")
    :switch("F", "force", "Force (dangerous)")
    :switch("n", "dry-run", "Dry run")
    :switch("t", "tags", "Include tags")
    :switch("u", "set-upstream", "Set upstream")
    :build()

  eq(data.name, "Push")
  eq(#data.switches, 5)
  eq(data.switches[1].key, "f")
  eq(data.switches[1].cli, "force-with-lease")
  eq(data.switches[2].key, "F")
  eq(data.switches[2].cli, "force")
  eq(data.switches[3].key, "n")
  eq(data.switches[3].cli, "dry-run")
  eq(data.switches[4].key, "t")
  eq(data.switches[4].cli, "tags")
  eq(data.switches[5].key, "u")
  eq(data.switches[5].cli, "set-upstream")
end

T["push popup"]["creates popup with correct options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Push")
    :option("r", "remote", "origin", "Remote")
    :option("b", "refspec", "", "Refspec")
    :build()

  eq(#data.options, 2)
  eq(data.options[1].key, "r")
  eq(data.options[1].cli, "remote")
  eq(data.options[1].value, "origin")
  eq(data.options[2].key, "b")
  eq(data.options[2].cli, "refspec")
  eq(data.options[2].value, "")
end

T["push popup"]["get_arguments returns enabled force-with-lease"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("f", "force-with-lease", "Force with lease", { enabled = true })
    :switch("n", "dry-run", "Dry run")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--force-with-lease")
end

T["push popup"]["get_arguments returns multiple enabled switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("f", "force-with-lease", "Force with lease", { enabled = true })
    :switch("n", "dry-run", "Dry run", { enabled = true })
    :switch("t", "tags", "Tags", { enabled = true })
    :build()

  local args = data:get_arguments()
  eq(#args, 3)
  eq(args[1], "--force-with-lease")
  eq(args[2], "--dry-run")
  eq(args[3], "--tags")
end

T["push popup"]["get_arguments includes remote option with value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("r", "remote", "upstream", "Remote"):build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--remote=upstream")
end

T["push popup"]["get_arguments excludes option without value"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup.builder():option("b", "refspec", "", "Refspec"):build()

  local args = data:get_arguments()
  eq(#args, 0)
end

T["push popup"]["creates actions correctly"] = function()
  local popup = require("gitlad.ui.popup")

  local push_upstream_called = false
  local push_elsewhere_called = false

  local data = popup
    .builder()
    :group_heading("Push")
    :action("p", "Push to upstream", function()
      push_upstream_called = true
    end)
    :action("e", "Push elsewhere", function()
      push_elsewhere_called = true
    end)
    :build()

  -- 1 heading + 2 actions
  eq(#data.actions, 3)
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Push")
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "p")
  eq(data.actions[2].description, "Push to upstream")
  eq(data.actions[3].type, "action")
  eq(data.actions[3].key, "e")
  eq(data.actions[3].description, "Push elsewhere")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(push_upstream_called, true)

  data.actions[3].callback(data)
  eq(push_elsewhere_called, true)
end

-- Parse remotes tests
T["parse_remotes"] = MiniTest.new_set()

T["parse_remotes"]["parses single remote with fetch and push"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remotes({
    "origin\thttps://github.com/user/repo.git (fetch)",
    "origin\thttps://github.com/user/repo.git (push)",
  })

  eq(#result, 1)
  eq(result[1].name, "origin")
  eq(result[1].fetch_url, "https://github.com/user/repo.git")
  eq(result[1].push_url, "https://github.com/user/repo.git")
end

T["parse_remotes"]["parses multiple remotes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remotes({
    "origin\thttps://github.com/user/repo.git (fetch)",
    "origin\thttps://github.com/user/repo.git (push)",
    "upstream\thttps://github.com/original/repo.git (fetch)",
    "upstream\thttps://github.com/original/repo.git (push)",
  })

  eq(#result, 2)
  eq(result[1].name, "origin")
  eq(result[1].fetch_url, "https://github.com/user/repo.git")
  eq(result[2].name, "upstream")
  eq(result[2].fetch_url, "https://github.com/original/repo.git")
end

T["parse_remotes"]["parses SSH URLs"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remotes({
    "origin\tgit@github.com:user/repo.git (fetch)",
    "origin\tgit@github.com:user/repo.git (push)",
  })

  eq(#result, 1)
  eq(result[1].name, "origin")
  eq(result[1].fetch_url, "git@github.com:user/repo.git")
  eq(result[1].push_url, "git@github.com:user/repo.git")
end

T["parse_remotes"]["handles different fetch and push URLs"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remotes({
    "origin\thttps://github.com/user/repo.git (fetch)",
    "origin\tgit@github.com:user/repo.git (push)",
  })

  eq(#result, 1)
  eq(result[1].name, "origin")
  eq(result[1].fetch_url, "https://github.com/user/repo.git")
  eq(result[1].push_url, "git@github.com:user/repo.git")
end

T["parse_remotes"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remotes({})

  eq(#result, 0)
end

T["parse_remotes"]["returns remotes in sorted order"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remotes({
    "upstream\thttps://github.com/original/repo.git (fetch)",
    "upstream\thttps://github.com/original/repo.git (push)",
    "origin\thttps://github.com/user/repo.git (fetch)",
    "origin\thttps://github.com/user/repo.git (push)",
    "backup\thttps://gitlab.com/user/repo.git (fetch)",
    "backup\thttps://gitlab.com/user/repo.git (push)",
  })

  eq(#result, 3)
  eq(result[1].name, "backup")
  eq(result[2].name, "origin")
  eq(result[3].name, "upstream")
end

return T
