---@mod gitlad.ui.views.diff.source DiffSpec producers
---@brief [[
--- Functions that run git diff commands and parse the output into DiffSpec objects.
--- Each producer runs `git diff [args]` via cli.run_async, parses through hunk.parse_unified_diff,
--- and calls back with a DiffSpec.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local hunk = require("gitlad.ui.views.diff.hunk")

--- Build git command arguments for a given diff source type
---@param source_type DiffSourceType The type of diff source
---@param ref_or_range string|nil Ref or range argument (depends on source_type)
---@return string[] args Git command arguments (without 'git' prefix)
function M._build_args(source_type, ref_or_range)
  if source_type == "staged" then
    return { "diff", "--cached" }
  elseif source_type == "unstaged" then
    return { "diff" }
  elseif source_type == "worktree" then
    return { "diff", "HEAD" }
  elseif source_type == "commit" then
    assert(ref_or_range, "commit source requires a ref")
    return { "show", "--format=", ref_or_range }
  elseif source_type == "range" then
    assert(ref_or_range, "range source requires a range expression")
    return { "diff", ref_or_range }
  elseif source_type == "stash" then
    assert(ref_or_range, "stash source requires a stash ref")
    return { "stash", "show", "-p", ref_or_range }
  else
    error("Unknown diff source type: " .. tostring(source_type))
  end
end

--- Format the file count suffix for titles (e.g., " (3 files)" or " (1 file)")
---@param file_pairs DiffFilePair[] Parsed file pairs
---@return string suffix Formatted suffix like " (3 files)"
function M._format_file_count(file_pairs)
  local n = #file_pairs
  if n == 0 then
    return " (empty)"
  elseif n == 1 then
    return " (1 file)"
  else
    return string.format(" (%d files)", n)
  end
end

--- Build a display title for a diff source
---@param source DiffSource The diff source descriptor
---@param file_pairs DiffFilePair[] Parsed file pairs (for file count)
---@return string title Human-readable title
function M._build_title(source, file_pairs)
  local suffix = M._format_file_count(file_pairs)

  if source.type == "staged" then
    return "Diff staged" .. suffix
  elseif source.type == "unstaged" then
    return "Diff unstaged" .. suffix
  elseif source.type == "worktree" then
    return "Diff worktree" .. suffix
  elseif source.type == "commit" then
    local short_ref = source.ref or "unknown"
    if #short_ref > 7 then
      short_ref = short_ref:sub(1, 7)
    end
    return "Commit " .. short_ref .. suffix
  elseif source.type == "range" then
    return "Diff " .. (source.range or "unknown") .. suffix
  elseif source.type == "stash" then
    return "Stash " .. (source.ref or "unknown") .. suffix
  elseif source.type == "pr" then
    local pr_info = source.pr_info
    if not pr_info then
      return "PR" .. suffix
    end
    if source.selected_commit then
      local commit = pr_info.commits and pr_info.commits[source.selected_commit]
      if commit then
        return string.format(
          "PR #%d: %s (%s)%s",
          pr_info.number,
          commit.message_headline,
          commit.short_oid,
          suffix
        )
      end
    end
    return string.format("PR #%d %s%s", pr_info.number, pr_info.title, suffix)
  else
    return "Diff" .. suffix
  end
end

--- Build a DiffSpec from its components (pure, synchronous, testable)
---@param source DiffSource The diff source descriptor
---@param file_pairs DiffFilePair[] Parsed file pairs from hunk.parse_unified_diff
---@param repo_root string Repository root path
---@return DiffSpec
function M._build_diff_spec(source, file_pairs, repo_root)
  return {
    source = source,
    file_pairs = file_pairs,
    title = M._build_title(source, file_pairs),
    repo_root = repo_root,
  }
end

--- Internal: run a git diff command and parse the output into a DiffSpec
---@param source DiffSource The diff source descriptor
---@param args string[] Git command arguments
---@param repo_root string Repository root path
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
local function run_diff(source, args, repo_root, cb)
  cli.run_async(args, { cwd = repo_root }, function(result)
    if result.code ~= 0 then
      local err_msg = table.concat(result.stderr, "\n")
      if err_msg == "" then
        err_msg = "git command failed with exit code " .. result.code
      end
      cb(nil, err_msg)
      return
    end

    local file_pairs = hunk.parse_unified_diff(result.stdout)
    local diff_spec = M._build_diff_spec(source, file_pairs, repo_root)
    cb(diff_spec, nil)
  end)
end

--- Produce a DiffSpec for staged changes (git diff --cached)
---@param repo_root string Repository root path
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_staged(repo_root, cb)
  local source = { type = "staged" }
  local args = M._build_args("staged")
  run_diff(source, args, repo_root, cb)
end

--- Produce a DiffSpec for unstaged changes (git diff)
---@param repo_root string Repository root path
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_unstaged(repo_root, cb)
  local source = { type = "unstaged" }
  local args = M._build_args("unstaged")
  run_diff(source, args, repo_root, cb)
end

--- Produce a DiffSpec for all worktree changes vs HEAD (git diff HEAD)
---@param repo_root string Repository root path
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_worktree(repo_root, cb)
  local source = { type = "worktree" }
  local args = M._build_args("worktree")
  run_diff(source, args, repo_root, cb)
end

--- Produce a DiffSpec for a single commit (git show --format="" <ref>)
---@param repo_root string Repository root path
---@param ref string Commit ref (hash, branch, tag, etc.)
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_commit(repo_root, ref, cb)
  local source = { type = "commit", ref = ref }
  local args = M._build_args("commit", ref)
  run_diff(source, args, repo_root, cb)
end

--- Produce a DiffSpec for a range (git diff <range>)
---@param repo_root string Repository root path
---@param range string Range expression (e.g., "main..HEAD", "abc123..def456")
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_range(repo_root, range, cb)
  local source = { type = "range", range = range }
  local args = M._build_args("range", range)
  run_diff(source, args, repo_root, cb)
end

--- Produce a DiffSpec for a stash entry (git stash show -p <ref>)
---@param repo_root string Repository root path
---@param stash_ref string Stash reference (e.g., "stash@{0}")
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_stash(repo_root, stash_ref, cb)
  local source = { type = "stash", ref = stash_ref }
  local args = M._build_args("stash", stash_ref)
  run_diff(source, args, repo_root, cb)
end

--- Build git diff arguments for a PR source
---@param pr_info DiffPRInfo PR info with base/head OIDs and commits
---@param selected_index number|nil Index into pr_info.commits (nil = full PR diff)
---@return string[] args Git command arguments
---@return string|nil err Error message if invalid
function M._build_pr_args(pr_info, selected_index)
  if selected_index == nil then
    -- Full PR diff (three-dot: changes introduced by head relative to merge base)
    return { "diff", pr_info.base_oid .. "..." .. pr_info.head_oid }, nil
  end

  local commit = pr_info.commits and pr_info.commits[selected_index]
  if not commit then
    return {}, "Invalid commit index: " .. tostring(selected_index)
  end

  -- Single commit diff
  local parent
  if selected_index == 1 then
    parent = pr_info.base_oid
  else
    parent = pr_info.commits[selected_index - 1].oid
  end
  return { "diff", parent .. ".." .. commit.oid }, nil
end

--- Produce a DiffSpec for a PR (full diff or single commit within the PR)
---@param repo_root string Repository root path
---@param pr_info DiffPRInfo PR info with base/head OIDs and commits
---@param selected_index number|nil Index into pr_info.commits (nil = full PR diff)
---@param cb fun(diff_spec: DiffSpec|nil, err: string|nil) Callback
function M.produce_pr(repo_root, pr_info, selected_index, cb)
  local args, err = M._build_pr_args(pr_info, selected_index)
  if err then
    cb(nil, err)
    return
  end

  local source = {
    type = "pr",
    pr_info = pr_info,
    selected_commit = selected_index,
  }
  run_diff(source, args, repo_root, cb)
end

return M
