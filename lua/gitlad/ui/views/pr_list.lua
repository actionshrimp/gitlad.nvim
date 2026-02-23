---@mod gitlad.ui.views.pr_list PR list view
---@brief [[
--- Buffer showing pull request list from forge provider.
--- Opened via forge popup (N l in status buffer).
--- Shows a sectioned dashboard: My PRs, Review Requests, Recently Merged.
---@brief ]]

local M = {}

local pr_list_component = require("gitlad.ui.components.pr_list")
local keymap = require("gitlad.utils.keymap")
local utils = require("gitlad.utils")
local hl = require("gitlad.ui.hl")

---@class PRListSection
---@field key string Unique section identifier
---@field title string Display title
---@field prs ForgePullRequest[] PRs in this section

---@class PRSectionLineInfo
---@field type "section" Discriminator
---@field key string Section key

---@class PRListBuffer
---@field bufnr number Buffer number
---@field winnr number|nil Window number if open
---@field repo_state RepoState Repository state
---@field provider ForgeProvider Forge provider
---@field prs ForgePullRequest[] Current PRs (flat fallback)
---@field sections PRListSection[] Ordered sections
---@field collapsed_sections table<string, boolean> Collapsed state per section key
---@field section_lines table<number, PRSectionLineInfo> Map of line numbers to section header info
---@field viewer_login string|nil Authenticated user's login
---@field opts ForgeListPRsOpts List options
---@field line_map table<number, PRLineInfo> Map of line numbers to PR info
local PRListBuffer = {}
PRListBuffer.__index = PRListBuffer

-- PR list buffers by repo root (singleton per repo)
local pr_list_buffers = {}

--- Create or get the PR list buffer for a repository
---@param repo_state RepoState
---@param provider ForgeProvider
---@return PRListBuffer
local function get_or_create_buffer(repo_state, provider)
  local key = repo_state.repo_root

  if pr_list_buffers[key] and vim.api.nvim_buf_is_valid(pr_list_buffers[key].bufnr) then
    local buf = pr_list_buffers[key]
    buf.provider = provider
    return buf
  end

  local self = setmetatable({}, PRListBuffer)
  self.repo_state = repo_state
  self.provider = provider
  self.prs = {}
  self.sections = {}
  self.collapsed_sections = {}
  self.section_lines = {}
  self.viewer_login = nil
  self.opts = {}
  self.line_map = {}

  -- Create buffer
  self.bufnr = vim.api.nvim_create_buf(false, true)
  self.winnr = nil

  -- Set buffer options
  vim.api.nvim_buf_set_name(self.bufnr, "gitlad://pr-list[" .. key .. "]")
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "hide"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].filetype = "gitlad-pr-list"

  -- Set up keymaps
  self:_setup_keymaps()

  -- Clean up when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = self.bufnr,
    callback = function()
      pr_list_buffers[key] = nil
    end,
  })

  pr_list_buffers[key] = self
  return self
end

--- Set up buffer keymaps
function PRListBuffer:_setup_keymaps()
  local bufnr = self.bufnr

  -- Navigation
  keymap.set(bufnr, "n", "gj", function()
    self:_goto_next_pr()
  end, "Next PR")
  keymap.set(bufnr, "n", "gk", function()
    self:_goto_prev_pr()
  end, "Previous PR")

  -- Toggle section collapse
  keymap.set(bufnr, "n", "<Tab>", function()
    self:_toggle_section()
  end, "Toggle section")

  -- View PR detail
  keymap.set(bufnr, "n", "<CR>", function()
    local pr = self:_get_current_pr()
    if pr then
      local pr_detail_view = require("gitlad.ui.views.pr_detail")
      pr_detail_view.open(self.repo_state, self.provider, pr.number)
    end
  end, "View PR")

  -- Yank PR number
  keymap.set(bufnr, "n", "y", function()
    self:_yank_pr_number()
  end, "Yank PR number")

  -- Open in browser
  keymap.set(bufnr, "n", "o", function()
    local pr = self:_get_current_pr()
    if pr and pr.url ~= "" then
      vim.ui.open(pr.url)
    end
  end, "Open in browser")

  -- Refresh
  keymap.set(bufnr, "n", "gr", function()
    self:refresh()
  end, "Refresh PR list")

  -- Close
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close PR list")

  -- Help
  keymap.set(bufnr, "n", "?", function()
    self:_show_help()
  end, "Show help")
end

--- Show help popup with PR list keybindings
function PRListBuffer:_show_help()
  local HelpView = require("gitlad.popups.help").HelpView

  local sections = {
    {
      name = "Actions",
      columns = 3,
      items = {
        { key = "<CR>", desc = "View PR" },
        { key = "o", desc = "Open in browser" },
        { key = "y", desc = "Yank PR number" },
      },
    },
    {
      name = "Navigation",
      columns = 3,
      items = {
        { key = "gj", desc = "Next PR" },
        { key = "gk", desc = "Previous PR" },
        { key = "<Tab>", desc = "Toggle section" },
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

--- Get current PR under cursor
---@return ForgePullRequest|nil
function PRListBuffer:_get_current_pr()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local info = self.line_map[line]
  if info and info.type == "pr" then
    return info.pr
  end
  return nil
end

--- Navigate to next PR
function PRListBuffer:_goto_next_pr()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line + 1, vim.api.nvim_buf_line_count(self.bufnr) do
    local info = self.line_map[line]
    if info and info.type == "pr" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Navigate to previous PR
function PRListBuffer:_goto_prev_pr()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  for line = current_line - 1, 1, -1 do
    local info = self.line_map[line]
    if info and info.type == "pr" then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end
end

--- Toggle collapse/expand of section at cursor
function PRListBuffer:_toggle_section()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local section_info = self.section_lines[line]
  if section_info then
    self.collapsed_sections[section_info.key] = not self.collapsed_sections[section_info.key]
    self:render()
    -- Restore cursor to same line (it's still a section header)
    local max_lines = vim.api.nvim_buf_line_count(self.bufnr)
    if line > max_lines then
      line = max_lines
    end
    vim.api.nvim_win_set_cursor(0, { line, 0 })
  end
end

--- Yank PR number to clipboard
function PRListBuffer:_yank_pr_number()
  local pr = self:_get_current_pr()
  if not pr then
    return
  end

  local text = "#" .. pr.number
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify("[gitlad] Yanked: " .. text, vim.log.levels.INFO)
end

--- Refresh PR list from provider (sectioned dashboard with parallel queries)
function PRListBuffer:refresh()
  vim.notify("[gitlad] Refreshing PR list...", vim.log.levels.INFO)

  local forge = require("gitlad.forge")

  -- Try to get viewer login for sectioned view
  forge.get_viewer_login(self.provider, function(login, viewer_err)
    vim.schedule(function()
      if viewer_err or not login then
        -- Fallback to flat list
        self:_refresh_flat()
        return
      end

      self.viewer_login = login
      self:_refresh_sectioned()
    end)
  end)
end

--- Fallback: refresh with flat list_prs() (no sections)
function PRListBuffer:_refresh_flat()
  self.provider:list_prs(self.opts, function(prs, err)
    vim.schedule(function()
      if err then
        vim.notify("[gitlad] PR list failed: " .. err, vim.log.levels.ERROR)
        return
      end

      self.prs = prs or {}
      self.sections = {}
      self:render()
      vim.notify("[gitlad] PR list refreshed (" .. #self.prs .. " PRs)", vim.log.levels.INFO)
    end)
  end)
end

--- Refresh with sectioned search queries (3 parallel requests)
function PRListBuffer:_refresh_sectioned()
  local login = self.viewer_login
  local repo_slug = self.provider.owner .. "/" .. self.provider.repo
  local pending = 3

  -- Initialize sections with empty PR lists
  self.sections = {
    { key = "mine", title = "My Pull Requests", prs = {} },
    { key = "review", title = "Review Requests", prs = {} },
    { key = "merged", title = "Recently Merged", prs = {} },
  }

  local function on_section_done()
    pending = pending - 1
    if pending == 0 then
      -- Count total PRs
      local total = 0
      for _, section in ipairs(self.sections) do
        total = total + #section.prs
      end
      vim.notify("[gitlad] PR list refreshed (" .. total .. " PRs)", vim.log.levels.INFO)
    end
  end

  -- Section 1: My open PRs
  local my_query = "repo:" .. repo_slug .. " is:pr is:open author:" .. login
  self.provider:search_prs(my_query, 30, function(prs, err)
    vim.schedule(function()
      if not err and prs then
        self.sections[1].prs = prs
      end
      self:render()
      on_section_done()
    end)
  end)

  -- Section 2: Review requests
  local review_query = "repo:" .. repo_slug .. " is:pr is:open review-requested:" .. login
  self.provider:search_prs(review_query, 30, function(prs, err)
    vim.schedule(function()
      if not err and prs then
        self.sections[2].prs = prs
      end
      self:render()
      on_section_done()
    end)
  end)

  -- Section 3: Recently merged by me
  local merged_query = "repo:"
    .. repo_slug
    .. " is:pr is:merged author:"
    .. login
    .. " sort:updated-desc"
  self.provider:search_prs(merged_query, 10, function(prs, err)
    vim.schedule(function()
      if not err and prs then
        self.sections[3].prs = prs
      end
      self:render()
      on_section_done()
    end)
  end)
end

--- Update the winbar with PR list info
function PRListBuffer:_update_winbar()
  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  local total = 0
  if #self.sections > 0 then
    for _, section in ipairs(self.sections) do
      total = total + #section.prs
    end
  else
    total = #self.prs
  end

  local winbar = "%#GitladSectionHeader#Pull Requests"
  winbar = winbar .. " (" .. self.provider.owner .. "/" .. self.provider.repo .. ")"
  winbar = winbar .. " (" .. total .. ")"

  vim.api.nvim_set_option_value("winbar", winbar, { win = self.winnr, scope = "local" })
end

--- Render the PR list buffer
function PRListBuffer:render()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  self:_update_winbar()

  if #self.sections > 0 then
    self:_render_sectioned()
  else
    self:_render_flat()
  end
end

--- Render flat PR list (fallback mode, no sections)
function PRListBuffer:_render_flat()
  local lines = {}
  self.line_map = {}
  self.section_lines = {}

  if #self.prs == 0 then
    table.insert(lines, "No pull requests found.")
  else
    local result = pr_list_component.render(self.prs, {
      indent = 0,
      max_title_len = 60,
    })

    for i, line in ipairs(result.lines) do
      table.insert(lines, line)
      local info = result.line_info[i]
      if info then
        self.line_map[#lines] = info
      end
    end
  end

  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  self:_apply_highlights()
  vim.bo[self.bufnr].modifiable = false
end

--- Render sectioned PR list (dashboard mode)
function PRListBuffer:_render_sectioned()
  local lines = {}
  self.line_map = {}
  self.section_lines = {}

  local has_any_prs = false
  for _, section in ipairs(self.sections) do
    if #section.prs > 0 then
      has_any_prs = true
      break
    end
  end

  if not has_any_prs then
    table.insert(lines, "No pull requests found.")
  else
    for _, section in ipairs(self.sections) do
      if #section.prs > 0 then
        -- Add blank line separator between sections (not before first)
        if #lines > 0 then
          table.insert(lines, "")
        end

        -- Section header
        local header = string.format("%s (%d)", section.title, #section.prs)
        table.insert(lines, header)
        self.section_lines[#lines] = { type = "section", key = section.key }

        -- PR lines (unless collapsed)
        if not self.collapsed_sections[section.key] then
          local result = pr_list_component.render(section.prs, {
            indent = 2,
            max_title_len = 58,
          })

          for i, line in ipairs(result.lines) do
            table.insert(lines, line)
            local info = result.line_info[i]
            if info then
              self.line_map[#lines] = info
            end
          end
        end
      end
    end
  end

  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  self:_apply_highlights()
  vim.bo[self.bufnr].modifiable = false
end

--- Apply syntax highlighting
function PRListBuffer:_apply_highlights()
  local ns = hl.get_namespaces().status

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  -- Highlight section headers
  for line_nr, info in pairs(self.section_lines) do
    if info then
      hl.set(
        self.bufnr,
        ns,
        line_nr - 1,
        0,
        #vim.api.nvim_buf_get_lines(self.bufnr, line_nr - 1, line_nr, false)[1],
        "GitladSectionHeader"
      )
    end
  end

  -- Highlight PR lines per section
  if #self.sections > 0 then
    for _, section in ipairs(self.sections) do
      if #section.prs > 0 and not self.collapsed_sections[section.key] then
        local result = pr_list_component.render(section.prs, {
          indent = 2,
          max_title_len = 58,
        })
        -- Find where this section's PRs start in the buffer
        local start_line = self:_find_section_pr_start(section.key)
        if start_line then
          pr_list_component.apply_highlights(self.bufnr, ns, start_line - 1, result)
        end
      end
    end
  else
    -- Flat mode
    if #self.prs > 0 then
      local result = pr_list_component.render(self.prs, {
        indent = 0,
        max_title_len = 60,
      })
      pr_list_component.apply_highlights(self.bufnr, ns, 0, result)
    end
  end
end

--- Find the buffer line number where a section's PR lines start
---@param section_key string
---@return number|nil start_line 1-indexed line number of first PR in section
function PRListBuffer:_find_section_pr_start(section_key)
  -- Find the section header line, then the first PR line after it
  for line_nr, info in pairs(self.section_lines) do
    if info.key == section_key then
      -- First PR line is immediately after header
      return line_nr + 1
    end
  end
  return nil
end

--- Open the PR list buffer with data from provider
---@param repo_state RepoState
---@param provider ForgeProvider
---@param opts ForgeListPRsOpts|nil
function PRListBuffer:open_with_provider(repo_state, provider, opts)
  self.repo_state = repo_state
  self.provider = provider
  self.opts = opts or {}

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

  -- Show loading state
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "Loading pull requests..." })
  vim.bo[self.bufnr].modifiable = false

  -- Fetch PRs
  self:refresh()
end

--- Close the PR list buffer
function PRListBuffer:close()
  utils.close_view_buffer(self)
end

-- =============================================================================
-- Module-level API
-- =============================================================================

--- Open PR list view (module-level entry point)
---@param repo_state RepoState
---@param provider ForgeProvider
---@param opts? ForgeListPRsOpts
function M.open(repo_state, provider, opts)
  local buf = get_or_create_buffer(repo_state, provider)
  buf:open_with_provider(repo_state, provider, opts)
end

--- Close PR list view for a specific repo
---@param repo_state? RepoState
function M.close(repo_state)
  local key = repo_state and repo_state.repo_root or "default"
  local buf = pr_list_buffers[key]
  if buf then
    buf:close()
  end
end

--- Get the PR list buffer for a repo if it exists
---@param repo_state? RepoState
---@return PRListBuffer|nil
function M.get_buffer(repo_state)
  if repo_state then
    local key = repo_state.repo_root
    local buf = pr_list_buffers[key]
    if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
    return nil
  end
  for _, buf in pairs(pr_list_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      return buf
    end
  end
  return nil
end

--- Clear all PR list buffers (for testing)
function M.clear_all()
  for _, buf in pairs(pr_list_buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    end
  end
  pr_list_buffers = {}
end

return M
