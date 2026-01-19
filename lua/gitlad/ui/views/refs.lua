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
---@field line_map table<number, RefLineInfo> Map of line numbers to info
---@field section_lines table<number, string> Map of section header lines
---@field expanded_refs table<string, boolean> Map of ref name to expanded state
---@field cherry_cache table<string, CherryCommit[]> Map of ref name to cherry commits
---@field sign_lines table<number, RefsSignInfo> Map of line numbers to sign info
local RefsBuffer = {}
RefsBuffer.__index = RefsBuffer

-- Singleton buffer (one refs view at a time)
local refs_buffer = nil

--- Create or get the refs buffer
---@param repo_state RepoState
---@return RefsBuffer
local function get_or_create_buffer(repo_state)
  if refs_buffer and vim.api.nvim_buf_is_valid(refs_buffer.bufnr) then
    refs_buffer.repo_state = repo_state
    return refs_buffer
  end

  local self = setmetatable({}, RefsBuffer)
  self.repo_state = repo_state
  self.base_ref = "HEAD"
  self.local_branches = {}
  self.remote_branches = {}
  self.tags = {}
  self.line_map = {}
  self.section_lines = {}
  self.expanded_refs = {}
  self.cherry_cache = {}
  self.sign_lines = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://refs")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-refs"

  -- Set up keymaps
  self:_setup_keymaps()

  refs_buffer = self
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
    local context = ref and { ref = ref.name } or nil
    branch_popup.open(self.repo_state, context)
  end, "Branch popup")

  -- Diff popup (with ref context)
  keymap.set(bufnr, "n", "d", function()
    local diff_popup = require("gitlad.popups.diff")
    local ref = self:_get_current_ref()
    local context = ref and { ref = ref.name, base_ref = self.base_ref } or {}
    diff_popup.open(self.repo_state, context)
  end, "Diff popup")

  -- Reset popup
  keymap.set(bufnr, "n", "X", function()
    local reset_popup = require("gitlad.popups.reset")
    local ref = self:_get_current_ref()
    local context = ref and { commit = ref.hash } or nil
    reset_popup.open(self.repo_state, context)
  end, "Reset popup")
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
    vim.cmd("normal! ")
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

      -- DEBUG: Log the error to see what we're getting
      vim.notify("[DEBUG] delete_branch error: " .. vim.inspect(err), vim.log.levels.INFO)

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

--- Delete refs (smart: merged branches delete without prompt)
---@param refs RefInfo[]
function RefsBuffer:_delete_refs(refs)
  if #refs == 0 then
    return
  end

  -- For non-local refs (remotes, tags), we still prompt
  local non_local_refs = {}
  local local_refs = {}

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

  -- Handle local branches with smart delete (no prompt for merged)
  for _, ref in ipairs(local_refs) do
    self:_smart_delete_local_branch(ref, function(success, err)
      completed = completed + 1
      if not success and err ~= "cancelled" then
        table.insert(errors, ref.name .. ": " .. (err or "unknown error"))
      end
      check_all_complete()
    end)
  end

  -- For non-local refs, prompt once if any exist
  if #non_local_refs > 0 then
    local msg
    if #non_local_refs == 1 then
      msg = string.format("Delete %s '%s'?", non_local_refs[1].type, non_local_refs[1].name)
    else
      msg = string.format("Delete %d remote/tag refs?", #non_local_refs)
    end

    vim.ui.select({ "Yes", "No" }, { prompt = msg }, function(choice)
      if choice ~= "Yes" then
        -- Mark all as completed (cancelled)
        completed = completed + #non_local_refs
        check_all_complete()
        return
      end

      for _, ref in ipairs(non_local_refs) do
        if ref.type == "remote" then
          -- Parse remote/branch from name (e.g., "origin/feature")
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
    end)
  end
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

  git.refs({ cwd = self.repo_state.repo_root }, function(refs, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] Failed to get refs: " .. err, vim.log.levels.ERROR)
        return
      end

      -- Organize refs by type
      self.local_branches = {}
      self.remote_branches = {}
      self.tags = {}

      for _, ref in ipairs(refs or {}) do
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

      -- Clear expansion state and cherry cache on refresh
      self.expanded_refs = {}
      self.cherry_cache = {}

      -- Render immediately so user sees content
      self:render()

      -- Pre-fetch cherry data for local branches (fast operation)
      self:_prefetch_local_cherries()
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

--- Render the refs buffer
function RefsBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local lines = {}
  self.line_map = {}
  self.section_lines = {}
  self.sign_lines = {}

  -- Header
  table.insert(lines, "References (at " .. self.base_ref .. ")")
  table.insert(lines, "")

  -- Local branches section
  if #self.local_branches > 0 then
    table.insert(lines, "Local (" .. #self.local_branches .. ")")
    self.section_lines[#lines] = "local"
    self.line_map[#lines] = { type = "section", section = "local" }

    for _, ref in ipairs(self.local_branches) do
      self:_render_ref(lines, ref)
    end
    table.insert(lines, "")
  end

  -- Remote branches sections (grouped by remote)
  local remotes = vim.tbl_keys(self.remote_branches)
  table.sort(remotes)

  if #remotes > 0 then
    for _, remote in ipairs(remotes) do
      local remote_refs = self.remote_branches[remote]
      table.insert(lines, remote .. " (" .. #remote_refs .. ")")
      self.section_lines[#lines] = "remote:" .. remote
      self.line_map[#lines] = { type = "section", section = "remote:" .. remote }

      for _, ref in ipairs(remote_refs) do
        self:_render_ref(lines, ref)
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
      self:_render_ref(lines, ref)
    end
    table.insert(lines, "")
  end

  -- Help line
  table.insert(lines, "")
  table.insert(lines, "Press TAB expand, x delete, y yank, gr refresh, q close")

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
function RefsBuffer:_render_ref(lines, ref, base_indent)
  base_indent = base_indent or 0
  local indent = string.rep("  ", base_indent)

  -- Build ref line: [*] [counts] name subject
  local parts = {}

  -- HEAD marker
  if ref.is_head then
    table.insert(parts, "*")
  else
    table.insert(parts, " ")
  end

  -- Name (padded)
  local name = ref.name
  if ref.type == "remote" and ref.remote then
    -- Show without remote prefix for cleaner display
    name = ref.name:gsub("^" .. ref.remote .. "/", "")
  end
  local name_width = 30
  local padded_name = name .. string.rep(" ", math.max(0, name_width - #name))
  table.insert(parts, padded_name)

  -- Subject
  local subject = ref.subject or ""
  if #subject > 50 then
    subject = subject:sub(1, 47) .. "..."
  end
  table.insert(parts, subject)

  local line = indent .. table.concat(parts, " ")
  table.insert(lines, line)

  -- Track line info
  local line_num = #lines
  self.line_map[line_num] = { type = "ref", ref = ref }

  -- Track sign for expandable refs (only show if expanded or has cached cherries)
  local is_expanded = self.expanded_refs[ref.name]
  local has_cherry = self.cherry_cache[ref.name] and #self.cherry_cache[ref.name] > 0
  if is_expanded or has_cherry then
    self.sign_lines[line_num] = { expanded = is_expanded or false }
  end

  -- Render cherry commits if expanded
  if is_expanded and self.cherry_cache[ref.name] then
    for _, cherry in ipairs(self.cherry_cache[ref.name]) do
      local cherry_prefix = cherry.equivalent and "-" or "+"
      local cherry_line = indent
        .. "    "
        .. cherry_prefix
        .. " "
        .. cherry.hash:sub(1, 7)
        .. " "
        .. cherry.subject
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
      hl.set_line(self.bufnr, ns, line_num - 1, "GitladSectionHeader")
    elseif info.type == "ref" then
      local ref = info.ref
      if ref.is_head then
        -- Highlight HEAD marker
        local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line_num - 1, line_num, false)[1]
          or ""
        local star_pos = line_text:find("%*")
        if star_pos then
          hl.set(self.bufnr, ns, line_num - 1, star_pos - 1, star_pos, "GitladCommitHash")
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
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = nil
    return
  end

  -- Go back to previous buffer or close window
  local prev_buf = vim.fn.bufnr("#")
  if prev_buf ~= -1 and vim.api.nvim_buf_is_valid(prev_buf) then
    vim.api.nvim_set_current_buf(prev_buf)
  else
    vim.cmd("quit")
  end
  self.winnr = nil
end

--- Open refs view (module-level entry point)
---@param repo_state RepoState
---@param base_ref string The ref to compare against (e.g., "HEAD", "main")
function M.open(repo_state, base_ref)
  local buf = get_or_create_buffer(repo_state)
  buf:open_with_base_ref(repo_state, base_ref)
end

--- Close refs view
function M.close()
  if refs_buffer then
    refs_buffer:close()
  end
end

--- Get current refs buffer (for testing)
---@return RefsBuffer|nil
function M.get_buffer()
  return refs_buffer
end

--- Clear the buffer singleton (for testing)
function M.clear()
  if refs_buffer then
    if vim.api.nvim_buf_is_valid(refs_buffer.bufnr) then
      vim.api.nvim_buf_delete(refs_buffer.bufnr, { force = true })
    end
    refs_buffer = nil
  end
end

return M
