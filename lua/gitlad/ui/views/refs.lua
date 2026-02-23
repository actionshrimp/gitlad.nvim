---@mod gitlad.ui.views.refs Git refs view
---@brief [[
--- Buffer showing all git references (branches, tags) with navigation and actions.
--- Opened via refs popup (yr keymap in status buffer).
---@brief ]]

local M = {}

local keymap = require("gitlad.utils.keymap")
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")
local git = require("gitlad.git")
local signs_util = require("gitlad.ui.utils.signs")

-- Namespace for sign column indicators
local ns_signs = vim.api.nvim_create_namespace("gitlad_refs_signs")

---@class RefLineInfo
---@field type "ref"|"cherry"|"section" Line type
---@field ref? RefInfo The ref (for type="ref")
---@field cherry? CherryCommit The cherry commit (for type="cherry")
---@field parent_ref? string Parent ref name for cherry commits
---@field section? string Section name (for type="section")
---@field positions? table Position data for highlighting

---@class RefsSignInfo
---@field expanded boolean Whether the ref is expanded

---@class RefsBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field base_ref string The ref being compared against
---@field local_branches RefInfo[] Local branches
---@field remote_branches table<string, RefInfo[]> Remote branches grouped by remote
---@field tags RefInfo[] Tags
---@field remote_urls table<string, string> Map of remote name to fetch URL
---@field line_map table<number, RefLineInfo> Map of line numbers to info
---@field section_lines table<number, string> Map of section header lines
---@field expanded_refs table<string, boolean> Map of ref name to expanded state
---@field cherry_cache table<string, CherryCommit[]> Map of ref name to cherry commits
---@field sign_lines table<number, RefsSignInfo> Map of line numbers to sign info
local RefsBuffer = {}
RefsBuffer.__index = RefsBuffer

-- Refs buffers by repo root (one per repo for multi-project support)
local refs_buffers = {}

--- Create or get the refs buffer for a repository
---@param repo_state RepoState
---@return RefsBuffer
local function get_or_create_buffer(repo_state)
  local key = repo_state.repo_root

  if refs_buffers[key] and vim.api.nvim_buf_is_valid(refs_buffers[key].bufnr) then
    return refs_buffers[key]
  end

  local self = setmetatable({}, RefsBuffer)
  self.repo_state = repo_state
  self.base_ref = "HEAD"
  self.local_branches = {}
  self.remote_branches = {}
  self.tags = {}
  self.remote_urls = {}
  self.line_map = {}
  self.section_lines = {}
  self.expanded_refs = {}
  self.cherry_cache = {}
  self.sign_lines = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options (include repo path for multi-project support)
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://refs[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-refs"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Clean up when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      refs_buffers[key] = nil
    end,
  })

  refs_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function RefsBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Navigation (evil-collection-magit style)
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_ref()
  end, "Next ref")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_ref()
  end, "Previous ref")
  keymap.set(bufnr, "n", "<M-n>", function()
    self:_goto_next_section()
  end, "Next section")
  keymap.set(bufnr, "n", "<M-p>", function()
    self:_goto_prev_section()
  end, "Previous section")

  -- Expand/collapse cherry commits
  keymap.set(bufnr, "n", "<CR>", function()
    self:_toggle_expand()
  end, "Toggle cherry commits")
  keymap.set(bufnr, "n", "<Tab>", function()
    self:_toggle_expand()
  end, "Toggle cherry commits")

  -- Delete ref
  keymap.set(bufnr, "n", "x", function()
    self:_delete_ref()
  end, "Delete ref")
  keymap.set(bufnr, "v", "x", function()
    self:_delete_refs_visual()
  end, "Delete selected refs")

  -- Yank ref name
  keymap.set(bufnr, "n", "y", function()
    self:_yank_ref()
  end, "Yank ref name")

  -- Refresh
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh refs")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close refs")

  -- Help
  keymap.set(bufnr, "n", "?", function()
    self:_show_help()
  end, "Show help")

  -- Cherry-pick popup (for cherry commits)
  keymap.set(bufnr, "n", "A", function()
    local cherrypick_popup = require("gitlad.popups.cherrypick")
    local cherry = self:_get_current_cherry()
    local context = cherry and { commit = cherry.hash } or nil
    cherrypick_popup.open(self.repo_state, context)
  end, "Cherry-pick popup")

  -- Branch popup (with ref context for checkout)
  keymap.set(bufnr, "n", "b", function()
    local branch_popup = require("gitlad.popups.branch")
    local ref = self:_get_current_ref()
    local context = ref and { ref = ref.name, ref_type = ref.type } or nil
    branch_popup.open(self.repo_state, context)
  end, "Branch popup")

  -- Diff popup (with ref or cherry context)
  keymap.set(bufnr, "n", "d", function()
    local diff_popup = require("gitlad.popups.diff")
    local context = {}

    -- Check for cherry commit first (individual commits under expanded refs)
    local cherry = self:_get_current_cherry()
    if cherry then
      -- Convert CherryCommit to GitCommitInfo-like structure for diff popup
      context.commit = { hash = cherry.hash, subject = cherry.subject }
    else
      -- Check for ref
      local ref = self:_get_current_ref()
      if ref then
        context.ref = ref.name
        context.base_ref = self.base_ref
        context.ref_upstream = ref.upstream
        -- Pass the current (HEAD) branch's upstream for the U action
        local status = self.repo_state.status
        context.current_upstream = status and status.upstream or nil
      end
    end

    diff_popup.open(self.repo_state, context)
  end, "Diff popup")

  -- Reset popup
  keymap.set(bufnr, "n", "X", function()
    local reset_popup = require("gitlad.popups.reset")
    local ref = self:_get_current_ref()
    local context = ref and { commit = ref.hash } or nil
    reset_popup.open(self.repo_state, context)
  end, "Reset popup")

  -- Rebase popup
  keymap.set(bufnr, "n", "r", function()
    local rebase_popup = require("gitlad.popups.rebase")
    -- Check for cherry commit first (individual commits under expanded refs)
    local cherry = self:_get_current_cherry()
    if cherry then
      rebase_popup.open(self.repo_state, { commit = cherry.hash })
      return
    end
    -- Fall back to ref hash
    local ref = self:_get_current_ref()
    local context = ref and { commit = ref.hash } or nil
    rebase_popup.open(self.repo_state, context)
  end, "Rebase popup")

  -- Fetch popup
  keymap.set(bufnr, "n", "f", function()
    local fetch_popup = require("gitlad.popups.fetch")
    fetch_popup.open(self.repo_state)
  end, "Fetch popup")

  -- Commit popup (passes commit at point for instant fixup/squash)
  keymap.set(bufnr, "n", "c", function()
    local commit_popup = require("gitlad.popups.commit")
    -- Check for cherry commit first (individual commits under expanded refs)
    local cherry = self:_get_current_cherry()
    if cherry then
      commit_popup.open(self.repo_state, { commit = cherry.hash })
      return
    end
    -- Fall back to ref hash
    local ref = self:_get_current_ref()
    local context = ref and { commit = ref.hash } or nil
    commit_popup.open(self.repo_state, context)
  end, "Commit popup")
end

--- Get current ref under cursor
---@return RefInfo|nil
function RefsBuffer:_get_current_ref()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local info = self.line_map[line]
  if info and info.type == "ref" then
    return info.ref
  end
  return nil
end

--- Get current cherry commit under cursor
---@return CherryCommit|nil
function RefsBuffer:_get_current_cherry()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local info = self.line_map[line]
  if info and info.type == "cherry" then
    return info.cherry
  end
  return nil
end

--- Get refs in visual selection
---@return RefInfo[]
function RefsBuffer:_get_selected_refs()
  local mode = vim.fn.mode()
  if mode:match("[vV]") then
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "nx", false)
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    local refs = {}
    for line = start_line, end_line do
      local info = self.line_map[line]
      if info and info.type == "ref" then
        table.insert(refs, info.ref)
      end
    end
    return refs
  else
    local ref = self:_get_current_ref()
    if ref then
      return { ref }
    end
  end
  return {}
end

--- Navigate to next ref
function RefsBuffer:_goto_next_ref()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line + 1, vim.api.nvim_buf_line_count(self.bufnr) do
    local info = self.line_map[line]
    if info and info.type == "ref" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous ref
function RefsBuffer:_goto_prev_ref()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    local info = self.line_map[line]
    if info and info.type == "ref" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to next section
function RefsBuffer:_goto_next_section()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  local section_list = vim.tbl_keys(self.section_lines)
  table.sort(section_list)

  for _, line in ipairs(section_list) do
    if line > current_line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous section
function RefsBuffer:_goto_prev_section()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  local section_list = vim.tbl_keys(self.section_lines)
  table.sort(section_list, function(a, b)
    return a > b
  end)

  for _, line in ipairs(section_list) do
    if line < current_line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Toggle expand/collapse of current ref's cherry commits
function RefsBuffer:_toggle_expand()
  local ref = self:_get_current_ref()
  if not ref then
    return
  end

  local ref_name = ref.name
  local is_expanded = self.expanded_refs[ref_name]

  if is_expanded then
    -- Collapse
    self.expanded_refs[ref_name] = nil
    self:render()
  else
    -- Check if we have cached cherry commits
    if self.cherry_cache[ref_name] then
      self.expanded_refs[ref_name] = true
      self:render()
    else
      -- Fetch cherry commits
      git.cherry(
        ref_name,
        self.base_ref,
        { cwd = self.repo_state.repo_root },
        function(commits, err)
          vim.schedule(function()
            if err then
              vim.notify("[gitlad] Failed to get cherry commits: " .. err, vim.log.levels.ERROR)
              return
            end
            self.cherry_cache[ref_name] = commits or {}
            self.expanded_refs[ref_name] = true
            self:render()
          end)
        end
      )
    end
  end
end

--- Yank ref name to clipboard
function RefsBuffer:_yank_ref()
  local ref = self:_get_current_ref()
  if not ref then
    local cherry = self:_get_current_cherry()
    if cherry then
      vim.fn.setreg("+", cherry.hash)
      vim.fn.setreg('"', cherry.hash)
      vim.notify("[gitlad] Yanked: " .. cherry.hash, vim.log.levels.INFO)
    end
    return
  end

  vim.fn.setreg("+", ref.name)
  vim.fn.setreg('"', ref.name)
  vim.notify("[gitlad] Yanked: " .. ref.name, vim.log.levels.INFO)
end

--- Show help popup with refs-relevant keybindings
function RefsBuffer:_show_help()
  local HelpView = require("gitlad.popups.help").HelpView
  local repo_state = self.repo_state

  local sections = {
    {
      name = "Transient commands",
      columns = 3,
      items = {
        {
          key = "b",
          desc = "Branch",
          action = function()
            require("gitlad.popups.branch").open(repo_state)
          end,
        },
        {
          key = "c",
          desc = "Commit",
          action = function()
            require("gitlad.popups.commit").open(repo_state)
          end,
        },
        {
          key = "d",
          desc = "Diff",
          action = function()
            require("gitlad.popups.diff").open(repo_state, {})
          end,
        },
        {
          key = "f",
          desc = "Fetch",
          action = function()
            require("gitlad.popups.fetch").open(repo_state)
          end,
        },
        {
          key = "r",
          desc = "Rebase",
          action = function()
            require("gitlad.popups.rebase").open(repo_state)
          end,
        },
        {
          key = "A",
          desc = "Cherry-pick",
          action = function()
            require("gitlad.popups.cherrypick").open(repo_state)
          end,
        },
        {
          key = "X",
          desc = "Reset",
          action = function()
            require("gitlad.popups.reset").open(repo_state)
          end,
        },
      },
    },
    {
      name = "Actions",
      columns = 3,
      items = {
        { key = "x", desc = "Delete ref" },
        { key = "y", desc = "Yank ref name" },
        { key = "<Tab>", desc = "Toggle expand" },
        { key = "<CR>", desc = "Toggle expand" },
      },
    },
    {
      name = "Navigation",
      columns = 3,
      items = {
        { key = "gj", desc = "Next ref" },
        { key = "gk", desc = "Previous ref" },
        { key = "<M-n>", desc = "Next section" },
        { key = "<M-p>", desc = "Previous section" },
      },
    },
    {
      name = "Essential commands",
      columns = 2,
      items = {
        {
          key = "gr",
          desc = "Refresh",
          action = function()
            self:refresh()
          end,
        },
        { key = "q", desc = "Close buffer" },
        { key = "?", desc = "This help" },
      },
    },
  }

  local help_view = HelpView.new(sections)
  help_view:show()
end

--- Delete a single ref
function RefsBuffer:_delete_ref()
  local ref = self:_get_current_ref()
  if not ref then
    return
  end

  self:_delete_refs({ ref })
end

--- Delete refs from visual selection
function RefsBuffer:_delete_refs_visual()
  local refs = self:_get_selected_refs()
  if #refs == 0 then
    return
  end

  self:_delete_refs(refs)
end

--- Smart delete a local branch (merged=no prompt, unmerged=prompt+force)
---@param ref RefInfo The local branch ref
---@param on_complete fun(success: boolean, err: string|nil) Callback when done
function RefsBuffer:_smart_delete_local_branch(ref, on_complete)
  local cwd = self.repo_state.repo_root

  -- First try non-force delete (works for merged branches)
  git.delete_branch(ref.name, false, { cwd = cwd }, function(success, err)
    vim.schedule(function()
      if success then
        -- Branch was merged, deleted successfully without prompt
        on_complete(true, nil)
        return
      end

      -- Check if it's an "unmerged" error
      if err and err:match("not fully merged") then
        -- Prompt user to confirm force delete
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Branch '" .. ref.name .. "' is not fully merged. Force delete?",
        }, function(choice)
          if choice ~= "Yes" then
            on_complete(false, "cancelled")
            return
          end

          -- Retry with force
          git.delete_branch(ref.name, true, { cwd = cwd }, function(force_success, force_err)
            vim.schedule(function()
              on_complete(force_success, force_err)
            end)
          end)
        end)
      else
        -- Some other error
        on_complete(false, err)
      end
    end)
  end)
end

--- Build a confirmation prompt for deleting refs
---@param refs RefInfo[]
---@return string
local function build_delete_prompt(refs)
  if #refs == 1 then
    local ref = refs[1]
    local type_label = ref.type == "local" and "branch"
      or ref.type == "remote" and "remote branch"
      or "tag"
    return string.format("Delete %s '%s'?", type_label, ref.name)
  end
  return string.format("Delete %d refs?", #refs)
end

--- Execute deletion of confirmed refs (no further confirmation except force-delete for unmerged)
---@param refs RefInfo[]
function RefsBuffer:_execute_delete_refs(refs)
  local local_refs = {}
  local non_local_refs = {}

  for _, ref in ipairs(refs) do
    if ref.type == "local" then
      table.insert(local_refs, ref)
    else
      table.insert(non_local_refs, ref)
    end
  end

  -- Track completion across all refs
  local total = #refs
  local completed = 0
  local errors = {}

  local function check_all_complete()
    if completed == total then
      self:_handle_delete_complete(total, errors)
    end
  end

  -- Handle local branches with smart delete (force prompt only for unmerged)
  for _, ref in ipairs(local_refs) do
    self:_smart_delete_local_branch(ref, function(success, err)
      completed = completed + 1
      if not success and err ~= "cancelled" then
        table.insert(errors, ref.name .. ": " .. (err or "unknown error"))
      end
      check_all_complete()
    end)
  end

  -- Handle non-local refs (remotes, tags)
  for _, ref in ipairs(non_local_refs) do
    if ref.type == "remote" then
      local remote, branch = ref.name:match("^([^/]+)/(.+)$")
      if remote and branch then
        git.delete_remote_branch(
          remote,
          branch,
          { cwd = self.repo_state.repo_root },
          function(success, err)
            vim.schedule(function()
              completed = completed + 1
              if not success then
                table.insert(errors, ref.name .. ": " .. (err or "unknown error"))
              end
              check_all_complete()
            end)
          end
        )
      else
        completed = completed + 1
        table.insert(errors, ref.name .. ": invalid remote branch format")
        check_all_complete()
      end
    elseif ref.type == "tag" then
      git.delete_tag(ref.name, { cwd = self.repo_state.repo_root }, function(success, err)
        vim.schedule(function()
          completed = completed + 1
          if not success then
            table.insert(errors, ref.name .. ": " .. (err or "unknown error"))
          end
          check_all_complete()
        end)
      end)
    end
  end
end

--- Delete refs with upfront confirmation
---@param refs RefInfo[]
function RefsBuffer:_delete_refs(refs)
  if #refs == 0 then
    return
  end

  local prompt = build_delete_prompt(refs)

  vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
    if choice ~= "Yes" then
      return
    end
    self:_execute_delete_refs(refs)
  end)
end

--- Handle completion of delete operations
---@param total number Total refs attempted
---@param errors string[] Error messages
function RefsBuffer:_handle_delete_complete(total, errors)
  if #errors > 0 then
    vim.notify(
      "[gitlad] Deleted "
        .. (total - #errors)
        .. "/"
        .. total
        .. " refs. Errors:\n"
        .. table.concat(errors, "\n"),
      vim.log.levels.WARN
    )
  else
    vim.notify("[gitlad] Deleted " .. total .. " ref(s)", vim.log.levels.INFO)
  end
  self:refresh()
end

--- Refresh refs data
function RefsBuffer:refresh()
  vim.notify("[gitlad] Refreshing refs...", vim.log.levels.INFO)

  local cwd = self.repo_state.repo_root
  local pending = 2 -- refs + remotes
  local refs_result = nil
  local remotes_result = nil

  local function try_render()
    pending = pending - 1
    if pending > 0 then
      return
    end

    -- Process refs
    if refs_result then
      self.local_branches = {}
      self.remote_branches = {}
      self.tags = {}

      for _, ref in ipairs(refs_result) do
        if ref.type == "local" then
          table.insert(self.local_branches, ref)
        elseif ref.type == "remote" then
          local remote = ref.remote or "unknown"
          if not self.remote_branches[remote] then
            self.remote_branches[remote] = {}
          end
          table.insert(self.remote_branches[remote], ref)
        elseif ref.type == "tag" then
          table.insert(self.tags, ref)
        end
      end
    end

    -- Process remotes
    self.remote_urls = {}
    if remotes_result then
      for _, remote in ipairs(remotes_result) do
        self.remote_urls[remote.name] = remote.fetch_url
      end
    end

    -- Clear expansion state and cherry cache on refresh
    self.expanded_refs = {}
    self.cherry_cache = {}

    -- Render immediately so user sees content
    self:render()

    -- Pre-fetch cherry data for local branches (fast operation)
    self:_prefetch_local_cherries()
  end

  git.refs({ cwd = cwd }, function(refs, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get refs: " .. err, vim.log.levels.ERROR)
      else
        refs_result = refs or {}
      end
      try_render()
    end)
  end)

  git.remotes({ cwd = cwd }, function(remotes, err)
    vim.schedule(function()
      if not err then
        remotes_result = remotes or {}
      end
      try_render()
    end)
  end)
end

--- Pre-fetch cherry commits for all local branches
function RefsBuffer:_prefetch_local_cherries()
  if #self.local_branches == 0 then
    return
  end

  local pending = #self.local_branches
  local cwd = self.repo_state.repo_root

  for _, ref in ipairs(self.local_branches) do
    git.cherry(ref.name, self.base_ref, { cwd = cwd }, function(commits, err)
      vim.schedule(function()
        pending = pending - 1

        if not err then
          self.cherry_cache[ref.name] = commits or {}
        end

        -- Re-render once all cherry data is fetched
        if pending == 0 then
          self:render()
        end
      end)
    end)
  end
end

-- Maximum column widths before truncation
local MAX_NAME_WIDTH = 30
local MAX_UPSTREAM_WIDTH = 30

--- Get the display name for a ref (strips remote prefix for remote branches)
---@param ref RefInfo
---@return string
local function ref_display_name(ref)
  if ref.type == "remote" and ref.remote then
    return ref.name:gsub("^" .. vim.pesc(ref.remote) .. "/", "")
  end
  return ref.name
end

--- Truncate a string with ellipsis if it exceeds max width
---@param str string
---@param max_width number
---@return string
local function truncate(str, max_width)
  if #str <= max_width then
    return str
  end
  return str:sub(1, max_width - 3) .. "..."
end

--- Compute column widths from all refs being rendered
---@param local_branches RefInfo[]
---@param remote_branches table<string, RefInfo[]>
---@param tags RefInfo[]
---@return number name_width, number upstream_width
local function compute_column_widths(local_branches, remote_branches, tags)
  local max_name = 0
  local max_upstream = 0

  -- Scan all refs for max widths
  for _, ref in ipairs(local_branches) do
    max_name = math.max(max_name, #ref_display_name(ref))
    if ref.upstream then
      max_upstream = math.max(max_upstream, #ref.upstream)
    end
  end

  for _, remote_refs in pairs(remote_branches) do
    for _, ref in ipairs(remote_refs) do
      max_name = math.max(max_name, #ref_display_name(ref))
    end
  end

  for _, ref in ipairs(tags) do
    max_name = math.max(max_name, #ref_display_name(ref))
  end

  -- Cap at maximums and ensure minimum
  local name_width = math.max(math.min(max_name, MAX_NAME_WIDTH), 4)
  local upstream_width = math.max(math.min(max_upstream, MAX_UPSTREAM_WIDTH), 0)

  return name_width, upstream_width
end

--- Render the refs buffer
function RefsBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local lines = {}
  self.line_map = {}
  self.section_lines = {}
  self.sign_lines = {}

  -- Compute dynamic column widths from data
  local name_width, upstream_width =
    compute_column_widths(self.local_branches, self.remote_branches, self.tags)

  -- Header
  table.insert(lines, "References (at " .. self.base_ref .. ")")
  table.insert(lines, "")

  -- Local branches section
  if #self.local_branches > 0 then
    table.insert(lines, "Branches (" .. #self.local_branches .. ")")
    self.section_lines[#lines] = "local"
    self.line_map[#lines] = { type = "section", section = "local" }

    for _, ref in ipairs(self.local_branches) do
      self:_render_ref(lines, ref, nil, name_width, upstream_width)
    end
    table.insert(lines, "")
  end

  -- Remote branches sections (grouped by remote)
  local remotes = vim.tbl_keys(self.remote_branches)
  table.sort(remotes)

  if #remotes > 0 then
    for _, remote in ipairs(remotes) do
      local remote_refs = self.remote_branches[remote]
      local url = self.remote_urls[remote]
      local header
      if url then
        header = "Remote " .. remote .. " (" .. url .. ") (" .. #remote_refs .. ")"
      else
        header = "Remote " .. remote .. " (" .. #remote_refs .. ")"
      end
      table.insert(lines, header)
      self.section_lines[#lines] = "remote:" .. remote
      self.line_map[#lines] = { type = "section", section = "remote:" .. remote }

      for _, ref in ipairs(remote_refs) do
        self:_render_ref(lines, ref, nil, name_width, upstream_width)
      end
      table.insert(lines, "")
    end
  end

  -- Tags section
  if #self.tags > 0 then
    table.insert(lines, "Tags (" .. #self.tags .. ")")
    self.section_lines[#lines] = "tags"
    self.line_map[#lines] = { type = "section", section = "tags" }

    for _, ref in ipairs(self.tags) do
      self:_render_ref(lines, ref, nil, name_width, upstream_width)
    end
    table.insert(lines, "")
  end

  -- Help line
  table.insert(lines, "")
  table.insert(lines, "Press ? for help")

  -- Update buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply highlights
  self:_apply_highlights()

  -- Place signs
  signs_util.place_expand_signs(self.bufnr, self.sign_lines, ns_signs)

  vim.bo[self.bufnr].modifiable = false
end

--- Render a single ref
---@param lines string[] Buffer lines to append to
---@param ref RefInfo The ref to render
---@param base_indent? number Base indentation level (default 0)
---@param name_col_width? number Column width for name
---@param upstream_col_width? number Column width for upstream
function RefsBuffer:_render_ref(lines, ref, base_indent, name_col_width, upstream_col_width)
  base_indent = base_indent or 0
  name_col_width = name_col_width or 16
  upstream_col_width = upstream_col_width or 0
  local indent = string.rep("  ", base_indent)

  -- Build ref line: [@] name [upstream] subject
  local parts = {}

  -- HEAD marker
  if ref.is_head then
    table.insert(parts, "@")
  else
    table.insert(parts, " ")
  end

  -- Name (truncated if needed, then padded to column width)
  local name = ref_display_name(ref)
  local display_name = truncate(name, name_col_width)
  local padded_name = display_name .. string.rep(" ", math.max(0, name_col_width - #display_name))
  table.insert(parts, padded_name)

  -- Upstream tracking ref (only for local branches, no right-padding - flows into subject)
  local display_upstream
  if ref.type == "local" and upstream_col_width > 0 then
    local upstream = ref.upstream or ""
    display_upstream = truncate(upstream, upstream_col_width)
    if #display_upstream > 0 then
      table.insert(parts, display_upstream)
    end
  end

  -- Subject
  local subject = ref.subject or ""
  if #subject > 50 then
    subject = subject:sub(1, 47) .. "..."
  end
  table.insert(parts, subject)

  local line = indent .. table.concat(parts, " ")
  table.insert(lines, line)

  -- Track line info with positions for highlighting
  local line_num = #lines

  -- Calculate positions for highlighting
  local positions = {}
  local marker_start = #indent
  positions.marker = { start = marker_start, finish = marker_start + 1 }

  -- Name position (after marker + space)
  local name_start = marker_start + 2
  positions.name = { start = name_start, finish = name_start + #display_name }

  -- Upstream position (for local branches)
  if ref.type == "local" and display_upstream and #display_upstream > 0 then
    local upstream_start = name_start + name_col_width + 1
    positions.upstream = { start = upstream_start, finish = upstream_start + #display_upstream }
  end

  -- Subject position
  local subject_start = #line - #subject
  if #subject > 0 then
    positions.subject = { start = subject_start, finish = subject_start + #subject }
  end

  self.line_map[line_num] = { type = "ref", ref = ref, positions = positions }

  -- Track sign for expandable refs (only show if expanded or has cached cherries)
  local is_expanded = self.expanded_refs[ref.name]
  local has_cherry = self.cherry_cache[ref.name] and #self.cherry_cache[ref.name] > 0
  if is_expanded or has_cherry then
    self.sign_lines[line_num] = { expanded = is_expanded or false }
  end

  -- Render cherry commits if expanded (no indentation per TODO requirement)
  if is_expanded and self.cherry_cache[ref.name] then
    for _, cherry in ipairs(self.cherry_cache[ref.name]) do
      local cherry_prefix = cherry.equivalent and "-" or "+"
      local cherry_line = cherry_prefix .. " " .. cherry.hash:sub(1, 7) .. " " .. cherry.subject
      table.insert(lines, cherry_line)
      self.line_map[#lines] = { type = "cherry", cherry = cherry, parent_ref = ref.name }
    end
  end
end

--- Apply syntax highlighting
function RefsBuffer:_apply_highlights()
  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  -- Highlight header
  hl.set_line(self.bufnr, ns, 0, "GitladSectionHeader")

  -- Highlight section headers and refs
  for line_num, info in pairs(self.line_map) do
    if info.type == "section" then
      -- Check for remote section with inline highlights
      local section = info.section or ""
      if section:match("^remote:") then
        local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line_num - 1, line_num, false)[1]
          or ""
        -- "Remote origin (url) (N)" - highlight parts inline
        local remote_name = section:match("^remote:(.+)$")
        if remote_name then
          -- Highlight "Remote " in section header style
          hl.set(self.bufnr, ns, line_num - 1, 0, 7, "GitladSectionHeader")
          -- Highlight remote name in green
          local name_start = 7
          local name_end = name_start + #remote_name
          hl.set(self.bufnr, ns, line_num - 1, name_start, name_end, "GitladRefRemote")
          -- Highlight URL if present
          local url = self.remote_urls[remote_name]
          if url then
            local url_start = line_text:find(url, 1, true)
            if url_start then
              hl.set(
                self.bufnr,
                ns,
                line_num - 1,
                url_start - 1,
                url_start - 1 + #url,
                "GitladRemote"
              )
            end
          end
          -- Highlight the count at the end
          local count_start, count_end = line_text:find("%(%d+%)$")
          if count_start then
            hl.set(self.bufnr, ns, line_num - 1, count_start - 1, count_end, "GitladSectionHeader")
          end
        end
      else
        hl.set_line(self.bufnr, ns, line_num - 1, "GitladSectionHeader")
      end
    elseif info.type == "ref" then
      local ref = info.ref
      local pos = info.positions

      if pos then
        -- Highlight HEAD marker
        if ref.is_head then
          hl.set(self.bufnr, ns, line_num - 1, pos.marker.start, pos.marker.finish, "GitladRefHead")
        end

        -- Highlight branch/tag name
        local name_hl
        if ref.type == "local" then
          name_hl = "GitladRefLocal"
        elseif ref.type == "remote" then
          name_hl = "GitladRefRemote"
        elseif ref.type == "tag" then
          name_hl = "GitladRefTag"
        end
        if name_hl then
          hl.set(self.bufnr, ns, line_num - 1, pos.name.start, pos.name.finish, name_hl)
        end

        -- Highlight upstream tracking ref
        if pos.upstream then
          hl.set(
            self.bufnr,
            ns,
            line_num - 1,
            pos.upstream.start,
            pos.upstream.finish,
            "GitladRefRemote"
          )
        end

        -- Highlight subject
        if pos.subject then
          hl.set(
            self.bufnr,
            ns,
            line_num - 1,
            pos.subject.start,
            pos.subject.finish,
            "GitladCommitMsg"
          )
        end
      end
    elseif info.type == "cherry" then
      local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line_num - 1, line_num, false)[1]
        or ""
      local prefix_pos = line_text:find("[%+%-]")
      if prefix_pos then
        local cherry = info.cherry
        local hl_group = cherry.equivalent and "DiffDelete" or "DiffAdd"
        hl.set(self.bufnr, ns, line_num - 1, prefix_pos - 1, prefix_pos, hl_group)
      end
      -- Highlight hash
      local hash_start = line_text:find("%x%x%x%x%x%x%x")
      if hash_start then
        hl.set(self.bufnr, ns, line_num - 1, hash_start - 1, hash_start + 6, "GitladCommitHash")
      end
    end
  end
end

--- Open the refs buffer in a window
---@param repo_state RepoState
---@param base_ref string The ref to compare against
function RefsBuffer:open_with_base_ref(repo_state, base_ref)
  self.repo_state = repo_state
  self.base_ref = base_ref
  self.expanded_refs = {}
  self.cherry_cache = {}

  -- Check if already open
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_set_current_win(self.winnr)
    self:refresh()
    return
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(self.bufnr)
  self.winnr = vim.api.nvim_get_current_win()

  -- Set window-local options
  utils.setup_view_window_options(self.winnr)

  -- Fetch and render
  self:refresh()
end

--- Close the refs buffer
function RefsBuffer:close()
  utils.close_view_buffer(self)
end

--- Open refs view (module-level entry point)
---@param repo_state RepoState
---@param base_ref string The ref to compare against (e.g., "HEAD", "main")
function M.open(repo_state, base_ref)
  local buf = get_or_create_buffer(repo_state)
  buf:open_with_base_ref(repo_state, base_ref)
end

--- Close refs view for a repo
---@param repo_state? RepoState
function M.close(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    if refs_buffers[key] then
      refs_buffers[key]:close()
    end
  else
    -- Close all if no repo specified
    for _, buf in pairs(refs_buffers) do
      buf:close()
    end
  end
end

--- Get the refs buffer for a repo if it exists
---@param repo_state? RepoState
---@return RefsBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    local buf = refs_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end
  -- If no repo_state, return first valid buffer (for backwards compat/testing)
  for _, buf in pairs(refs_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

--- Clear all refs buffers (for testing)
function M.clear_all()
  for _, buf in pairs(refs_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  refs_buffers = {}
end

return M
