---@mod gitlad.utils.remote Remote/ref utilities
---@brief [[
--- Shared helpers for extracting remote names and push targets from git status.
---@brief ]]

local M = {}

--- Extract remote name from ref (e.g., "origin/main" -> "origin")
---@param ref string|nil
---@return string|nil
function M.get_remote_from_ref(ref)
  if not ref then
    return nil
  end
  return ref:match("^([^/]+)/")
end

--- Get the push remote for the current branch
--- Returns the remote that would be used for pushing (may differ from upstream)
---@param status GitStatusResult|nil
---@return string|nil remote Remote name like "origin"
function M.get_push_remote(status)
  if not status then
    return nil
  end

  -- Use explicitly calculated push_remote if available
  if status.push_remote then
    return M.get_remote_from_ref(status.push_remote)
  end

  -- Fall back to deriving from upstream
  if status.upstream then
    return M.get_remote_from_ref(status.upstream)
  end

  return nil
end

--- Get the effective push target for the current branch
--- This returns the same push_remote that the status view displays
---@param status GitStatusResult|nil
---@return string|nil push_ref Full ref like "origin/feature-branch"
---@return string|nil remote Remote name like "origin"
function M.get_push_target(status)
  if not status then
    return nil, nil
  end

  -- Use explicitly calculated push_remote if available
  if status.push_remote then
    local remote = M.get_remote_from_ref(status.push_remote)
    return status.push_remote, remote
  end

  -- Fall back to computing it the same way state/init.lua does
  -- Push goes to <remote>/<branch> where remote is derived from upstream
  if status.upstream then
    local remote = M.get_remote_from_ref(status.upstream)
    if remote then
      return remote .. "/" .. status.branch, remote
    end
  end

  return nil, nil
end

return M
