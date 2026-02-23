---@mod gitlad.forge Forge integration entry point
---@brief [[
--- Provider detection, authentication, and caching for forge integrations.
--- Detects GitHub repos from git remote URLs and manages auth tokens.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")

-- Cache providers by repo_root
local _providers = {}

-- Cache auth token per session
local _auth_token = nil

-- Cache viewer login per session
local _viewer_login = nil

-- Allow overriding auth function for testing
local _auth_fn = nil

--- Set a custom auth function for testing
---@param fn fun(callback: fun(token: string|nil, err: string|nil))|nil
function M._set_auth_fn(fn)
  _auth_fn = fn
end

--- Clear all cached state (for testing)
function M._clear_cache()
  _providers = {}
  _auth_token = nil
  _viewer_login = nil
end

--- Get the authenticated viewer's login (cached per session)
---@param provider ForgeProvider
---@param callback fun(login: string|nil, err: string|nil)
function M.get_viewer_login(provider, callback)
  if _viewer_login then
    callback(_viewer_login, nil)
    return
  end

  provider:get_viewer(function(login, err)
    if login then
      _viewer_login = login
    end
    callback(login, err)
  end)
end

--- Parse a git remote URL into forge provider info
--- Supports HTTPS, SSH colon, and SSH path formats.
---@param url string Git remote URL
---@return ForgeRemoteInfo|nil info Parsed remote info, or nil if not recognized
function M.parse_remote_url(url)
  if not url or url == "" then
    return nil
  end

  -- Strip trailing .git
  url = url:gsub("%.git$", "")
  -- Strip trailing whitespace/newlines
  url = url:gsub("%s+$", "")

  local host, owner, repo

  -- HTTPS: https://github.com/owner/repo
  host, owner, repo = url:match("^https?://([^/]+)/([^/]+)/([^/]+)$")
  if host and owner and repo then
    return M._make_remote_info(host, owner, repo)
  end

  -- SSH colon: git@github.com:owner/repo
  host, owner, repo = url:match("^[^@]+@([^:]+):([^/]+)/([^/]+)$")
  if host and owner and repo then
    return M._make_remote_info(host, owner, repo)
  end

  -- SSH path: ssh://git@github.com/owner/repo
  host, owner, repo = url:match("^ssh://[^@]+@([^/]+)/([^/]+)/([^/]+)$")
  if host and owner and repo then
    return M._make_remote_info(host, owner, repo)
  end

  -- SSH path without user: ssh://github.com/owner/repo
  host, owner, repo = url:match("^ssh://([^/]+)/([^/]+)/([^/]+)$")
  if host and owner and repo then
    return M._make_remote_info(host, owner, repo)
  end

  return nil
end

--- Create a ForgeRemoteInfo from parsed URL components
---@param host string Hostname
---@param owner string Repository owner
---@param repo string Repository name
---@return ForgeRemoteInfo|nil
function M._make_remote_info(host, owner, repo)
  -- Determine provider type from host
  if host:match("github") then
    return {
      provider = "github",
      owner = owner,
      repo = repo,
      host = host,
    }
  end

  -- Unknown provider
  return nil
end

--- Get auth token from gh CLI (cached per session)
---@param callback fun(token: string|nil, err: string|nil)
function M.get_auth_token(callback)
  -- Return cached token
  if _auth_token then
    callback(_auth_token, nil)
    return
  end

  -- Use custom auth function if set (for testing)
  if _auth_fn then
    _auth_fn(function(token, err)
      if token then
        _auth_token = token
      end
      callback(token, err)
    end)
    return
  end

  -- Run gh auth token
  vim.fn.jobstart({ "gh", "auth", "token" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        -- Remove trailing empty strings
        while #data > 0 and data[#data] == "" do
          table.remove(data)
        end
        if #data > 0 then
          local token = data[1]:gsub("%s+$", "")
          if token ~= "" then
            _auth_token = token
            vim.schedule(function()
              callback(token, nil)
            end)
            return
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          callback(
            nil,
            "gh auth token failed (exit " .. code .. "). Is gh CLI installed and authenticated?"
          )
        end)
      end
    end,
  })
end

--- Detect the forge provider for a repository
--- Chains: git remote get-url origin → parse URL → get auth → create provider
---@param repo_root string Repository root path
---@param callback fun(provider: ForgeProvider|nil, err: string|nil)
function M.detect(repo_root, callback)
  -- Return cached provider
  if _providers[repo_root] then
    callback(_providers[repo_root], nil)
    return
  end

  -- Get remote URL
  cli.run_async(
    { "remote", "get-url", "origin" },
    { cwd = repo_root, internal = true },
    function(result)
      if result.code ~= 0 then
        callback(nil, "No 'origin' remote found")
        return
      end

      local url = (result.stdout[1] or ""):gsub("%s+$", "")
      local remote_info = M.parse_remote_url(url)
      if not remote_info then
        callback(nil, "Could not parse remote URL: " .. url)
        return
      end

      if remote_info.provider ~= "github" then
        callback(nil, "Unsupported forge provider: " .. remote_info.provider)
        return
      end

      -- Get auth token
      M.get_auth_token(function(token, auth_err)
        if not token then
          callback(nil, auth_err or "Failed to get auth token")
          return
        end

        -- Create GitHub provider
        local github = require("gitlad.forge.github")
        local api_url = "https://api.github.com"
        if remote_info.host ~= "github.com" then
          api_url = "https://" .. remote_info.host .. "/api/v3"
        end

        local provider = github.new(remote_info.owner, remote_info.repo, api_url, token)
        _providers[repo_root] = provider

        callback(provider, nil)
      end)
    end
  )
end

--- Get the cached provider for a repository (or nil if not yet detected)
---@param repo_root string Repository root path
---@return ForgeProvider|nil
function M.get(repo_root)
  return _providers[repo_root]
end

return M
