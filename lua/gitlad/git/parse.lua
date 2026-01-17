---@mod gitlad.git.parse Git output parsing utilities
---@brief [[
--- Parsers for various git command outputs.
--- Uses --porcelain formats where available for stability.
---@brief ]]

local M = {}

---@class GitStatusEntry
---@field path string File path
---@field orig_path? string Original path (for renames)
---@field index_status string Status in index (staged)
---@field worktree_status string Status in worktree (unstaged)
---@field submodule? string Submodule status if applicable

---@class GitStatusResult
---@field branch string Current branch name
---@field oid string Current commit OID
---@field upstream? string Upstream branch name
---@field ahead number Commits ahead of upstream
---@field behind number Commits behind upstream
---@field staged GitStatusEntry[] Staged files
---@field unstaged GitStatusEntry[] Unstaged files
---@field untracked GitStatusEntry[] Untracked files
---@field conflicted GitStatusEntry[] Files with conflicts

-- Status codes from git status --porcelain=v2
local STATUS_CODES = {
  ["."] = "unmodified",
  ["M"] = "modified",
  ["T"] = "typechange",
  ["A"] = "added",
  ["D"] = "deleted",
  ["R"] = "renamed",
  ["C"] = "copied",
  ["U"] = "unmerged",
}

--- Parse git status --porcelain=v2 output
---@param lines string[] Output lines from git status
---@return GitStatusResult
function M.parse_status(lines)
  local result = {
    branch = "",
    oid = "",
    upstream = nil,
    ahead = 0,
    behind = 0,
    staged = {},
    unstaged = {},
    untracked = {},
    conflicted = {},
  }

  for _, line in ipairs(lines) do
    if line:match("^# branch%.head") then
      result.branch = line:match("^# branch%.head (.+)$") or ""
    elseif line:match("^# branch%.oid") then
      result.oid = line:match("^# branch%.oid (.+)$") or ""
    elseif line:match("^# branch%.upstream") then
      result.upstream = line:match("^# branch%.upstream (.+)$")
    elseif line:match("^# branch%.ab") then
      local ahead, behind = line:match("^# branch%.ab %+(%d+) %-(%d+)$")
      result.ahead = tonumber(ahead) or 0
      result.behind = tonumber(behind) or 0
    elseif line:match("^1 ") then
      -- Ordinary changed entry: 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
      local xy, sub, path = line:match("^1 (..) (....) %S+ %S+ %S+ %S+ %S+ (.+)$")
      if xy and path then
        local entry = {
          path = path,
          index_status = xy:sub(1, 1),
          worktree_status = xy:sub(2, 2),
          submodule = sub ~= "...." and sub or nil,
        }
        M._categorize_entry(entry, result)
      end
    elseif line:match("^2 ") then
      -- Renamed/copied entry: 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><tab><origPath>
      local xy, sub, rest = line:match("^2 (..) (....) %S+ %S+ %S+ %S+ %S+ %S+ (.+)$")
      if xy and rest then
        local path, orig_path = rest:match("^(.+)\t(.+)$")
        if path and orig_path then
          local entry = {
            path = path,
            orig_path = orig_path,
            index_status = xy:sub(1, 1),
            worktree_status = xy:sub(2, 2),
            submodule = sub ~= "...." and sub or nil,
          }
          M._categorize_entry(entry, result)
        end
      end
    elseif line:match("^u ") then
      -- Unmerged entry: u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
      local xy, path = line:match("^u (..) %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$")
      if xy and path then
        table.insert(result.conflicted, {
          path = path,
          index_status = xy:sub(1, 1),
          worktree_status = xy:sub(2, 2),
        })
      end
    elseif line:match("^%? ") then
      -- Untracked: ? <path>
      local path = line:match("^%? (.+)$")
      if path then
        table.insert(result.untracked, {
          path = path,
          index_status = "?",
          worktree_status = "?",
        })
      end
    elseif line:match("^! ") then
      -- Ignored (we typically don't request these)
    end
  end

  return result
end

--- Categorize a status entry into staged/unstaged
---@param entry GitStatusEntry
---@param result GitStatusResult
function M._categorize_entry(entry, result)
  -- Check if staged (index has changes)
  if entry.index_status ~= "." then
    table.insert(result.staged, entry)
  end
  -- Check if unstaged (worktree has changes)
  if entry.worktree_status ~= "." then
    table.insert(result.unstaged, entry)
  end
end

--- Parse git branch output
---@param lines string[] Output from git branch
---@return table[] Array of branch info
function M.parse_branches(lines)
  local branches = {}
  for _, line in ipairs(lines) do
    local current = line:match("^%*") ~= nil
    local name = line:match("^[%*%s]+(.+)$")
    if name then
      -- Handle detached HEAD
      if name:match("^%(HEAD detached") then
        name = "HEAD (detached)"
      end
      table.insert(branches, {
        name = vim.trim(name),
        current = current,
      })
    end
  end
  return branches
end

--- Get human-readable status description
---@param code string Single character status code
---@return string
function M.status_description(code)
  return STATUS_CODES[code] or "unknown"
end

---@class GitRemote
---@field name string Remote name (e.g., "origin")
---@field fetch_url string Fetch URL
---@field push_url string Push URL

--- Parse git remote -v output
---@param lines string[] Output lines from git remote -v
---@return GitRemote[]
function M.parse_remotes(lines)
  local remotes = {}
  local remote_map = {} -- name -> { fetch_url, push_url }

  for _, line in ipairs(lines) do
    -- Format: "origin\thttps://github.com/user/repo.git (fetch)"
    -- or: "origin\tgit@github.com:user/repo.git (push)"
    local name, url, type_str = line:match("^(%S+)\t(%S+)%s+%((%w+)%)$")
    if name and url and type_str then
      if not remote_map[name] then
        remote_map[name] = { name = name, fetch_url = "", push_url = "" }
      end
      if type_str == "fetch" then
        remote_map[name].fetch_url = url
      elseif type_str == "push" then
        remote_map[name].push_url = url
      end
    end
  end

  -- Convert map to array (maintain consistent ordering)
  local names = {}
  for name, _ in pairs(remote_map) do
    table.insert(names, name)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    table.insert(remotes, remote_map[name])
  end

  return remotes
end

return M
