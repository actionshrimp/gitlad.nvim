---@mod gitlad.ui.popup Transient-style popup system
---@brief [[
--- A popup system inspired by magit/neogit transients.
--- Supports switches (boolean flags), options (key-value), and actions.
---@brief ]]

local M = {}

local keymap = require("gitlad.utils.keymap")
local hl = require("gitlad.ui.hl")

---@class PopupSwitch
---@field key string Single character key binding
---@field cli string CLI flag name (without --)
---@field description string User-facing description
---@field enabled boolean Current state
---@field cli_prefix string Prefix for CLI flag (default "--")

---@class PopupOption
---@field key string Single character key binding
---@field cli string CLI flag name (without --)
---@field value string Current value
---@field description string User-facing description
---@field cli_prefix string Prefix for CLI flag (default "--")
---@field separator string Separator between flag and value (default "=")

---@class PopupAction
---@field type "heading"|"action"
---@field key? string Single character key binding (for actions)
---@field text? string Heading text (for headings)
---@field description? string User-facing description (for actions)
---@field callback? fun(popup: PopupData) Callback function (for actions)

---@class PopupData
---@field name string Popup identifier
---@field switches PopupSwitch[] List of switches
---@field options PopupOption[] List of options
---@field actions PopupAction[] List of actions and headings
---@field buffer number|nil Buffer handle when shown
---@field window number|nil Window handle when shown
local PopupData = {}
PopupData.__index = PopupData

---@class PopupBuilder
---@field _name string Popup name
---@field _switches PopupSwitch[] Switches being built
---@field _options PopupOption[] Options being built
---@field _actions PopupAction[] Actions being built
local PopupBuilder = {}
PopupBuilder.__index = PopupBuilder

--- Create a new popup builder
---@return PopupBuilder
function M.builder()
  local builder = setmetatable({}, PopupBuilder)
  builder._name = ""
  builder._switches = {}
  builder._options = {}
  builder._actions = {}
  return builder
end

--- Set the popup name
---@param name string
---@return PopupBuilder
function PopupBuilder:name(name)
  self._name = name
  return self
end

--- Add a switch (boolean toggle)
---@param key string Single character key
---@param cli string CLI flag name (without --)
---@param description string User-facing description
---@param opts? { enabled?: boolean, cli_prefix?: string }
---@return PopupBuilder
function PopupBuilder:switch(key, cli, description, opts)
  opts = opts or {}
  table.insert(self._switches, {
    key = key,
    cli = cli,
    description = description,
    enabled = opts.enabled or false,
    cli_prefix = opts.cli_prefix or "--",
  })
  return self
end

--- Add an option (key-value)
---@param key string Single character key
---@param cli string CLI flag name (without --)
---@param value string Default/current value
---@param description string User-facing description
---@param opts? { cli_prefix?: string, separator?: string }
---@return PopupBuilder
function PopupBuilder:option(key, cli, value, description, opts)
  opts = opts or {}
  table.insert(self._options, {
    key = key,
    cli = cli,
    value = value,
    description = description,
    cli_prefix = opts.cli_prefix or "--",
    separator = opts.separator or "=",
  })
  return self
end

--- Add a section heading
---@param text string Heading text
---@return PopupBuilder
function PopupBuilder:group_heading(text)
  table.insert(self._actions, {
    type = "heading",
    text = text,
  })
  return self
end

--- Add an action
---@param key string Single character key
---@param description string User-facing description
---@param callback fun(popup: PopupData) Callback when action is triggered
---@return PopupBuilder
function PopupBuilder:action(key, description, callback)
  table.insert(self._actions, {
    type = "action",
    key = key,
    description = description,
    callback = callback,
  })
  return self
end

--- Build the popup data
---@return PopupData
function PopupBuilder:build()
  local data = setmetatable({}, PopupData)
  data.name = self._name
  data.switches = vim.deepcopy(self._switches)
  data.options = vim.deepcopy(self._options)
  data.actions = vim.deepcopy(self._actions)
  data.buffer = nil
  data.window = nil
  return data
end

--- Get CLI arguments from enabled switches and options with values
---@return string[]
function PopupData:get_arguments()
  local args = {}

  -- Add enabled switches
  for _, sw in ipairs(self.switches) do
    if sw.enabled then
      table.insert(args, sw.cli_prefix .. sw.cli)
    end
  end

  -- Add options with values
  for _, opt in ipairs(self.options) do
    if opt.value and opt.value ~= "" then
      table.insert(args, opt.cli_prefix .. opt.cli .. opt.separator .. opt.value)
    end
  end

  return args
end

--- Get CLI arguments as a single string
---@return string
function PopupData:to_cli()
  return table.concat(self:get_arguments(), " ")
end

--- Toggle a switch by key
---@param key string Switch key
function PopupData:toggle_switch(key)
  for _, sw in ipairs(self.switches) do
    if sw.key == key then
      sw.enabled = not sw.enabled
      return
    end
  end
end

--- Set an option value by key
---@param key string Option key
---@param value string New value
function PopupData:set_option(key, value)
  for _, opt in ipairs(self.options) do
    if opt.key == key then
      opt.value = value
      return
    end
  end
end

--- Render the popup as lines of text
---@return string[]
function PopupData:render_lines()
  local lines = {}

  -- Arguments section (switches and options)
  if #self.switches > 0 or #self.options > 0 then
    table.insert(lines, "Arguments")

    -- Switches
    for _, sw in ipairs(self.switches) do
      local enabled_marker = sw.enabled and "*" or " "
      local cli_display = string.format("(%s%s)", sw.cli_prefix, sw.cli)
      local line =
        string.format(" %s-%s %s %s", enabled_marker, sw.key, sw.description, cli_display)
      table.insert(lines, line)
    end

    -- Options
    for _, opt in ipairs(self.options) do
      local value_display = opt.value ~= "" and opt.value or ""
      local cli_display
      if value_display ~= "" then
        cli_display =
          string.format("(%s%s%s%s)", opt.cli_prefix, opt.cli, opt.separator, value_display)
      else
        cli_display = string.format("(%s%s%s)", opt.cli_prefix, opt.cli, opt.separator)
      end
      local line = string.format("  =%s %s %s", opt.key, opt.description, cli_display)
      table.insert(lines, line)
    end

    table.insert(lines, "")
  end

  -- Actions section
  for _, item in ipairs(self.actions) do
    if item.type == "heading" then
      table.insert(lines, item.text)
    elseif item.type == "action" then
      local line = string.format(" %s %s", item.key, item.description)
      table.insert(lines, line)
    end
  end

  return lines
end

--- Show the popup in a floating window
function PopupData:show()
  local lines = self:render_lines()

  -- Calculate window size
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
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
    title = self.name ~= "" and (" " .. self.name .. " ") or nil,
    title_pos = "center",
  }
  self.window = vim.api.nvim_open_win(self.buffer, true, win_opts)

  -- Apply syntax highlighting
  hl.apply_popup_highlights(self.buffer, lines, self.switches, self.options, self.actions)

  -- Set up keymaps
  self:_setup_keymaps()
end

--- Close the popup
function PopupData:close()
  if self.window and vim.api.nvim_win_is_valid(self.window) then
    vim.api.nvim_win_close(self.window, true)
  end
  self.window = nil
  self.buffer = nil
end

--- Refresh the popup display
function PopupData:refresh()
  if not self.buffer or not vim.api.nvim_buf_is_valid(self.buffer) then
    return
  end

  local lines = self:render_lines()
  vim.bo[self.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, lines)
  vim.bo[self.buffer].modifiable = false

  -- Apply syntax highlighting
  hl.apply_popup_highlights(self.buffer, lines, self.switches, self.options, self.actions)
end

--- Set up keymaps for the popup buffer
function PopupData:_setup_keymaps()
  local bufnr = self.buffer
  local nowait_opts = { nowait = true }

  -- Close keymaps
  keymap.set(bufnr, "n", "q", function()
    self:close()
  end, "Close popup", nowait_opts)
  keymap.set(bufnr, "n", "<Esc>", function()
    self:close()
  end, "Close popup", nowait_opts)

  -- Switch prefix key (-)
  keymap.set(bufnr, "n", "-", function()
    -- Wait for next key
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok or not char then
      return
    end
    self:toggle_switch(char)
    self:refresh()
  end, "Toggle switch", nowait_opts)

  -- Option prefix key (=)
  keymap.set(bufnr, "n", "=", function()
    -- Wait for next key
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok or not char then
      return
    end

    -- Find the option
    local opt = nil
    for _, o in ipairs(self.options) do
      if o.key == char then
        opt = o
        break
      end
    end

    if not opt then
      return
    end

    -- Prompt for value
    local current = opt.value ~= "" and opt.value or ""
    vim.ui.input({ prompt = opt.description .. ": ", default = current }, function(input)
      if input ~= nil then
        self:set_option(char, input)
        self:refresh()
      end
    end)
  end, "Set option", nowait_opts)

  -- Action keymaps (direct keys)
  for _, item in ipairs(self.actions) do
    if item.type == "action" and item.key then
      keymap.set(bufnr, "n", item.key, function()
        self:close()
        if item.callback then
          item.callback(self)
        end
      end, item.description or "Action", nowait_opts)
    end
  end
end

return M
