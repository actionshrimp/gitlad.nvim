local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      local forge = require("gitlad.forge")
      forge._clear_cache()
      forge._set_auth_fn(nil)
    end,
  },
})

local forge = require("gitlad.forge")

-- =============================================================================
-- parse_remote_url
-- =============================================================================

T["parse_remote_url()"] = MiniTest.new_set()

T["parse_remote_url()"]["returns nil for nil input"] = function()
  eq(forge.parse_remote_url(nil), nil)
end

T["parse_remote_url()"]["returns nil for empty string"] = function()
  eq(forge.parse_remote_url(""), nil)
end

T["parse_remote_url()"]["parses HTTPS URL"] = function()
  local info = forge.parse_remote_url("https://github.com/owner/repo")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
  eq(info.host, "github.com")
end

T["parse_remote_url()"]["parses HTTPS URL with .git suffix"] = function()
  local info = forge.parse_remote_url("https://github.com/owner/repo.git")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
end

T["parse_remote_url()"]["parses SSH colon format"] = function()
  local info = forge.parse_remote_url("git@github.com:owner/repo")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
  eq(info.host, "github.com")
end

T["parse_remote_url()"]["parses SSH colon format with .git"] = function()
  local info = forge.parse_remote_url("git@github.com:owner/repo.git")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
end

T["parse_remote_url()"]["parses SSH path format"] = function()
  local info = forge.parse_remote_url("ssh://git@github.com/owner/repo")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
end

T["parse_remote_url()"]["parses SSH path format with .git"] = function()
  local info = forge.parse_remote_url("ssh://git@github.com/owner/repo.git")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
end

T["parse_remote_url()"]["handles trailing whitespace"] = function()
  local info = forge.parse_remote_url("https://github.com/owner/repo  \n")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
end

T["parse_remote_url()"]["parses GitHub Enterprise HTTPS"] = function()
  local info = forge.parse_remote_url("https://github.mycompany.com/org/project")
  eq(info.provider, "github")
  eq(info.owner, "org")
  eq(info.repo, "project")
  eq(info.host, "github.mycompany.com")
end

T["parse_remote_url()"]["parses GitHub Enterprise SSH"] = function()
  local info = forge.parse_remote_url("git@github.mycompany.com:org/project.git")
  eq(info.provider, "github")
  eq(info.owner, "org")
  eq(info.repo, "project")
  eq(info.host, "github.mycompany.com")
end

T["parse_remote_url()"]["returns nil for non-github hosts"] = function()
  local info = forge.parse_remote_url("https://gitlab.com/owner/repo")
  eq(info, nil)
end

T["parse_remote_url()"]["returns nil for malformed URLs"] = function()
  eq(forge.parse_remote_url("not-a-url"), nil)
  eq(forge.parse_remote_url("https://github.com/"), nil)
  eq(forge.parse_remote_url("https://github.com/owner"), nil)
end

T["parse_remote_url()"]["parses HTTP URL (upgradable)"] = function()
  local info = forge.parse_remote_url("http://github.com/owner/repo")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
end

-- =============================================================================
-- get_auth_token (with mock)
-- =============================================================================

T["get_auth_token()"] = MiniTest.new_set({
  hooks = {
    post_case = function()
      forge._clear_cache()
      forge._set_auth_fn(nil)
    end,
  },
})

T["get_auth_token()"]["returns token from mock auth fn"] = function()
  forge._set_auth_fn(function(cb)
    cb("test-token-123", nil)
  end)

  local got_token = nil
  forge.get_auth_token(function(token, err)
    got_token = token
  end)

  eq(got_token, "test-token-123")
end

T["get_auth_token()"]["caches token on success"] = function()
  local call_count = 0
  forge._set_auth_fn(function(cb)
    call_count = call_count + 1
    cb("test-token", nil)
  end)

  forge.get_auth_token(function() end)
  forge.get_auth_token(function() end)

  -- Auth fn should only be called once (second call uses cache)
  eq(call_count, 1)
end

T["get_auth_token()"]["returns error from mock auth fn"] = function()
  forge._set_auth_fn(function(cb)
    cb(nil, "no gh cli")
  end)

  local got_err = nil
  forge.get_auth_token(function(token, err)
    got_err = err
  end)

  eq(got_err, "no gh cli")
end

-- =============================================================================
-- _make_remote_info
-- =============================================================================

T["_make_remote_info()"] = MiniTest.new_set()

T["_make_remote_info()"]["creates info for github.com"] = function()
  local info = forge._make_remote_info("github.com", "owner", "repo")
  eq(info.provider, "github")
  eq(info.owner, "owner")
  eq(info.repo, "repo")
  eq(info.host, "github.com")
end

T["_make_remote_info()"]["creates info for GHE host"] = function()
  local info = forge._make_remote_info("github.enterprise.com", "org", "project")
  eq(info.provider, "github")
  eq(info.host, "github.enterprise.com")
end

T["_make_remote_info()"]["returns nil for non-github host"] = function()
  eq(forge._make_remote_info("gitlab.com", "owner", "repo"), nil)
end

-- =============================================================================
-- get / _clear_cache
-- =============================================================================

T["get()"] = MiniTest.new_set()

T["get()"]["returns nil for unknown repo"] = function()
  eq(forge.get("/unknown/repo"), nil)
end

T["_clear_cache()"] = MiniTest.new_set()

T["_clear_cache()"]["clears provider cache"] = function()
  -- Not much to test without full integration, but ensures no errors
  forge._clear_cache()
  eq(forge.get("/some/repo"), nil)
end

return T
