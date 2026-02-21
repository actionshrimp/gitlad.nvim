---@mod gitlad.git.git_commits Commit operations
---@brief [[
--- Commit-related git operations: commit, amend, fixup, squash, log, cherry-pick, revert.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")
local errors = require("gitlad.utils.errors")

--- Create a commit with a message
---@param message_lines string[] Commit message lines
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit(message_lines, args, opts, callback)
  -- Build commit args: commit -F - <extra_args>
  -- Using -F - to read message from stdin avoids shell escaping issues
  local commit_args = { "commit", "-F", "-" }
  vim.list_extend(commit_args, args)

  cli.run_async_with_stdin(commit_args, message_lines, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Amend the current commit without editing the message
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_amend_no_edit(args, opts, callback)
  local commit_args = { "commit", "--amend", "--no-edit" }
  vim.list_extend(commit_args, args)

  cli.run_async(commit_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Create a fixup or squash commit (message is auto-generated)
--- Used for --fixup=<commit> or --squash=<commit> which generate their own message
---@param args string[] Arguments including --fixup=<hash> or --squash=<hash>
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_fixup(args, opts, callback)
  local commit_args = { "commit" }
  vim.list_extend(commit_args, args)

  cli.run_async(commit_args, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Create a commit with streaming output viewer
--- Shows a floating window with real-time hook output
---@param message_lines string[] Commit message lines
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_streaming(message_lines, args, opts, callback)
  local output_viewer = require("gitlad.ui.views.output")

  -- Build display command for the viewer
  local display_cmd = "git commit " .. table.concat(args, " ")

  local viewer = output_viewer.create({
    title = "Commit",
    command = display_cmd,
  })

  -- Build commit args: commit -F - <extra_args>
  local commit_args = { "commit", "-F", "-" }
  vim.list_extend(commit_args, args)

  cli.run_async_with_stdin(commit_args, message_lines, {
    cwd = opts and opts.cwd,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(result)
    viewer:complete(result.code)
    callback(errors.result_to_callback(result))
  end)
end

--- Amend the current commit without editing the message, with streaming output viewer
--- Shows a floating window with real-time hook output
---@param args string[] Extra arguments (from popup switches/options)
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.commit_amend_no_edit_streaming(args, opts, callback)
  local output_viewer = require("gitlad.ui.views.output")

  -- Build display command for the viewer
  local display_cmd = "git commit --amend --no-edit " .. table.concat(args, " ")

  local viewer = output_viewer.create({
    title = "Amend",
    command = display_cmd,
  })

  local commit_args = { "commit", "--amend", "--no-edit" }
  vim.list_extend(commit_args, args)

  cli.run_async(commit_args, {
    cwd = opts and opts.cwd,
    on_output_line = function(line, is_stderr)
      viewer:append(line, is_stderr)
    end,
  }, function(result)
    viewer:complete(result.code)
    callback(errors.result_to_callback(result))
  end)
end

--- Get the commit subject for a ref
---@param ref string Git ref (branch, tag, commit hash)
---@param opts? GitCommandOptions
---@param callback fun(subject: string|nil, err: string|nil)
function M.get_commit_subject(ref, opts, callback)
  cli.run_async({ "log", "-1", "--format=%s", ref }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(result.stdout[1] or "", nil)
  end)
end

--- Get commits between two refs
---@param base string Base ref (the older end)
---@param target string Target ref (the newer end)
---@param opts? GitCommandOptions
---@param callback fun(commits: GitCommitInfo[]|nil, err: string|nil)
function M.get_commits_between(base, target, opts, callback)
  -- git log base..target shows commits reachable from target but not from base
  -- Use --decorate to get refs (branches, tags) on commits
  cli.run_async({ "log", "--oneline", "--decorate", base .. ".." .. target }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_log_oneline(result.stdout), nil)
  end)
end

--- Get commit log (basic oneline format)
---@param args string[] Additional log arguments (e.g., { "-20" }, { "main..HEAD" })
---@param opts? GitCommandOptions
---@param callback fun(commits: GitCommitInfo[]|nil, err: string|nil)
function M.log(args, opts, callback)
  -- Use --decorate to get refs (branches, tags) on commits
  local log_args = { "log", "--oneline", "--decorate" }
  vim.list_extend(log_args, args)

  cli.run_async(log_args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_log_oneline(result.stdout), nil)
  end)
end

--- Get commit log with detailed info (author, date)
---@param args string[] Additional log arguments (e.g., { "-20" }, { "main..HEAD" })
---@param opts? GitCommandOptions
---@param callback fun(commits: GitCommitInfo[]|nil, err: string|nil)
function M.log_detailed(args, opts, callback)
  local format = parse.get_log_format_string()
  local log_args = { "log", "--format=" .. format }
  vim.list_extend(log_args, args)

  cli.run_async(log_args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_log_format(table.concat(result.stdout, "\n")), nil)
  end)
end

--- Get commit message body
---@param hash string Commit hash
---@param opts? GitCommandOptions
---@param callback fun(body: string|nil, err: string|nil)
function M.show_commit(hash, opts, callback)
  -- Get just the commit body (message after subject)
  local args = { "log", "-1", "--format=%b", hash }

  cli.run_async(args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    local body = table.concat(result.stdout, "\n")
    -- Trim trailing whitespace
    body = body:gsub("%s+$", "")
    callback(body ~= "" and body or nil, nil)
  end)
end

--- Cherry-pick one or more commits
---@param commits string[] Commit hashes to cherry-pick
---@param args string[] Extra arguments (from popup switches, e.g., {"-x", "--signoff"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.cherry_pick(commits, args, opts, callback)
  local cherry_pick_args = { "cherry-pick" }
  vim.list_extend(cherry_pick_args, args)
  vim.list_extend(cherry_pick_args, commits)

  cli.run_async(cherry_pick_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Continue an in-progress cherry-pick
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.cherry_pick_continue(opts, callback)
  cli.run_async({ "cherry-pick", "--continue" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress cherry-pick
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.cherry_pick_abort(opts, callback)
  cli.run_async({ "cherry-pick", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Skip the current commit during cherry-pick
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.cherry_pick_skip(opts, callback)
  cli.run_async({ "cherry-pick", "--skip" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Revert one or more commits
---@param commits string[] Commit hashes to revert
---@param args string[] Extra arguments (from popup switches, e.g., {"--no-edit", "--signoff"})
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, output: string|nil, err: string|nil)
function M.revert(commits, args, opts, callback)
  local revert_args = { "revert" }
  vim.list_extend(revert_args, args)
  vim.list_extend(revert_args, commits)

  cli.run_async(revert_args, opts, function(result)
    local stdout = table.concat(result.stdout, "\n")
    local stderr = table.concat(result.stderr, "\n")
    local output = stdout ~= "" and stdout or stderr
    callback(result.code == 0, output, result.code ~= 0 and stderr or nil)
  end)
end

--- Continue an in-progress revert
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.revert_continue(opts, callback)
  cli.run_async({ "revert", "--continue" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Abort an in-progress revert
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.revert_abort(opts, callback)
  cli.run_async({ "revert", "--abort" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Skip the current commit during revert
---@param opts? GitCommandOptions
---@param callback fun(success: boolean, err: string|nil)
function M.revert_skip(opts, callback)
  cli.run_async({ "revert", "--skip" }, opts, function(result)
    callback(errors.result_to_callback(result))
  end)
end

--- Get cherry commits between ref and upstream (commits unique to ref)
--- Shows commits in ref that are not in upstream, with equivalence markers
---@param ref string The ref to check (e.g., "feature-branch")
---@param upstream string The upstream to compare against (e.g., "main")
---@param opts? GitCommandOptions
---@param callback fun(commits: CherryCommit[]|nil, err: string|nil)
function M.cherry(ref, upstream, opts, callback)
  -- git cherry -v <upstream> <ref> shows commits in ref not in upstream
  -- + means unique to ref, - means equivalent (cherry-picked) commit exists in upstream
  cli.run_async({ "cherry", "-v", upstream, ref }, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    callback(parse.parse_cherry(result.stdout), nil)
  end)
end

--- Get ahead/behind count between ref and another ref
---@param ref string The ref to check
---@param compare_to string The ref to compare against
---@param opts? GitCommandOptions
---@param callback fun(ahead: number, behind: number, err: string|nil)
function M.rev_list_count(ref, compare_to, opts, callback)
  -- git rev-list --left-right --count ref...compare_to
  -- Output: "ahead\tbehind"
  cli.run_async(
    { "rev-list", "--left-right", "--count", ref .. "..." .. compare_to },
    opts,
    function(result)
      if result.code ~= 0 then
        callback(0, 0, table.concat(result.stderr, "\n"))
        return
      end
      local ahead, behind = parse.parse_rev_list_count(result.stdout)
      callback(ahead, behind, nil)
    end
  )
end

return M
