---@mod gitlad.utils.prompt Input prompt utilities
---@brief [[
--- Utilities for prompting user input with completion.
--- Provides magit-style ref picker with graceful fallback:
---   1. snacks.nvim picker (best UX, if available)
---   2. mini.pick (if available)
---   3. vim.ui.input with completion (always works)
---
--- All options show suggestions (branches, tags, commits) but accept
--- arbitrary input - matching magit's completing-read with require-match='any'.
---@brief ]]

local M = {}

--- Check if snacks.nvim is available
---@return boolean
local function has_snacks()
  local ok = pcall(require, "snacks")
  return ok
end

--- Check if mini.pick is available
---@return boolean
local function has_mini_pick()
  local ok = pcall(require, "mini.pick")
  return ok
end

--- Get git refs for picker/completion suggestions.
--- Returns branches (local/remote), tags, and recent commit SHAs.
---@param cwd? string Working directory for git commands
---@return string[] refs
local function get_git_refs(cwd)
  local refs = {}

  -- Build command with optional cwd
  local git_prefix = cwd and string.format("git -C %s ", vim.fn.shellescape(cwd)) or "git "

  -- Get remote names to filter them out (for-each-ref returns bare remote names)
  local remotes_cmd = git_prefix .. "remote 2>/dev/null"
  local remotes_output = vim.fn.systemlist(remotes_cmd)
  local remote_set = {}
  if vim.v.shell_error == 0 then
    for _, remote in ipairs(remotes_output) do
      remote_set[remote] = true
    end
  end

  -- Get branches and tags via for-each-ref (fast, single call)
  local ref_cmd = git_prefix
    .. "for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>/dev/null"
  local ref_output = vim.fn.systemlist(ref_cmd)
  if vim.v.shell_error == 0 then
    for _, ref in ipairs(ref_output) do
      -- Filter out bare remote names (e.g., "origin" without a branch)
      if not remote_set[ref] then
        table.insert(refs, ref)
      end
    end
  end

  -- Add some recent commit SHAs for convenience
  local log_cmd = git_prefix .. "log --format='%h' -20 2>/dev/null"
  local log_output = vim.fn.systemlist(log_cmd)
  if vim.v.shell_error == 0 then
    vim.list_extend(refs, log_output)
  end

  -- Add common refs
  table.insert(refs, "HEAD")
  table.insert(refs, "HEAD~1")
  table.insert(refs, "HEAD~2")
  table.insert(refs, "HEAD~3")

  return refs
end

--- Prompt for ref using snacks.nvim picker.
--- Shows suggestions but accepts arbitrary input on Enter.
---@param opts { prompt: string, default?: string, cwd?: string }
---@param callback fun(ref: string|nil)
local function prompt_with_snacks(opts, callback)
  local Snacks = require("snacks")

  local refs = get_git_refs(opts.cwd)
  local items = vim.tbl_map(function(ref)
    return { text = ref }
  end, refs)

  -- Track if we've already called the callback (to avoid double-calling)
  local called = false
  local function finish(value)
    if called then
      return
    end
    called = true
    callback(value)
  end

  Snacks.picker({
    title = opts.prompt:gsub(": ?$", ""), -- Remove trailing colon/space
    items = items,
    format = "text",
    layout = {
      preset = "select",
    },
    actions = {
      -- Custom confirm that accepts typed text when no item matches
      confirm = function(picker)
        -- picker:current() gets the item under cursor
        local current = picker:current()
        if current then
          -- User selected an item from the list
          picker:close()
          finish(current.text)
        else
          -- No item under cursor - use the typed text as custom input
          local input_text = picker.input and picker.input:get() or ""
          picker:close()
          if input_text ~= "" then
            finish(input_text)
          else
            finish(nil)
          end
        end
      end,
      cancel = function(picker)
        picker:close()
        finish(nil)
      end,
    },
    win = {
      input = {
        keys = {
          ["<CR>"] = { "confirm", mode = { "n", "i" } },
          ["<Esc>"] = { "cancel", mode = { "n", "i" } },
        },
      },
    },
  })
end

--- Prompt for ref using mini.pick.
--- Shows suggestions but accepts arbitrary input on Enter.
---@param opts { prompt: string, default?: string, cwd?: string }
---@param callback fun(ref: string|nil)
local function prompt_with_mini_pick(opts, callback)
  local MiniPick = require("mini.pick")

  local refs = get_git_refs(opts.cwd)
  local chosen = nil

  MiniPick.start({
    source = {
      items = refs,
      name = opts.prompt:gsub(": ?$", ""),
      choose = function(item)
        chosen = item
        return nil -- Continue to close picker
      end,
    },
    mappings = {
      -- Custom Enter that accepts query when no match
      choose_or_input = {
        char = "<CR>",
        func = function()
          local match = MiniPick.get_picker_matches()
          if match and match.current then
            chosen = match.current
          else
            -- No match - use query as custom input
            local query = MiniPick.get_picker_query()
            if query then
              chosen = table.concat(query, "")
            end
          end
          return true -- Stop picker
        end,
      },
    },
  })

  -- MiniPick.start is synchronous, callback after it closes
  if chosen and chosen ~= "" then
    callback(chosen)
  else
    callback(nil)
  end
end

--- Completion function for git refs (vim.ui.input fallback).
--- Must be global for vim.ui.input completion to access it.
---@param arglead string Current argument being completed
---@param _cmdline string Full command line (unused)
---@param _cursorpos number Cursor position (unused)
---@return string[] completions
function _G.gitlad_complete_refs(arglead, _cmdline, _cursorpos)
  local refs = get_git_refs()

  -- Filter by arglead if provided
  if arglead and arglead ~= "" then
    local filtered = {}
    local pattern = "^" .. vim.pesc(arglead)
    for _, ref in ipairs(refs) do
      if ref:match(pattern) then
        table.insert(filtered, ref)
      end
    end
    return filtered
  end

  return refs
end

--- Prompt for ref using vim.ui.input with completion (fallback).
---@param opts { prompt: string, default?: string, cwd?: string }
---@param callback fun(ref: string|nil)
local function prompt_with_input(opts, callback)
  vim.ui.input({
    prompt = opts.prompt,
    default = opts.default or "",
    completion = "customlist,v:lua.gitlad_complete_refs",
  }, function(input)
    if input and input ~= "" then
      callback(input)
    else
      callback(nil)
    end
  end)
end

--- Prompt for a git ref with picker/completion.
--- Uses the best available picker with graceful fallback:
---   1. snacks.nvim (full picker UI, accepts custom input)
---   2. mini.pick (full picker UI, accepts custom input)
---   3. vim.ui.input (cmdline with Tab completion)
---@param opts { prompt: string, default?: string, cwd?: string }
---@param callback fun(ref: string|nil) Called with entered ref or nil if cancelled
function M.prompt_for_ref(opts, callback)
  if has_snacks() then
    prompt_with_snacks(opts, callback)
  elseif has_mini_pick() then
    prompt_with_mini_pick(opts, callback)
  else
    prompt_with_input(opts, callback)
  end
end

return M
