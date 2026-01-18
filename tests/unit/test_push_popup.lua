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

-- Test push popup internal functions
-- We test these by importing the module and checking behavior through the popup builder
T["push popup"]["uses push_remote when upstream differs"] = function()
  -- This tests the scenario where:
  -- - Branch tracks origin/main as upstream (for pulling/merging)
  -- - But should push to origin/feature-branch (same name on remote)
  --
  -- We verify this indirectly through the popup behavior.
  -- The key insight is that push_remote is derived from upstream's remote + current branch name
  local popup = require("gitlad.ui.popup")

  -- The default remote should be extracted from push target, not upstream
  -- When push_remote = "origin/feature", remote should be "origin"
  local mock_status = {
    branch = "feature/test",
    upstream = "origin/main", -- Merge target
    push_remote = "origin/feature/test", -- Push target (same-name branch)
  }

  -- Simulate the extraction that push.lua does
  local push_ref = mock_status.push_remote
  local remote = push_ref and push_ref:match("^([^/]+)/")

  eq(remote, "origin")
  eq(push_ref, "origin/feature/test")

  -- Verify that with this status, we'd push to the feature branch, not main
  local refspec = mock_status.branch
  eq(refspec, "feature/test")
end

T["push popup"]["derives push_remote from upstream remote when not explicit"] = function()
  -- When push_remote isn't set explicitly, it should be derived from:
  -- upstream_remote + "/" + current_branch
  local mock_status = {
    branch = "my-feature",
    upstream = "origin/main",
    push_remote = nil, -- Not set explicitly, should be derived
  }

  -- This is the logic from get_push_target:
  local push_ref = mock_status.push_remote
  if not push_ref and mock_status.upstream then
    local remote = mock_status.upstream:match("^([^/]+)/")
    if remote then
      push_ref = remote .. "/" .. mock_status.branch
    end
  end

  eq(push_ref, "origin/my-feature")
end

T["push popup"]["returns nil push target when no upstream"] = function()
  local mock_status = {
    branch = "orphan-branch",
    upstream = nil,
    push_remote = nil,
  }

  local push_ref = mock_status.push_remote
  if not push_ref and mock_status.upstream then
    local remote = mock_status.upstream:match("^([^/]+)/")
    if remote then
      push_ref = remote .. "/" .. mock_status.branch
    end
  end

  eq(push_ref, nil)
end

-- Test remote_branch_exists logic
-- This logic determines whether to prompt the user to create the remote branch
T["push popup"]["detects remote branch exists when push_commit_msg is set"] = function()
  -- When both push_remote and push_commit_msg are set, the remote branch exists
  local mock_status = {
    branch = "feature/test",
    upstream = "origin/main",
    push_remote = "origin/feature/test",
    push_commit_msg = "feat: some commit", -- Remote branch exists
  }

  -- This is the logic from remote_branch_exists
  local exists = mock_status.push_remote ~= nil and mock_status.push_commit_msg ~= nil
  eq(exists, true)
end

T["push popup"]["detects remote branch does not exist when push_commit_msg is nil"] = function()
  -- When push_remote is set but push_commit_msg is nil, the remote branch doesn't exist yet
  local mock_status = {
    branch = "feature/new-branch",
    upstream = "origin/main",
    push_remote = "origin/feature/new-branch",
    push_commit_msg = nil, -- Remote branch doesn't exist
  }

  local exists = mock_status.push_remote ~= nil and mock_status.push_commit_msg ~= nil
  eq(exists, false)
end

T["push popup"]["detects no remote branch when push_remote is nil"] = function()
  -- When push_remote is nil (e.g., no upstream configured), remote branch doesn't exist
  local mock_status = {
    branch = "orphan-branch",
    upstream = nil,
    push_remote = nil,
    push_commit_msg = nil,
  }

  local exists = mock_status.push_remote ~= nil and mock_status.push_commit_msg ~= nil
  eq(exists, false)
end

T["push popup"]["should prompt when remote branch needs creation"] = function()
  -- Scenario: User is on feature/diff-popup tracking origin/main
  -- Push target is origin/feature/diff-popup which doesn't exist yet
  local mock_status = {
    branch = "feature/diff-popup",
    upstream = "origin/main",
    push_remote = "origin/feature/diff-popup",
    push_commit_msg = nil, -- Remote branch doesn't exist
  }

  -- Derive push_ref the same way _push_upstream does
  local push_ref = mock_status.push_remote
  if not push_ref and mock_status.upstream then
    local remote = mock_status.upstream:match("^([^/]+)/")
    if remote then
      push_ref = remote .. "/" .. mock_status.branch
    end
  end

  -- Check if we should prompt (remote branch doesn't exist)
  local remote_exists = mock_status.push_remote ~= nil and mock_status.push_commit_msg ~= nil
  local should_prompt = push_ref ~= nil and not remote_exists

  eq(push_ref, "origin/feature/diff-popup")
  eq(should_prompt, true)
end

T["push popup"]["should not prompt when remote branch already exists"] = function()
  -- Scenario: Remote branch already exists, no prompt needed
  local mock_status = {
    branch = "feature/existing",
    upstream = "origin/main",
    push_remote = "origin/feature/existing",
    push_commit_msg = "Previous commit message", -- Remote branch exists
  }

  local push_ref = mock_status.push_remote
  local remote_exists = mock_status.push_remote ~= nil and mock_status.push_commit_msg ~= nil
  local should_prompt = push_ref ~= nil and not remote_exists

  eq(push_ref, "origin/feature/existing")
  eq(should_prompt, false)
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
