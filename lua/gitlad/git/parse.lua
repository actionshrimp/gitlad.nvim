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
---@field cherry_pick_in_progress? boolean Whether a cherry-pick is in progress
---@field revert_in_progress? boolean Whether a revert is in progress
---@field rebase_in_progress? boolean Whether a rebase is in progress
---@field merge_in_progress? boolean Whether a merge is in progress
---@field merge_head_oid? string OID of the commit being merged
---@field merge_head_subject? string Subject of the commit being merged
---@field sequencer_head_oid? string OID of the commit being cherry-picked/reverted
---@field sequencer_head_subject? string Subject of the commit being cherry-picked/reverted
---@field stashes StashEntry[] Recent stashes (populated by refresh_status)
---@field recent_commits GitCommitInfo[] Recent commits (populated by refresh_status)
---@field submodules SubmoduleEntry[] Submodule status entries (populated by refresh_status)

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
      -- <sub> is "S<c><m><u>" for submodules (S=Submodule, c/m/u indicate state)
      -- or "N..." for non-submodules (N=Not a submodule)
      local xy, sub, path = line:match("^1 (..) (....) %S+ %S+ %S+ %S+ %S+ (.+)$")
      if xy and path then
        local entry = {
          path = path,
          index_status = xy:sub(1, 1),
          worktree_status = xy:sub(2, 2),
          submodule = sub:sub(1, 1) == "S" and sub or nil,
        }
        M._categorize_entry(entry, result)
      end
    elseif line:match("^2 ") then
      -- Renamed/copied entry: 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><tab><origPath>
      -- <sub> format same as above
      local xy, sub, rest = line:match("^2 (..) (....) %S+ %S+ %S+ %S+ %S+ %S+ (.+)$")
      if xy and rest then
        local path, orig_path = rest:match("^(.+)\t(.+)$")
        if path and orig_path then
          local entry = {
            path = path,
            orig_path = orig_path,
            index_status = xy:sub(1, 1),
            worktree_status = xy:sub(2, 2),
            submodule = sub:sub(1, 1) == "S" and sub or nil,
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

---@class CommitRef
---@field name string Display name (e.g., "main", "origin/main", "v1.0")
---@field type "local"|"remote"|"tag" Ref type
---@field is_head boolean Whether this ref has HEAD pointing to it
---@field is_combined boolean Whether this combines local+remote at same commit
---@field remote_prefix string|nil For combined refs, the remote prefix (e.g., "origin/") to highlight separately

---@class GitCommitInfo
---@field hash string Short commit hash
---@field subject string Commit subject line
---@field author? string Author name (optional, for detailed views)
---@field date? string Relative date (optional)
---@field body? string Commit body/message (optional, for expansion)
---@field refs? CommitRef[] Array of refs pointing to this commit (optional)

--- Parse git decorations string (from %D format)
--- Input examples:
---   "HEAD -> main, origin/main, tag: v1.0"
---   "origin/feature"
---   "" (empty for commits without refs)
---@param decorate_str string The decorations string from git log %D
---@return CommitRef[]
function M.parse_decorations(decorate_str)
  if not decorate_str or decorate_str == "" then
    return {}
  end

  -- Split by ", " to get individual refs
  local raw_refs = {}
  for ref in (decorate_str .. ", "):gmatch("([^,]+), ") do
    local trimmed = vim.trim(ref)
    if trimmed ~= "" then
      table.insert(raw_refs, trimmed)
    end
  end

  -- First pass: collect all branch names (tags and HEAD handled separately)
  -- We need to know all branch names first to determine which are local vs remote
  local branch_names = {} -- Set of all branch-like ref names (excluding tags, HEAD)
  local tag_names = {} -- Set of tag names
  local head_target = nil -- Branch that HEAD points to, if any

  for _, ref_str in ipairs(raw_refs) do
    -- Check for "HEAD -> branch" pattern
    local target = ref_str:match("^HEAD%s*->%s*(.+)$")
    if target then
      head_target = target
      branch_names[target] = true
    -- Skip "origin/HEAD -> origin/branch" patterns
    elseif ref_str:match("^[^/]+/HEAD%s*->") then
      -- Skip these
      -- Check for "tag: name" pattern
    elseif ref_str:match("^tag:%s*") then
      local name = ref_str:match("^tag:%s*(.+)$")
      tag_names[name] = true
    -- Check for detached HEAD (just "HEAD")
    elseif ref_str == "HEAD" then
      -- Will be handled specially
      -- Everything else is a branch
    else
      branch_names[ref_str] = true
    end
  end

  -- Common remote names - used as fallback heuristic when we can't determine
  -- from context whether a branch is local or remote
  local common_remotes = {
    origin = true,
    upstream = true,
    fork = true,
    github = true,
    gitlab = true,
    bitbucket = true,
  }

  -- Second pass: classify branches as local or remote
  -- A branch "a/b/c" is considered remote if:
  --   1. There exists a branch "b/c" (the part after first slash), OR
  --   2. The first path component is a common remote name (origin, upstream, etc.)
  -- This handles: "main" (local), "origin/main" (remote because "main" exists OR "origin" is common),
  -- "feature/foo" (local), "origin/feature/foo" (remote because "feature/foo" exists OR "origin" is common)
  local remote_branches = {} -- Set of branch names that are remote
  for name, _ in pairs(branch_names) do
    -- Check if this looks like it could be a remote ref (has a slash)
    local first_component, after_first_slash = name:match("^([^/]+)/(.+)$")
    if first_component and after_first_slash then
      -- This is remote if the part after slash is also a branch, OR if first component is a common remote
      if branch_names[after_first_slash] or common_remotes[first_component] then
        remote_branches[name] = true
      end
    end
  end

  -- Third pass: build parsed refs with proper classification
  local parsed = {}
  local local_branch_indices = {} -- Map: branch_name -> index in parsed
  local remote_branch_indices = {} -- Map: "remote/branch" -> index in parsed

  for _, ref_str in ipairs(raw_refs) do
    ---@type CommitRef
    local ref = {
      name = "",
      type = "local",
      is_head = false,
      is_combined = false,
    }

    -- Check for "HEAD -> branch" pattern
    local target = ref_str:match("^HEAD%s*->%s*(.+)$")
    if target then
      ref.name = target
      ref.is_head = true
      -- Classify based on our remote detection
      ref.type = remote_branches[target] and "remote" or "local"
    -- Skip "origin/HEAD -> origin/branch" patterns
    elseif ref_str:match("^[^/]+/HEAD%s*->") then
      goto continue
    -- Check for "tag: name" pattern
    elseif ref_str:match("^tag:%s*") then
      ref.name = ref_str:match("^tag:%s*(.+)$")
      ref.type = "tag"
    -- Check for detached HEAD (just "HEAD")
    elseif ref_str == "HEAD" then
      ref.name = "HEAD"
      ref.type = "local"
      ref.is_head = true
    -- Everything else is a branch
    else
      ref.name = ref_str
      ref.type = remote_branches[ref_str] and "remote" or "local"
    end

    -- Track indices for deduplication
    if ref.type == "local" and ref.name ~= "HEAD" then
      local_branch_indices[ref.name] = #parsed + 1
    elseif ref.type == "remote" then
      remote_branch_indices[ref.name] = #parsed + 1
    end

    table.insert(parsed, ref)
    ::continue::
  end

  -- Fourth pass: combine local and remote branches that match
  -- When local "main" and "origin/main" both exist, keep only "origin/main" with is_combined=true
  local to_remove = {}
  for local_name, local_idx in pairs(local_branch_indices) do
    -- Look for matching remote refs
    for remote_name, remote_idx in pairs(remote_branch_indices) do
      -- Extract branch name from remote (e.g., "main" from "origin/main")
      local remote_prefix, remote_branch = remote_name:match("^([^/]+/)(.+)$")
      if remote_branch == local_name then
        -- Found a match! Mark remote as combined, mark local for removal
        parsed[remote_idx].is_combined = true
        parsed[remote_idx].remote_prefix = remote_prefix -- Store prefix for separate highlighting
        -- Transfer is_head from local to remote if HEAD points to the local branch
        if parsed[local_idx].is_head then
          parsed[remote_idx].is_head = true
        end
        to_remove[local_idx] = true
        break -- Only combine with first matching remote
      end
    end
  end

  -- Build final result, excluding removed refs
  -- Order: HEAD refs first, then tags, then other branches
  local head_refs = {}
  local tags = {}
  local branches = {}

  for i, ref in ipairs(parsed) do
    if not to_remove[i] then
      if ref.is_head then
        table.insert(head_refs, ref)
      elseif ref.type == "tag" then
        table.insert(tags, ref)
      else
        table.insert(branches, ref)
      end
    end
  end

  -- Combine in order: HEAD refs, tags, branches
  local result = {}
  for _, ref in ipairs(head_refs) do
    table.insert(result, ref)
  end
  for _, ref in ipairs(tags) do
    table.insert(result, ref)
  end
  for _, ref in ipairs(branches) do
    table.insert(result, ref)
  end

  return result
end

---@class StashEntry
---@field index number Stash index (0, 1, 2, ...)
---@field ref string Full stash ref (e.g., "stash@{0}")
---@field branch string Branch the stash was created on
---@field message string Stash message (either custom or default "WIP on <branch>")

---@class RefInfo
---@field name string Short ref name (e.g., "main", "origin/main", "v1.0.0")
---@field full_name string Full ref name (e.g., "refs/heads/main")
---@field hash string Short commit hash
---@field subject string Commit subject line
---@field type "local"|"remote"|"tag" Ref type
---@field remote? string Remote name for remote branches
---@field is_head boolean Whether this is the current HEAD
---@field upstream? string Upstream tracking ref (e.g., "origin/main")
---@field ahead? number Commits ahead of base ref (for local branches)
---@field behind? number Commits behind base ref (for local branches)

---@class CherryCommit
---@field hash string Commit hash
---@field subject string Commit subject
---@field equivalent boolean True if commit is in upstream (- prefix), false if unique (+ prefix)

---@class SubmoduleEntry
---@field path string Submodule path
---@field sha string Current HEAD SHA (40 chars)
---@field status "clean"|"modified"|"uninitialized"|"merge_conflict" Submodule status
---@field describe? string Output of git describe in submodule

---@class ReflogEntry
---@field hash string Short commit hash
---@field author string Author name
---@field selector string Reflog selector (e.g., "HEAD@{0}", "main@{2}")
---@field subject string Full reflog subject (e.g., "commit: message", "checkout: moving from X to Y")
---@field action_type string Extracted action type (e.g., "commit", "checkout", "reset")

---@class WorktreeEntry
---@field path string Absolute path to worktree directory
---@field head string HEAD commit SHA (40 chars)
---@field branch string|nil Branch name (nil if detached HEAD)
---@field is_main boolean Whether this is the main worktree (first in list)
---@field is_bare boolean Whether this is a bare repository
---@field locked boolean Whether the worktree is locked
---@field lock_reason string|nil Reason for locking (if locked)
---@field prunable boolean Whether the worktree is prunable (stale)
---@field prune_reason string|nil Reason why it's prunable

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

--- Check if a string looks like git refs (decorations)
--- Refs typically contain: HEAD, ->, tag:, origin/, or comma-separated branch names
---@param str string Potential refs string (without parentheses)
---@return boolean
local function looks_like_refs(str)
  if not str or str == "" then
    return false
  end
  -- Contains clear ref indicators
  if str:match("HEAD") or str:match("->") or str:match("tag:") then
    return true
  end
  -- Contains comma (multiple refs)
  if str:match(",") then
    return true
  end
  -- Looks like a remote ref (origin/something, upstream/something)
  if str:match("^origin/") or str:match("^upstream/") then
    return true
  end
  -- Simple branch name (no spaces, no special chars except /-_)
  if str:match("^[%w/_%-]+$") then
    return true
  end
  return false
end

--- Parse git log --oneline output
--- Handles both plain and decorated output:
---   "abc1234 commit subject"
---   "abc1234 (HEAD -> main, origin/main) commit subject"
---@param lines string[] Output lines from git log --oneline [--decorate]
---@return GitCommitInfo[]
function M.parse_log_oneline(lines)
  local commits = {}

  for _, line in ipairs(lines) do
    -- Try to match decorated format: "<hash> (<refs>) <subject>"
    local hash, potential_refs, after_refs = line:match("^(%S+)%s+%(([^)]+)%)%s*(.*)$")

    if hash and potential_refs and looks_like_refs(potential_refs) then
      -- Decorated format with refs
      table.insert(commits, {
        hash = hash,
        subject = after_refs or "",
        refs = M.parse_decorations(potential_refs),
      })
    else
      -- Plain format: "<hash> <subject>" (no refs, or parentheses are part of subject)
      hash, subject = line:match("^(%S+)%s+(.*)$")
      if hash then
        table.insert(commits, {
          hash = hash,
          subject = subject or "",
          refs = {},
        })
      end
    end
  end

  return commits
end

-- ASCII control characters for structured parsing
local LOG_RECORD_SEP = "\x1e" -- Record Separator (0x1E) - between commits
local LOG_FIELD_SEP = "\x1f" -- Unit Separator (0x1F) - between fields

--- Parse git log output with custom format
--- Records separated by RS (0x1E), fields by US (0x1F)
--- Format per record: hash<US>decorations<US>author<US>date<US>subject<US>body
--- Body is included so we know upfront which commits are expandable
---@param output string Raw output from git log
---@return GitCommitInfo[]
function M.parse_log_format(output)
  local commits = {}

  -- Split on record separator (0x1E)
  local records = vim.split(output, LOG_RECORD_SEP, { plain = true, trimempty = true })
  for _, record in ipairs(records) do
    -- Split first 5 fields on unit separator; everything after is body
    local fields = {}
    local pos = 1
    local field_count = 0
    while field_count < 5 do
      local sep_pos = record:find(LOG_FIELD_SEP, pos, true)
      if not sep_pos then
        break
      end
      table.insert(fields, record:sub(pos, sep_pos - 1))
      pos = sep_pos + 1
      field_count = field_count + 1
    end
    local body_raw = record:sub(pos)

    local hash = vim.trim(fields[1] or "")
    if hash ~= "" then
      local decorations = fields[2] or ""
      local author = fields[3] or ""
      local date_str = fields[4] or ""
      local subject = fields[5] or ""
      local body = vim.trim(body_raw)

      table.insert(commits, {
        hash = hash,
        author = author ~= "" and author or nil,
        date = date_str ~= "" and date_str or nil,
        subject = subject,
        body = body ~= "" and body or nil,
        refs = M.parse_decorations(decorations),
      })
    end
  end

  return commits
end

--- Get the git log format string for parse_log_format
--- Uses Record Separator (%x1e) between commits and Unit Separator (%x1f) between fields
--- Body (%b) is the last field so it can span multiple lines
---@return string
function M.get_log_format_string()
  return "%x1e%H%x1f%D%x1f%an%x1f%ar%x1f%s%x1f%b"
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

-- Separator used in git for-each-ref format for parsing refs
local REFS_FORMAT_SEP = "|||"

--- Get the git for-each-ref format string for parse_for_each_ref
---@return string
function M.get_refs_format_string()
  -- Format: refname:short|||objectname:short|||refname|||subject|||HEAD|||upstream:short
  return "%(refname:short)"
    .. REFS_FORMAT_SEP
    .. "%(objectname:short)"
    .. REFS_FORMAT_SEP
    .. "%(refname)"
    .. REFS_FORMAT_SEP
    .. "%(subject)"
    .. REFS_FORMAT_SEP
    .. "%(HEAD)"
    .. REFS_FORMAT_SEP
    .. "%(upstream:short)"
end

--- Parse git for-each-ref output
--- Format: refname:short|||objectname:short|||refname|||subject|||HEAD|||upstream:short
---@param lines string[] Output lines from git for-each-ref
---@return RefInfo[]
function M.parse_for_each_ref(lines)
  local refs = {}

  for _, line in ipairs(lines) do
    -- Format: "name|||hash|||full_name|||subject|||head_marker|||upstream"
    local name, hash, full_name, subject, head_marker, upstream =
      line:match("^([^|]*)|||([^|]*)|||([^|]*)|||(.-)|||([^|]*)|||([^|]*)$")

    if name and full_name then
      -- Skip remote HEAD refs (e.g., refs/remotes/origin/HEAD)
      if full_name:match("^refs/remotes/[^/]+/HEAD$") then
        goto continue
      end

      ---@type RefInfo
      local ref = {
        name = name,
        full_name = full_name,
        hash = hash or "",
        subject = subject or "",
        type = "local",
        is_head = head_marker == "*",
        upstream = (upstream and upstream ~= "") and upstream or nil,
      }

      -- Determine ref type from full_name
      if full_name:match("^refs/heads/") then
        ref.type = "local"
      elseif full_name:match("^refs/remotes/") then
        ref.type = "remote"
        -- Extract remote name (e.g., "origin" from "refs/remotes/origin/main")
        local remote = full_name:match("^refs/remotes/([^/]+)/")
        ref.remote = remote
      elseif full_name:match("^refs/tags/") then
        ref.type = "tag"
      end

      table.insert(refs, ref)
      ::continue::
    end
  end

  return refs
end

--- Parse git cherry -v output
--- Format: "+ abc1234 commit subject" or "- abc1234 commit subject"
---@param lines string[] Output lines from git cherry -v
---@return CherryCommit[]
function M.parse_cherry(lines)
  local commits = {}

  for _, line in ipairs(lines) do
    -- Format: "[+-] <hash> <subject>"
    local prefix, hash, subject = line:match("^([%+%-])%s+(%S+)%s+(.*)$")
    if prefix and hash then
      table.insert(commits, {
        hash = hash,
        subject = subject or "",
        equivalent = prefix == "-",
      })
    end
  end

  return commits
end

--- Parse git rev-list --left-right --count output
--- Format: "ahead\tbehind" (tab-separated)
---@param lines string[] Output lines from git rev-list --left-right --count
---@return number ahead, number behind
function M.parse_rev_list_count(lines)
  if not lines or #lines == 0 then
    return 0, 0
  end

  local line = lines[1]
  -- Format: "ahead\tbehind"
  local ahead, behind = line:match("^(%d+)\t(%d+)$")
  return tonumber(ahead) or 0, tonumber(behind) or 0
end

--- Parse git submodule status output
--- Format varies by status prefix:
---   " <sha> <path> (<describe>)" - clean (SHA matches recorded)
---   "+<sha> <path> (<describe>)" - modified (SHA differs from recorded)
---   "-<sha> <path>" - uninitialized
---   "U<sha> <path>" - merge conflict
---@param lines string[] Output lines from git submodule status
---@return SubmoduleEntry[]
function M.parse_submodule_status(lines)
  local submodules = {}

  for _, line in ipairs(lines) do
    -- First character is status prefix: space, +, -, or U
    local prefix = line:sub(1, 1)
    local rest = line:sub(2)

    -- Parse: <sha> <path> [(<describe>)]
    -- SHA is always 40 characters
    local sha, path_and_desc = rest:match("^(%x+)%s+(.+)$")

    if sha and path_and_desc then
      -- Check for describe in parentheses at the end
      local path, describe = path_and_desc:match("^(.-)%s+%((.+)%)$")
      if not path then
        -- No describe, just the path
        path = path_and_desc
        describe = nil
      end

      -- Determine status from prefix
      local status
      if prefix == " " then
        status = "clean"
      elseif prefix == "+" then
        status = "modified"
      elseif prefix == "-" then
        status = "uninitialized"
      elseif prefix == "U" then
        status = "merge_conflict"
      else
        -- Unknown prefix, skip
        status = "clean"
      end

      table.insert(submodules, {
        path = path,
        sha = sha,
        status = status,
        describe = describe,
      })
    end
  end

  return submodules
end

-- Separator used in git reflog format for parsing
local REFLOG_FORMAT_SEP = "\30" -- ASCII record separator %x1E

--- Extract action type from reflog subject
--- Examples:
---   "commit: Initial commit" -> "commit"
---   "commit (amend): Fix typo" -> "amend"
---   "commit (initial): Initial commit" -> "initial"
---   "checkout: moving from main to feature" -> "checkout"
---   "reset: moving to HEAD~1" -> "reset"
---   "pull: Fast-forward" -> "pull"
---   "rebase (start): checkout abc1234" -> "rebase"
---   "rebase (continue): message" -> "rebase"
---   "rebase (finish): refs/heads/feature onto abc1234" -> "rebase"
---   "rebase -i (start): checkout abc1234" -> "rebase"
---   "merge branch-name: Fast-forward" -> "merge"
---   "branch: Created from HEAD" -> "branch"
---@param subject string Reflog subject
---@return string action_type
function M.extract_reflog_action_type(subject)
  if not subject or subject == "" then
    return "unknown"
  end

  -- Check for "merge <branch>: message" pattern (special case)
  -- Merge reflog entries look like: "merge feature-branch: Fast-forward"
  if subject:match("^merge%s+[^:]+:") then
    return "merge"
  end

  -- Check for "rebase ..." patterns (with or without -i flag and subtype)
  -- e.g., "rebase (start):", "rebase -i (start):", "rebase (interactive) (start):"
  if subject:match("^rebase") then
    return "rebase"
  end

  -- Check for "command (type): message" pattern
  -- e.g., "commit (amend): message", "checkout (detached): message"
  local command, subtype = subject:match("^(%S+)%s*%(([^)]+)%)")
  if command and subtype then
    -- For commit, the subtype is more descriptive (amend, initial)
    if command == "commit" then
      return subtype
    end
    -- For other commands, use the command itself
    return command
  end

  -- Check for "command: message" pattern
  -- e.g., "commit: message", "checkout: moving from X to Y"
  local action = subject:match("^(%S+):")
  if action then
    -- Normalize some actions
    if action:match("^pull") then
      return "pull"
    elseif action:match("^cherry%-pick") then
      return "cherry-pick"
    end
    return action
  end

  return "unknown"
end

--- Parse git reflog output with custom format
--- Format: hash<RS>author<RS>selector<RS>subject
--- where <RS> is ASCII record separator (\30)
---@param lines string[] Output lines from git reflog show
---@return ReflogEntry[]
function M.parse_reflog(lines)
  local entries = {}

  for _, line in ipairs(lines) do
    -- Split by record separator
    local parts = vim.split(line, REFLOG_FORMAT_SEP, { plain = true })
    if #parts >= 4 then
      local hash = parts[1]
      local author = parts[2]
      local selector = parts[3]
      local subject = parts[4]
      local action_type = M.extract_reflog_action_type(subject)

      table.insert(entries, {
        hash = hash,
        author = author,
        selector = selector,
        subject = subject,
        action_type = action_type,
      })
    end
  end

  return entries
end

--- Parse git worktree list --porcelain output
--- Format (repeated for each worktree, separated by blank lines):
---   worktree /path/to/worktree
---   HEAD abc123...
---   branch refs/heads/branch-name  (or "detached" if detached HEAD)
---   [bare]                          (present if bare repository)
---   [locked [reason]]               (present if locked, optionally with reason)
---   [prunable [reason]]             (present if prunable/stale)
---@param lines string[] Output from git worktree list --porcelain
---@return WorktreeEntry[]
function M.parse_worktree_list(lines)
  local worktrees = {}
  local current = nil

  for _, line in ipairs(lines) do
    if line == "" then
      -- Blank line = end of entry
      if current then
        table.insert(worktrees, current)
        current = nil
      end
    elseif line:match("^worktree ") then
      -- Start of a new worktree entry
      current = {
        path = line:match("^worktree (.+)$"),
        head = "",
        branch = nil,
        is_main = false,
        is_bare = false,
        locked = false,
        lock_reason = nil,
        prunable = false,
        prune_reason = nil,
      }
    elseif current then
      if line:match("^HEAD ") then
        current.head = line:match("^HEAD (.+)$")
      elseif line:match("^branch ") then
        -- Format: "branch refs/heads/branch-name"
        local branch = line:match("^branch (.+)$")
        -- Strip refs/heads/ prefix to get clean branch name
        current.branch = branch:gsub("^refs/heads/", "")
      elseif line == "detached" then
        -- Detached HEAD - branch stays nil
        current.branch = nil
      elseif line == "bare" then
        current.is_bare = true
      elseif line:match("^locked") then
        current.locked = true
        -- Reason is on the same line after "locked " (optional)
        current.lock_reason = line:match("^locked (.+)$")
      elseif line:match("^prunable") then
        current.prunable = true
        -- Reason is on the same line after "prunable " (optional)
        current.prune_reason = line:match("^prunable (.+)$")
      end
    end
  end

  -- Don't forget the last entry (if file doesn't end with blank line)
  if current then
    table.insert(worktrees, current)
  end

  -- Mark first worktree as main (primary worktree is always first)
  if #worktrees > 0 then
    worktrees[1].is_main = true
  end

  return worktrees
end

---@class BlameCommitInfo
---@field hash string Full commit hash (40 chars)
---@field author string Author name
---@field author_time number Author timestamp (epoch seconds)
---@field summary string Commit subject line
---@field previous_hash? string Parent commit hash (for blame-on-blame)
---@field previous_filename? string Filename in parent commit
---@field boundary boolean Whether this is a boundary commit
---@field filename string Filename in this commit

---@class BlameLine
---@field hash string Full commit hash
---@field orig_line number Original line number in the commit
---@field final_line number Line number in the current file
---@field content string Line content (without leading tab)

---@class BlameResult
---@field commits table<string, BlameCommitInfo> Map of hash to commit info
---@field lines BlameLine[] Ordered blame lines
---@field file string File path that was blamed

--- Parse git blame --porcelain output
--- See: https://git-scm.com/docs/git-blame#_the_porcelain_format
---@param output string[] Lines from git blame --porcelain
---@return BlameResult
function M.parse_blame_porcelain(output)
  local result = {
    commits = {},
    lines = {},
    file = "",
  }

  local current_hash = nil
  local current_orig_line = nil
  local current_final_line = nil

  for _, line in ipairs(output) do
    -- Commit header line: <hash> <orig_line> <final_line> [<num_lines>]
    local hash, orig, final = line:match("^(%x%x%x%x%x%x%x+)%s+(%d+)%s+(%d+)")
    if hash then
      current_hash = hash
      current_orig_line = tonumber(orig)
      current_final_line = tonumber(final)

      -- Initialize commit info if first time seeing this hash
      if not result.commits[hash] then
        result.commits[hash] = {
          hash = hash,
          author = "",
          author_time = 0,
          summary = "",
          boundary = false,
          filename = "",
        }
      end
    elseif current_hash then
      -- Content line (starts with tab)
      if line:sub(1, 1) == "\t" then
        table.insert(result.lines, {
          hash = current_hash,
          orig_line = current_orig_line,
          final_line = current_final_line,
          content = line:sub(2),
        })
      else
        -- Metadata line for current commit
        local commit = result.commits[current_hash]
        if commit then
          local key, value = line:match("^(%S+)%s?(.*)")
          if key == "author" then
            commit.author = value
          elseif key == "author-time" then
            commit.author_time = tonumber(value) or 0
          elseif key == "summary" then
            commit.summary = value
          elseif key == "previous" then
            local prev_hash, prev_file = value:match("^(%x+)%s+(.+)")
            if prev_hash then
              commit.previous_hash = prev_hash
              commit.previous_filename = prev_file
            end
          elseif key == "boundary" then
            commit.boundary = true
          elseif key == "filename" then
            commit.filename = value
            if result.file == "" then
              result.file = value
            end
          end
        end
      end
    end
  end

  return result
end

return M
