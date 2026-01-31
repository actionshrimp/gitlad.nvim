---@mod gitlad.ui.popup Transient-style popup system
---@brief [[
--- A popup system inspired by magit/neogit transients.
--- Supports switches (boolean flags), options (key-value), and actions.
---@brief ]]

local M = {}

local keymap = require("gitlad.utils.keymap")
local hl = require("gitlad.ui.hl")
local git = require("gitlad.git")

---@class PopupSwitch
---@field key string Single character key binding
---@field cli string CLI flag name (without --)
---@field description string User-facing description
---@field enabled boolean Current state
---@field cli_prefix string Prefix for CLI flag (default "--")
---@field exclusive_with? string[] CLI names of switches that are mutually exclusive

---@class PopupOption
---@field key string Single character key binding
---@field cli string CLI flag name (without --)
---@field value string Current value
---@field description string User-facing description
---@field cli_prefix string Prefix for CLI flag (default "--")
---@field separator string Separator between flag and value (default "=")
---@field choices? string[] If set, use vim.ui.select instead of vim.ui.input

---@class PopupAction
---@field type "heading"|"action"
---@field key? string Single character key binding (for actions)
---@field text? string Heading text (for headings)
---@field description? string User-facing description (for actions)
---@field callback? fun(popup: PopupData) Callback function (for actions)

---@class PopupConfigVar
---@field type "config_heading"|"config_var"
---@field key? string Single character key binding (for config_var, nil for read-only)
---@field text? string Heading text (for config_heading, supports %s for branch substitution)
---@field config_key? string Git config key (for config_var, supports %s for branch substitution)
---@field label? string Display label (for config_var, supports %s for branch substitution)
---@field var_type? "text"|"cycle"|"remote_cycle" How to handle the value (for config_var)
---@field choices? string[] For "cycle" type - values to cycle through
---@field default_display? string What to show for default/unset (e.g., "default:false")
---@field current_value? string Current value (populated on build)
---@field fallback? string Fallback config key for remote_cycle (e.g., "remote.pushDefault")
---@field fallback_value? string Cached fallback value (populated on build)
---@field remote_choices? string[] Dynamically populated list of remote names (for remote_cycle)
---@field read_only? boolean If true, display only with no keybinding
---@field on_set? fun(value: string, popup: PopupData): table<string,string>|nil Custom setter that can set multiple configs

---@class PopupData
---@field name string Popup identifier
---@field switches PopupSwitch[] List of switches
---@field options PopupOption[] List of options
---@field actions PopupAction[] List of actions and headings
---@field config_vars PopupConfigVar[] List of config variables and headings
---@field branch_scope string|nil Branch name for %s substitution in config keys
---@field repo_root string|nil Repository root for git config operations
---@field buffer number|nil Buffer handle when shown
---@field window number|nil Window handle when shown
---@field columns number Number of columns for action rendering (default 1)
---@field action_positions table<number, table<string, {col: number, len: number}>> Line -> key -> position info for highlighting
---@field config_positions table<number, table<string, {col: number, len: number}>> Line -> key -> position info for config highlighting
local PopupData = {}
PopupData.__index = PopupData

---@class PopupBuilder
---@field _name string Popup name
---@field _switches PopupSwitch[] Switches being built
---@field _options PopupOption[] Options being built
---@field _actions PopupAction[] Actions being built
---@field _config_vars PopupConfigVar[] Config variables being built
---@field _branch_scope string|nil Branch name for %s substitution
---@field _repo_root string|nil Repository root for git config operations
---@field _columns number Number of columns for action rendering (default 1)
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
  builder._config_vars = {}
  builder._branch_scope = nil
  builder._repo_root = nil
  builder._columns = 1
  return builder
end

--- Set the popup name
---@param name string
---@return PopupBuilder
function PopupBuilder:name(name)
  self._name = name
  return self
end

--- Set the number of columns for action rendering
---@param n number Number of columns (default 1)
---@return PopupBuilder
function PopupBuilder:columns(n)
  self._columns = n
  return self
end

--- Add a switch (boolean toggle)
---@param key string Single character key
---@param cli string CLI flag name (without --)
---@param description string User-facing description
---@param opts? { enabled?: boolean, cli_prefix?: string, exclusive_with?: string[] }
---@return PopupBuilder
function PopupBuilder:switch(key, cli, description, opts)
  opts = opts or {}
  table.insert(self._switches, {
    key = key,
    cli = cli,
    description = description,
    enabled = opts.enabled or false,
    cli_prefix = opts.cli_prefix or "--",
    exclusive_with = opts.exclusive_with,
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

--- Add an option with constrained choices (uses vim.ui.select)
---@param key string Single character key
---@param cli string CLI flag name (without --)
---@param choices string[] List of valid choices
---@param description string User-facing description
---@param opts? { cli_prefix?: string, separator?: string, default?: string }
---@return PopupBuilder
function PopupBuilder:choice_option(key, cli, choices, description, opts)
  opts = opts or {}
  table.insert(self._options, {
    key = key,
    cli = cli,
    value = opts.default or "",
    description = description,
    cli_prefix = opts.cli_prefix or "--",
    separator = opts.separator or "=",
    choices = choices,
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

--- Set the branch scope for %s substitution in config keys/labels
---@param branch string Branch name
---@return PopupBuilder
function PopupBuilder:branch_scope(branch)
  self._branch_scope = branch
  return self
end

--- Set the repository root for git config operations
---@param path string Repository root path
---@return PopupBuilder
function PopupBuilder:repo_root(path)
  self._repo_root = path
  return self
end

--- Add a config section heading
---@param text string Heading text (supports %s for branch substitution)
---@return PopupBuilder
function PopupBuilder:config_heading(text)
  table.insert(self._config_vars, {
    type = "config_heading",
    text = text,
  })
  return self
end

--- Add a read-only config display line (no keybinding)
--- Use this for config values that are set indirectly (e.g., branch.remote set via merge)
---@param config_key string Git config key (supports %s for branch substitution)
---@param label string Display label (supports %s for branch substitution)
---@return PopupBuilder
function PopupBuilder:config_display(config_key, label)
  table.insert(self._config_vars, {
    type = "config_var",
    key = nil, -- No key = read-only
    config_key = config_key,
    label = label,
    var_type = "text",
    read_only = true,
  })
  return self
end

--- Add a config variable
---@param key string Single character key binding
---@param config_key string Git config key (supports %s for branch substitution)
---@param label string Display label (supports %s for branch substitution)
---@param opts? { type?: "text"|"cycle"|"remote_cycle", choices?: string[], default_display?: string, fallback?: string, on_set?: fun(value: string, popup: PopupData): table<string,string>|nil }
---@return PopupBuilder
function PopupBuilder:config_var(key, config_key, label, opts)
  opts = opts or {}
  table.insert(self._config_vars, {
    type = "config_var",
    key = key,
    config_key = config_key,
    label = label,
    var_type = opts.type or "text",
    choices = opts.choices,
    default_display = opts.default_display,
    fallback = opts.fallback,
    on_set = opts.on_set,
  })
  return self
end

--- Substitute %s with branch name in a string
---@param str string
---@param branch string|nil
---@return string
local function substitute_branch(str, branch)
  if not branch or not str then
    return str or ""
  end
  return str:gsub("%%s", branch)
end

--- Build the popup data
---@return PopupData
function PopupBuilder:build()
  local data = setmetatable({}, PopupData)
  data.name = self._name
  data.switches = vim.deepcopy(self._switches)
  data.options = vim.deepcopy(self._options)
  data.actions = vim.deepcopy(self._actions)
  data.branch_scope = self._branch_scope
  data.repo_root = self._repo_root
  data.buffer = nil
  data.window = nil
  data.columns = self._columns or 1
  data.action_positions = {}
  data.config_positions = {}

  -- Process config vars: substitute branch and load current values
  data.config_vars = {}
  local git_opts = data.repo_root and { cwd = data.repo_root } or nil

  -- Fetch remotes once for all remote_cycle vars (synchronous, fast operation)
  local remotes_cache = nil
  local function get_remotes()
    if remotes_cache == nil then
      local ok, result = pcall(git.remote_names_sync, git_opts)
      remotes_cache = (ok and result) or {}
    end
    return remotes_cache
  end

  for _, cv in ipairs(self._config_vars) do
    local item = vim.deepcopy(cv)
    if item.type == "config_heading" then
      item.text = substitute_branch(item.text, data.branch_scope)
    elseif item.type == "config_var" then
      item.config_key = substitute_branch(item.config_key, data.branch_scope)
      item.label = substitute_branch(item.label, data.branch_scope)
      -- Load current value synchronously (config reads are fast)
      item.current_value = git.config_get(item.config_key, git_opts)

      -- For remote_cycle type, populate remote_choices and fallback_value
      if item.var_type == "remote_cycle" then
        item.remote_choices = get_remotes() or {}
        if item.fallback then
          item.fallback_value = git.config_get(item.fallback, git_opts)
        end
      end
    end
    table.insert(data.config_vars, item)
  end

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
      -- Disable mutually exclusive switches when enabling
      if sw.enabled and sw.exclusive_with then
        for _, other in ipairs(self.switches) do
          for _, excl_cli in ipairs(sw.exclusive_with) do
            if other.cli == excl_cli then
              other.enabled = false
            end
          end
        end
      end
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

--- Find a config var by key
---@param key string Config var key
---@return PopupConfigVar|nil
function PopupData:_find_config_var(key)
  for _, cv in ipairs(self.config_vars or {}) do
    if cv.type == "config_var" and cv.key == key then
      return cv
    end
  end
  return nil
end

--- Set a config var value (async, updates git config)
---@param key string Config var key
---@param value string|nil New value (nil or "" to unset)
---@param callback? fun(success: boolean, err: string|nil)
function PopupData:set_config_var(key, value, callback)
  local cv = self:_find_config_var(key)
  if not cv then
    if callback then
      callback(false, "Config var not found: " .. key)
    end
    return
  end

  local git_opts = self.repo_root and { cwd = self.repo_root } or nil

  if value == nil or value == "" then
    -- Unset the config
    git.config_unset(cv.config_key, git_opts, function(success, err)
      if success then
        cv.current_value = nil
      end
      if callback then
        callback(success, err)
      end
    end)
  else
    -- Set the config
    git.config_set(cv.config_key, value, git_opts, function(success, err)
      if success then
        cv.current_value = value
      end
      if callback then
        callback(success, err)
      end
    end)
  end
end

--- Cycle a config var to the next value (for "cycle" or "remote_cycle" type)
---@param key string Config var key
---@param callback? fun(success: boolean, err: string|nil)
function PopupData:cycle_config_var(key, callback)
  local cv = self:_find_config_var(key)
  if not cv then
    if callback then
      callback(false, "Config var not found: " .. key)
    end
    return
  end

  -- Determine the choices based on var_type
  local choices
  if cv.var_type == "cycle" then
    if not cv.choices then
      if callback then
        callback(false, "Config var has no choices")
      end
      return
    end
    choices = cv.choices
  elseif cv.var_type == "remote_cycle" then
    if not cv.remote_choices then
      if callback then
        callback(false, "Config var has no remote choices")
      end
      return
    end
    -- Build choices: all remotes plus empty string (unset)
    choices = vim.list_extend({}, cv.remote_choices)
    table.insert(choices, "") -- Add empty for "unset" option
  else
    if callback then
      callback(false, "Config var is not a cycle type")
    end
    return
  end

  -- Find current index
  local current_idx = nil
  local current = cv.current_value
  for i, choice in ipairs(choices) do
    if choice == "" then
      -- Empty string matches nil/unset
      if current == nil or current == "" then
        current_idx = i
        break
      end
    elseif choice == current then
      current_idx = i
      break
    end
  end

  -- Cycle to next (or first if not found)
  local next_idx = current_idx and (current_idx % #choices) + 1 or 1
  local next_value = choices[next_idx]

  -- Empty string means unset
  if next_value == "" then
    self:set_config_var(key, nil, callback)
  else
    self:set_config_var(key, next_value, callback)
  end
end

--- Set multiple config vars at once (for on_set callbacks that modify multiple configs)
---@param values table<string, string|nil> Map of config_key to value (nil to unset)
---@param callback? fun(success: boolean, err: string|nil)
function PopupData:set_multiple_config_vars(values, callback)
  local git_opts = self.repo_root and { cwd = self.repo_root } or nil
  local errors = {}

  -- Convert to array for sequential processing (avoids git config lock conflicts)
  local operations = {}
  for config_key, value in pairs(values) do
    table.insert(operations, { key = config_key, value = value })
  end

  if #operations == 0 then
    if callback then
      callback(true, nil)
    end
    return
  end

  -- Process operations sequentially to avoid git config lock conflicts
  local function process_next(idx)
    if idx > #operations then
      -- All done - update cached current_value for all affected config_vars
      for _, op in ipairs(operations) do
        for _, cv in ipairs(self.config_vars) do
          if cv.type == "config_var" and cv.config_key == op.key then
            cv.current_value = op.value
          end
        end
      end
      if callback then
        callback(#errors == 0, #errors > 0 and table.concat(errors, ", ") or nil)
      end
      return
    end

    local op = operations[idx]
    local function on_done(success, err)
      if not success and err then
        table.insert(errors, err)
      end
      process_next(idx + 1)
    end

    if op.value == nil or op.value == "" then
      git.config_unset(op.key, git_opts, on_done)
    else
      git.config_set(op.key, op.value, git_opts, on_done)
    end
  end

  process_next(1)
end

--- Prompt for a config var value (for "text" type)
---@param key string Config var key
---@param callback? fun(success: boolean, err: string|nil)
function PopupData:prompt_config_var(key, callback)
  local cv = self:_find_config_var(key)
  if not cv then
    if callback then
      callback(false, "Config var not found: " .. key)
    end
    return
  end

  local current = cv.current_value or ""
  vim.ui.input({ prompt = cv.label .. ": ", default = current }, function(input)
    if input == nil then
      -- Cancelled
      if callback then
        callback(false, nil)
      end
      return
    end

    -- Check for custom on_set handler
    if cv.on_set then
      local multi_values = cv.on_set(input, self)
      if multi_values then
        self:set_multiple_config_vars(multi_values, callback)
        return
      end
    end

    -- Default single value behavior
    self:set_config_var(key, input, callback)
  end)
end

--- Group actions by heading into sections
---@return table[] Array of {heading: string|nil, actions: PopupAction[]}
function PopupData:_group_actions_by_heading()
  local groups = {}
  local current_group = nil

  for _, item in ipairs(self.actions) do
    if item.type == "heading" then
      if current_group then
        table.insert(groups, current_group)
      end
      current_group = { heading = item.text, actions = {} }
    elseif item.type == "action" then
      if not current_group then
        current_group = { heading = nil, actions = {} }
      end
      table.insert(current_group.actions, item)
    end
  end

  if current_group then
    table.insert(groups, current_group)
  end

  return groups
end

--- Get display width of a string (accounts for multi-byte UTF-8 characters)
---@param str string
---@return number display_width
local function display_width(str)
  -- Use vim.fn.strdisplaywidth if available, otherwise approximate
  if vim.fn and vim.fn.strdisplaywidth then
    return vim.fn.strdisplaywidth(str)
  end
  -- Fallback: count UTF-8 characters (not perfect but better than byte length)
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

--- Render a single group as lines
---@param group table {heading: string|nil, actions: PopupAction[]}
---@return string[] lines
---@return number max_width Maximum display width in this group
function PopupData:_render_group(group)
  local lines = {}
  local max_width = 0

  if group.heading then
    table.insert(lines, group.heading)
    max_width = display_width(group.heading)
  end

  for _, action in ipairs(group.actions) do
    local line = string.format(" %s %s", action.key, action.description)
    table.insert(lines, line)
    max_width = math.max(max_width, display_width(line))
  end

  return lines, max_width
end

--- Format a config value for display
---@param cv PopupConfigVar
---@return string
local function format_config_value(cv)
  if cv.var_type == "cycle" and cv.choices then
    -- Format as [opt1|opt2|default:X] with markers for current value
    local parts = {}
    local current = cv.current_value
    for _, choice in ipairs(cv.choices) do
      if choice == "" then
        -- Empty string means "unset" / use default
        local display = cv.default_display or "default"
        table.insert(parts, display)
      else
        table.insert(parts, choice)
      end
    end
    -- Return format: [opt1|opt2|default:X]
    -- The highlighting will mark the current one
    return "[" .. table.concat(parts, "|") .. "]"
  elseif cv.var_type == "remote_cycle" and cv.remote_choices then
    -- Format as [remote1|remote2|fallback:value] for remote cycling
    local parts = {}
    for _, remote in ipairs(cv.remote_choices) do
      table.insert(parts, remote)
    end
    -- Add fallback annotation if value comes from fallback (current is unset)
    if (cv.current_value == nil or cv.current_value == "") and cv.fallback_value then
      table.insert(parts, cv.fallback .. ":" .. cv.fallback_value)
    end
    if #parts == 0 then
      return "[]"
    end
    return "[" .. table.concat(parts, "|") .. "]"
  else
    -- Text type: show value or "unset"
    if cv.current_value == nil then
      return "unset"
    elseif cv.current_value == "" then
      return "[]"
    else
      return cv.current_value
    end
  end
end

--- Render the popup as lines of text
---@return string[]
function PopupData:render_lines()
  local lines = {}

  -- Clear positions for fresh render
  self.action_positions = {}
  self.config_positions = {}

  -- Config sections (render BEFORE Arguments)
  if self.config_vars and #self.config_vars > 0 then
    -- Calculate max label width for alignment
    local max_label_width = 0
    for _, cv in ipairs(self.config_vars) do
      if cv.type == "config_var" and cv.label then
        max_label_width = math.max(max_label_width, display_width(cv.label))
      end
    end

    for _, cv in ipairs(self.config_vars) do
      if cv.type == "config_heading" then
        -- Add blank line before heading (except first)
        if #lines > 0 then
          table.insert(lines, "")
        end
        table.insert(lines, cv.text)
      elseif cv.type == "config_var" then
        local value_display = format_config_value(cv)
        local padded_label = pad_to_width(cv.label, max_label_width)
        local line
        local line_idx = #lines + 1

        if cv.read_only or cv.key == nil then
          -- Read-only display: 3-space indent instead of keybinding
          line = string.format("   %s %s", padded_label, value_display)
          -- No config_positions entry for read-only items (no key to highlight)
        else
          line = string.format(" %s %s %s", cv.key, padded_label, value_display)
          self.config_positions[line_idx] = self.config_positions[line_idx] or {}
          self.config_positions[line_idx][cv.key] = {
            col = 1,
            len = #cv.key,
            config_key = cv.config_key,
            var_type = cv.var_type,
            choices = cv.choices,
            current_value = cv.current_value,
            default_display = cv.default_display,
            remote_choices = cv.remote_choices,
            fallback = cv.fallback,
            fallback_value = cv.fallback_value,
          }
        end
        table.insert(lines, line)
      end
    end

    -- Add blank line after config section if there's more content
    if #self.switches > 0 or #self.options > 0 or #self.actions > 0 then
      table.insert(lines, "")
    end
  end

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

  -- Actions section - single column or multi-column
  if self.columns <= 1 then
    -- Single column rendering (original behavior)
    for _, item in ipairs(self.actions) do
      if item.type == "heading" then
        table.insert(lines, item.text)
      elseif item.type == "action" then
        local line = string.format(" %s %s", item.key, item.description)
        local line_idx = #lines + 1
        self.action_positions[line_idx] = self.action_positions[line_idx] or {}
        self.action_positions[line_idx][item.key] = { col = 1, len = #item.key }
        table.insert(lines, line)
      end
    end
  else
    -- Multi-column rendering
    local groups = self:_group_actions_by_heading()
    self:_render_multicolumn(lines, groups)
  end

  return lines
end

--- Render groups in multiple columns
---@param lines string[] Output lines array (modified in place)
---@param groups table[] Array of {heading: string|nil, actions: PopupAction[]}
function PopupData:_render_multicolumn(lines, groups)
  -- Calculate line count for each group
  local group_line_counts = {}
  for i, group in ipairs(groups) do
    local count = #group.actions
    if group.heading then
      count = count + 1
    end
    group_line_counts[i] = count
  end

  -- Split groups into columns (try to balance line counts)
  local total_lines = 0
  for _, count in ipairs(group_line_counts) do
    total_lines = total_lines + count
  end

  local target_per_col = math.ceil(total_lines / self.columns)
  local column_groups = {}
  for i = 1, self.columns do
    column_groups[i] = {}
  end

  local current_col = 1
  local current_col_lines = 0
  for i, group in ipairs(groups) do
    -- If adding this group would exceed target and we're not on the last column, move to next
    if
      current_col_lines + group_line_counts[i] > target_per_col
      and current_col < self.columns
      and current_col_lines > 0
    then
      current_col = current_col + 1
      current_col_lines = 0
    end
    table.insert(column_groups[current_col], group)
    current_col_lines = current_col_lines + group_line_counts[i]
  end

  -- Render each column's groups to get lines
  local column_lines = {}
  local column_widths = {}
  for col = 1, self.columns do
    column_lines[col] = {}
    column_widths[col] = 0
    for _, group in ipairs(column_groups[col]) do
      local group_lines, max_width = self:_render_group(group)
      for _, line in ipairs(group_lines) do
        table.insert(column_lines[col], line)
      end
      column_widths[col] = math.max(column_widths[col], max_width)
    end
  end

  -- Find max lines across all columns
  local max_lines = 0
  for col = 1, self.columns do
    max_lines = math.max(max_lines, #column_lines[col])
  end

  -- Column separator
  local col_gap = "    " -- 4 spaces between columns

  -- Merge columns into output lines
  -- Track which group/action we're at for position tracking
  local col_action_indices = {}
  for col = 1, self.columns do
    col_action_indices[col] = { group_idx = 1, action_idx = 0, in_heading = true }
  end

  for row = 1, max_lines do
    local parts = {}
    -- Track byte offset for extmark positions (extmarks use bytes, not display columns)
    local current_byte_offset = 0

    for col = 1, self.columns do
      local col_line = column_lines[col][row] or ""
      local padded = pad_to_width(col_line, column_widths[col])

      -- Track action positions for highlighting
      if col_line ~= "" then
        -- Find which action this line corresponds to
        local groups_in_col = column_groups[col]
        local tracker = col_action_indices[col]
        if tracker.group_idx <= #groups_in_col then
          local group = groups_in_col[tracker.group_idx]
          if tracker.in_heading and group.heading then
            -- This is a heading line, skip to actions
            tracker.in_heading = false
            tracker.action_idx = 1
          elseif tracker.action_idx <= #group.actions then
            -- This is an action line
            local action = group.actions[tracker.action_idx]
            local line_idx = #lines + 1
            self.action_positions[line_idx] = self.action_positions[line_idx] or {}
            -- Position is: current byte offset + 1 (for leading space)
            self.action_positions[line_idx][action.key] =
              { col = current_byte_offset + 1, len = #action.key }
            tracker.action_idx = tracker.action_idx + 1
            if tracker.action_idx > #group.actions then
              -- Move to next group
              tracker.group_idx = tracker.group_idx + 1
              tracker.in_heading = true
              tracker.action_idx = 0
            end
          end
        end
      end

      table.insert(parts, padded)
      -- Update byte offset: use #padded (byte length) not display_width
      current_byte_offset = current_byte_offset + #padded + #col_gap
    end

    local combined = table.concat(parts, col_gap)
    -- Trim trailing whitespace
    combined = combined:gsub("%s+$", "")
    table.insert(lines, combined)
  end
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
  hl.apply_popup_highlights(
    self.buffer,
    lines,
    self.switches,
    self.options,
    self.actions,
    self.action_positions,
    self.config_vars,
    self.config_positions
  )

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
  hl.apply_popup_highlights(
    self.buffer,
    lines,
    self.switches,
    self.options,
    self.actions,
    self.action_positions,
    self.config_vars,
    self.config_positions
  )
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

    -- Use vim.ui.select for choice options, vim.ui.input for free-form
    if opt.choices then
      vim.ui.select(opt.choices, { prompt = opt.description .. ":" }, function(choice)
        if choice then
          self:set_option(char, choice)
          self:refresh()
        end
      end)
    else
      local current = opt.value ~= "" and opt.value or ""
      vim.ui.input({ prompt = opt.description .. ": ", default = current }, function(input)
        if input ~= nil then
          self:set_option(char, input)
          self:refresh()
        end
      end)
    end
  end, "Set option", nowait_opts)

  -- Config var keymaps (direct keys, skip read-only)
  for _, cv in ipairs(self.config_vars or {}) do
    if cv.type == "config_var" and cv.key and not cv.read_only then
      keymap.set(bufnr, "n", cv.key, function()
        if cv.var_type == "cycle" or cv.var_type == "remote_cycle" then
          self:cycle_config_var(cv.key, function(success, err)
            vim.schedule(function()
              if success then
                self:refresh()
              elseif err then
                vim.notify("[gitlad] Config error: " .. err, vim.log.levels.ERROR)
              end
            end)
          end)
        else
          -- text type
          self:prompt_config_var(cv.key, function(success, err)
            vim.schedule(function()
              if success then
                self:refresh()
              elseif err then
                vim.notify("[gitlad] Config error: " .. err, vim.log.levels.ERROR)
              end
            end)
          end)
        end
      end, cv.label or "Config", nowait_opts)
    end
  end

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
