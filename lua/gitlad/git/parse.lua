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
---@field upstream? string Upstream branch name (merge remote)
---@field ahead number Commits ahead of upstream
---@field behind number Commits behind upstream
---@field staged GitStatusEntry[] Staged files
---@field unstaged GitStatusEntry[] Unstaged files
---@field untracked GitStatusEntry[] Untracked files
---@field conflicted GitStatusEntry[] Files with conflicts
---@field head_commit_msg? string HEAD commit subject
---@field merge_commit_msg? string Upstream commit subject
---@field push_remote? string Push remote ref (e.g., "origin/feature")
---@field push_ahead number Commits ahead of push remote
---@field push_behind number Commits behind push remote
---@field push_commit_msg? string Push remote commit subject
---@field unpulled_upstream GitCommitInfo[] Commits to pull from upstream
---@field unpushed_upstream GitCommitInfo[] Commits to push to upstream
---@field unpulled_push GitCommitInfo[] Commits to pull from push remote
---@field unpushed_push GitCommitInfo[] Commits to push to push remote

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
    -- Extended fields (populated by refresh_status)
    head_commit_msg = nil,
    merge_commit_msg = nil,
    push_remote = nil,
    push_ahead = 0,
    push_behind = 0,
    push_commit_msg = nil,
    unpulled_upstream = {},
    unpushed_upstream = {},
    unpulled_push = {},
    unpushed_push = {},
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

---@class GitCommitInfo
---@field hash string Short commit hash
---@field subject string Commit subject line
---@field author? string Author name (optional, for detailed views)
---@field date? string Relative date (optional)
---@field body? string Commit body/message (optional, for expansion)

---@class StashEntry
---@field index number Stash index (0, 1, 2, ...)
---@field ref string Full stash ref (e.g., "stash@{0}")
---@field branch string Branch the stash was created on
---@field message string Stash message (either custom or default "WIP on <branch>")

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

--- Parse git log --oneline output
---@param lines string[] Output lines from git log --oneline
---@return GitCommitInfo[]
function M.parse_log_oneline(lines)
  local commits = {}

  for _, line in ipairs(lines) do
    -- Format: "<hash> <subject>" (space separated, hash is first word)
    local hash, subject = line:match("^(%S+)%s+(.*)$")
    if hash then
      table.insert(commits, {
        hash = hash,
        subject = subject or "",
      })
    end
  end

  return commits
end

-- Separator used in git log --format for parsing
local LOG_FORMAT_SEP = "|||"

--- Parse git log output with custom format
--- Format: hash|||author|||date|||subject
--- Each commit is separated by a record separator (newline + COMMIT_START marker)
---@param output string Raw output from git log
---@return GitCommitInfo[]
function M.parse_log_format(output)
  local commits = {}

  -- Split by newlines and parse each line as a commit
  for line in output:gmatch("[^\n]+") do
    -- Format: "hash|||author|||date|||subject"
    local hash, author, date, subject = line:match("^([^|]+)|||([^|]*)|||([^|]*)|||(.*)$")
    if hash then
      table.insert(commits, {
        hash = hash,
        author = author ~= "" and author or nil,
        date = date ~= "" and date or nil,
        subject = subject or "",
      })
    end
  end

  return commits
end

--- Get the git log format string for parse_log_format
---@return string
function M.get_log_format_string()
  return "%h" .. LOG_FORMAT_SEP .. "%an" .. LOG_FORMAT_SEP .. "%ar" .. LOG_FORMAT_SEP .. "%s"
end

--- Parse git branch -r output (remote branches)
---@param lines string[] Output lines from git branch -r
---@return string[] Array of remote branch names (e.g., "origin/main")
function M.parse_remote_branches(lines)
  local branches = {}
  for _, line in ipairs(lines) do
    -- Format: "  origin/main" or "  origin/HEAD -> origin/main"
    local trimmed = vim.trim(line)
    -- Skip HEAD pointers
    if not trimmed:match("^%S+/HEAD%s*->") then
      table.insert(branches, trimmed)
    end
  end
  return branches
end

--- Parse git stash list output
--- Format: "stash@{0}: WIP on main: abc1234 commit subject"
---      or "stash@{0}: On main: custom message"
---@param lines string[] Output lines from git stash list
---@return StashEntry[]
function M.parse_stash_list(lines)
  local stashes = {}

  for _, line in ipairs(lines) do
    -- Try WIP format first: "stash@{N}: WIP on <branch>: <message>"
    local index_str, branch, message = line:match("^stash@{(%d+)}: WIP on ([^:]+): (.*)$")

    if index_str and branch then
      local index = tonumber(index_str)
      table.insert(stashes, {
        index = index,
        ref = "stash@{" .. index_str .. "}",
        branch = branch,
        message = "WIP on " .. branch .. ": " .. (message or ""),
      })
    else
      -- Try custom message format: "stash@{N}: On <branch>: <message>"
      index_str, branch, message = line:match("^stash@{(%d+)}: On ([^:]+): (.*)$")

      if index_str and branch then
        local index = tonumber(index_str)
        table.insert(stashes, {
          index = index,
          ref = "stash@{" .. index_str .. "}",
          branch = branch,
          message = message or "",
        })
      end
    end
  end

  return stashes
end

return M
