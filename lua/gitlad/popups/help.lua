---@mod gitlad.popups.help Help popup
---@brief [[
--- Magit-style help popup showing all keybindings organized in columns.
--- Items within each section are arranged horizontally in columns.
---@brief ]]

local M = {}

local keymap = require("gitlad.utils.keymap")
local hl = require("gitlad.ui.hl")

---@class HelpItem
---@field key string Key binding (e.g., "c", "gr", "<Tab>")
---@field desc string Description
---@field action? fun() Optional callback when key is pressed

---@class HelpSection
---@field name string Section header
---@field columns number Number of columns for items
---@field items HelpItem[]

---@class HelpView
---@field buffer number|nil Buffer handle
---@field window number|nil Window handle
---@field sections HelpSection[] Section definitions
---@field action_positions table<number, table<string, {col: number, len: number}>> Position metadata for highlighting
local HelpView = {}
HelpView.__index = HelpView

--- Get display width of a string (accounts for multi-byte UTF-8 characters)
---@param str string
---@return number display_width
local function display_width(str)
  if vim.fn and vim.fn.strdisplaywidth then
    return vim.fn.strdisplaywidth(str)
  end
  local width = 0
  for _ in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    width = width + 1
  end
  return width
end

--- Pad a string to a target display width
---@param str string
---@param target_width number
---@return string padded_string
local function pad_to_width(str, target_width)
  local current_width = display_width(str)
  if current_width >= target_width then
    return str
  end
  return str .. string.rep(" ", target_width - current_width)
end

--- Create a new HelpView
---@param sections HelpSection[]
---@return HelpView
function HelpView.new(sections)
  local self = setmetatable({}, HelpView)
  self.sections = sections
  self.buffer = nil
  self.window = nil
  self.action_positions = {}
  return self
end

--- Render a single section as lines with items in columns
---@param section HelpSection
---@param start_line number 1-indexed starting line number in buffer
---@return string[] lines
---@return table<number, table<string, {col: number, len: number}>> positions
function HelpView:_render_section(section, start_line)
  local lines = {}
  local positions = {}

  -- Add section header
  table.insert(lines, section.name)

  if #section.items == 0 then
    return lines, positions
  end

  -- Calculate max item width (key + space + description)
  local max_item_width = 0
  for _, item in ipairs(section.items) do
    local item_width = display_width(item.key) + 1 + display_width(item.desc)
    max_item_width = math.max(max_item_width, item_width)
  end
  -- Add gap between columns (2 spaces minimum)
  local col_width = max_item_width + 2

  -- Calculate number of rows needed
  local num_cols = section.columns
  local num_items = #section.items
  local num_rows = math.ceil(num_items / num_cols)

  -- Render row by row
  for row = 1, num_rows do
    local parts = {}
    local line_positions = {}
    local byte_offset = 0

    for col = 1, num_cols do
      local idx = (row - 1) * num_cols + col
      local item = section.items[idx]

      if item then
        -- Format: " key description" with leading space
        local text = string.format(" %s %s", item.key, item.desc)
        local padded = pad_to_width(text, col_width)

        -- Track position for highlighting (byte offset + 1 for leading space)
        line_positions[item.key] = { col = byte_offset + 1, len = #item.key }

        table.insert(parts, padded)
        byte_offset = byte_offset + #padded
      end
    end

    local line = table.concat(parts)
    -- Trim trailing whitespace
    line = line:gsub("%s+$", "")
    table.insert(lines, line)

    -- Store positions for this line
    local line_num = start_line + #lines - 1
    positions[line_num] = line_positions
  end

  return lines, positions
end

--- Render all sections
---@return string[] lines
function HelpView:render_lines()
  local all_lines = {}
  self.action_positions = {}

  for i, section in ipairs(self.sections) do
    -- Add blank line between sections (but not before first)
    if i > 1 then
      table.insert(all_lines, "")
    end

    local start_line = #all_lines + 1
    local section_lines, positions = self:_render_section(section, start_line)

    for _, line in ipairs(section_lines) do
      table.insert(all_lines, line)
    end

    -- Merge positions
    for line_num, line_positions in pairs(positions) do
      self.action_positions[line_num] = line_positions
    end
  end

  return all_lines
end

--- Apply highlights to the help buffer
---@param lines string[]
function HelpView:_apply_highlights(lines)
  local ns = hl.get_namespaces().popup

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(self.buffer, ns, 0, -1)

  for line_idx, line in ipairs(lines) do
    local line_0 = line_idx - 1

    -- Check if this is a section header (starts with capital letter, not space)
    if line:match("^[A-Z]") then
      -- Highlight entire line as heading
      vim.api.nvim_buf_set_extmark(self.buffer, ns, line_0, 0, {
        end_col = #line,
        hl_group = "GitladPopupHeading",
      })
    else
      -- Check for action positions on this line
      local line_positions = self.action_positions[line_idx]
      if line_positions then
        for key, pos in pairs(line_positions) do
          -- Highlight the key
          vim.api.nvim_buf_set_extmark(self.buffer, ns, line_0, pos.col, {
            end_col = pos.col + pos.len,
            hl_group = "GitladPopupActionKey",
          })
        end
      end
    end
  end
end

--- Set up keymaps for the help buffer
function HelpView:_setup_keymaps()
  local bufnr = self.buffer
  local nowait_opts = { nowait = true }

  -- Close keymaps
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close help", nowait_opts)

  keymap.set(bufnr, "n", "<Esc>", function()
    self:close()
  end, "Close help", nowait_opts)

  -- Set up keymaps for each action
  for _, section in ipairs(self.sections) do
    for _, item in ipairs(section.items) do
      if item.action then
        keymap.set(bufnr, "n", item.key, function()
          self:close()
          item.action()
        end, item.desc, nowait_opts)
      end
    end
  end
end

--- Show the help popup
function HelpView:show()
  local lines = self:render_lines()

  -- Calculate window size
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, display_width(line))
  end
  width = math.max(width + 4, 40) -- Minimum width of 40, plus padding
  local height = #lines

  -- Create buffer
  self.buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, lines)
  vim.bo[self.buffer].modifiable = false
  vim.bo[self.buffer].buftype = "nofile"
  vim.bo[self.buffer].bufhidden = "wipe"

  -- Create floating window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
  }
  self.window = vim.api.nvim_open_win(self.buffer, true, win_opts)

  -- Apply highlights and keymaps
  self:_apply_highlights(lines)
  self:_setup_keymaps()
end

--- Close the help popup
function HelpView:close()
  if self.window and vim.api.nvim_win_is_valid(self.window) then
    vim.api.nvim_win_close(self.window, true)
  end
  self.window = nil
  self.buffer = nil
end

--- Create section definitions based on current context
---@param status_buffer StatusBuffer
---@return HelpSection[]
local function create_sections(status_buffer)
  local repo_state = status_buffer.repo_state

  return {
    -- Transient commands (popups) - 3 columns
    {
      name = "Transient commands",
      columns = 3,
      items = {
        {
          key = "c",
          desc = "Commit",
          action = function()
            require("gitlad.popups.commit").open(repo_state)
          end,
        },
        {
          key = "b",
          desc = "Branch",
          action = function()
            require("gitlad.popups.branch").open(repo_state)
          end,
        },
        {
          key = "l",
          desc = "Log",
          action = function()
            require("gitlad.popups.log").open(repo_state)
          end,
        },
        {
          key = "p",
          desc = "Push",
          action = function()
            require("gitlad.popups.push").open(repo_state)
          end,
        },
        {
          key = "F",
          desc = "Pull",
          action = function()
            require("gitlad.popups.pull").open(repo_state)
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
          key = "d",
          desc = "Diff",
          action = function()
            require("gitlad.popups.diff").open(repo_state, {})
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
          key = "m",
          desc = "Merge",
          action = function()
            require("gitlad.popups.merge").open(repo_state)
          end,
        },
        {
          key = "z",
          desc = "Stash",
          action = function()
            require("gitlad.popups.stash").open(repo_state)
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
          key = "_",
          desc = "Revert",
          action = function()
            require("gitlad.popups.revert").open(repo_state)
          end,
        },
        {
          key = "X",
          desc = "Reset",
          action = function()
            require("gitlad.popups.reset").open(repo_state)
          end,
        },
        {
          key = "'",
          desc = "Submodule",
          action = function()
            require("gitlad.popups.submodule").open(repo_state)
          end,
        },
        {
          key = "Z",
          desc = "Worktree",
          action = function()
            require("gitlad.popups.worktree").open(repo_state)
          end,
        },
        {
          key = "M",
          desc = "Remotes",
          action = function()
            require("gitlad.popups.remote").open(repo_state)
          end,
        },
        {
          key = "W",
          desc = "Patch",
          action = function()
            require("gitlad.popups.patch").open(repo_state)
          end,
        },
        {
          key = "w",
          desc = "Apply patches",
          action = function()
            require("gitlad.popups.am").open(repo_state)
          end,
        },
        {
          key = "yr",
          desc = "References",
          action = function()
            require("gitlad.popups.refs").open(repo_state)
          end,
        },
      },
    },

    -- Applying changes - 3 columns
    {
      name = "Applying changes",
      columns = 3,
      items = {
        { key = "s", desc = "Stage" },
        { key = "u", desc = "Unstage" },
        { key = "gs", desc = "Intent to add" },
        {
          key = "S",
          desc = "Stage all",
          action = function()
            status_buffer:_stage_all()
          end,
        },
        { key = "x", desc = "Discard" },
        {
          key = "U",
          desc = "Unstage all",
          action = function()
            status_buffer:_unstage_all()
          end,
        },
      },
    },

    -- Navigation - 3 columns
    {
      name = "Navigation",
      columns = 3,
      items = {
        { key = "j", desc = "Next item" },
        { key = "k", desc = "Previous item" },
        { key = "gj", desc = "Next section" },
        { key = "gk", desc = "Previous section" },
        { key = "<Tab>", desc = "Toggle section" },
        {
          key = "<S-Tab>",
          desc = "Toggle all",
          action = function()
            status_buffer:_toggle_all_sections()
          end,
        },
        {
          key = "1",
          desc = "Headers only",
          action = function()
            status_buffer:_apply_scoped_visibility_level(1)
          end,
        },
        {
          key = "2",
          desc = "Show items",
          action = function()
            status_buffer:_apply_scoped_visibility_level(2)
          end,
        },
        {
          key = "3",
          desc = "Show diffs",
          action = function()
            status_buffer:_apply_scoped_visibility_level(3)
          end,
        },
        {
          key = "4",
          desc = "Show all",
          action = function()
            status_buffer:_apply_scoped_visibility_level(4)
          end,
        },
        { key = "<CR>", desc = "Visit file" },
        { key = "e", desc = "Edit file" },
      },
    },

    -- Essential commands - 2 columns
    {
      name = "Essential commands",
      columns = 2,
      items = {
        {
          key = "gr",
          desc = "Refresh",
          action = function()
            repo_state:refresh_status(true)
          end,
        },
        {
          key = "$",
          desc = "Git command history",
          action = function()
            require("gitlad.ui.views.history").open()
          end,
        },
        {
          key = "ys",
          desc = "Yank section value",
          action = function()
            status_buffer:_yank_section_value()
          end,
        },
        { key = "q", desc = "Close buffer" },
        { key = "?", desc = "This help" },
      },
    },
  }
end

--- Create and show the help popup
---@param status_buffer StatusBuffer
function M.open(status_buffer)
  local sections = create_sections(status_buffer)
  local help_view = HelpView.new(sections)
  help_view:show()
end

-- Export HelpView for testing
M.HelpView = HelpView

return M
