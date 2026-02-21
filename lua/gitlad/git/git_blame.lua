---@mod gitlad.git.git_blame Blame operations
---@brief [[
--- Git blame operations using --porcelain format for stable parsing.
---@brief ]]

local M = {}

local cli = require("gitlad.git.cli")
local parse = require("gitlad.git.parse")

--- Run git blame on a file
---@param file string File path (relative to repo root)
---@param revision? string Optional revision to blame at (e.g., "HEAD~1", "abc123")
---@param extra_args? string[] Extra args (e.g., {"-w", "-M", "-C"})
---@param opts? GitCommandOptions
---@param callback fun(result: BlameResult|nil, err: string|nil)
function M.blame(file, revision, extra_args, opts, callback)
  local args = { "blame", "--porcelain" }

  if extra_args then
    vim.list_extend(args, extra_args)
  end

  if revision then
    table.insert(args, revision)
  end

  table.insert(args, "--")
  table.insert(args, file)

  cli.run_async(args, opts, function(result)
    if result.code ~= 0 then
      callback(nil, table.concat(result.stderr, "\n"))
      return
    end
    local blame_result = parse.parse_blame_porcelain(result.stdout)
    blame_result.file = file
    callback(blame_result, nil)
  end)
end

return M
