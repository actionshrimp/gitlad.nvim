-- Tests for gitlad.ui.hl module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Clear any highlight groups that might be set
      package.loaded["gitlad.ui.hl"] = nil
    end,
  },
})

T["hl"] = MiniTest.new_set()

-- =============================================================================
-- Setup tests
-- =============================================================================

T["hl"]["setup creates highlight groups"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()

  -- Check a few key highlight groups exist
  local head_hl = vim.api.nvim_get_hl(0, { name = "GitladHead" })
  expect.equality(head_hl.link, "Title")

  local branch_hl = vim.api.nvim_get_hl(0, { name = "GitladBranch" })
  expect.equality(branch_hl.link, "Identifier")

  -- GitladDiffAdd has explicit bg color for layered highlighting
  local diff_add_hl = vim.api.nvim_get_hl(0, { name = "GitladDiffAdd" })
  expect.equality(type(diff_add_hl.bg), "number") -- bg is a color number
end

T["hl"]["setup can be called multiple times safely"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()
  hl.setup() -- Should not error

  local head_hl = vim.api.nvim_get_hl(0, { name = "GitladHead" })
  expect.equality(head_hl.link, "Title")
end

-- =============================================================================
-- Namespace tests
-- =============================================================================

T["hl"]["get_namespaces returns all namespaces"] = function()
  local hl = require("gitlad.ui.hl")
  local ns = hl.get_namespaces()

  expect.equality(type(ns.status), "number")
  expect.equality(type(ns.diff_lang), "number")
  expect.equality(type(ns.diff_markers), "number")
  expect.equality(type(ns.history), "number")
  expect.equality(type(ns.popup), "number")

  -- Each namespace should be unique
  local seen = {}
  for name, id in pairs(ns) do
    if seen[id] then
      error("Duplicate namespace ID for " .. name)
    end
    seen[id] = true
  end
end

-- =============================================================================
-- Extmark helper tests
-- =============================================================================

T["hl"]["set applies highlight to buffer range"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()
  local ns = hl.get_namespaces()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello World" })

  hl.set(bufnr, ns.status, 0, 0, 5, "GitladBranch")

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns.status, 0, -1, { details = true })
  eq(#extmarks, 1)
  eq(extmarks[1][2], 0) -- line
  eq(extmarks[1][3], 0) -- col
  eq(extmarks[1][4].end_col, 5)
  eq(extmarks[1][4].hl_group, "GitladBranch")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hl"]["set_line applies line highlight"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()
  local ns = hl.get_namespaces()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2" })

  hl.set_line(bufnr, ns.status, 0, "GitladSectionStaged")

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns.status, 0, -1, { details = true })
  eq(#extmarks, 1)
  eq(extmarks[1][4].line_hl_group, "GitladSectionStaged")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hl"]["add_virtual_text adds text at end of line"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()
  local ns = hl.get_namespaces()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Test line" })

  hl.add_virtual_text(bufnr, ns.status, 0, " (no parser)", "GitladDiffNoParser")

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns.status, 0, -1, { details = true })
  eq(#extmarks, 1)
  eq(extmarks[1][4].virt_text[1][1], " (no parser)")
  eq(extmarks[1][4].virt_text[1][2], "GitladDiffNoParser")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hl"]["clear removes highlights from buffer"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()
  local ns = hl.get_namespaces()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Test line" })

  -- Add some highlights
  hl.set(bufnr, ns.status, 0, 0, 4, "GitladBranch")
  hl.set_line(bufnr, ns.status, 0, "GitladSectionStaged")

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns.status, 0, -1, {})
  eq(#extmarks, 2)

  -- Clear
  hl.clear(bufnr, ns.status)

  extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns.status, 0, -1, {})
  eq(#extmarks, 0)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hl"]["clear accepts namespace name string"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()
  local ns = hl.get_namespaces()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Test line" })

  hl.set(bufnr, ns.status, 0, 0, 4, "GitladBranch")

  -- Clear using string name
  hl.clear(bufnr, "status")

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns.status, 0, -1, {})
  eq(#extmarks, 0)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- =============================================================================
-- Language detection tests
-- =============================================================================

T["hl"]["get_lang_for_path returns correct language for common extensions"] = function()
  local hl = require("gitlad.ui.hl")

  eq(hl.get_lang_for_path("test.lua"), "lua")
  eq(hl.get_lang_for_path("test.py"), "python")
  eq(hl.get_lang_for_path("test.js"), "javascript")
  eq(hl.get_lang_for_path("test.ts"), "typescript")
  eq(hl.get_lang_for_path("test.tsx"), "tsx")
  eq(hl.get_lang_for_path("test.rs"), "rust")
  eq(hl.get_lang_for_path("test.go"), "go")
  eq(hl.get_lang_for_path("test.rb"), "ruby")
  eq(hl.get_lang_for_path("test.json"), "json")
  eq(hl.get_lang_for_path("test.yaml"), "yaml")
  eq(hl.get_lang_for_path("test.yml"), "yaml")
  eq(hl.get_lang_for_path("test.md"), "markdown")
end

T["hl"]["get_lang_for_path handles paths with directories"] = function()
  local hl = require("gitlad.ui.hl")

  eq(hl.get_lang_for_path("/foo/bar/test.lua"), "lua")
  eq(hl.get_lang_for_path("src/components/App.tsx"), "tsx")
  eq(hl.get_lang_for_path("./relative/path.py"), "python")
end

T["hl"]["get_lang_for_path handles uppercase extensions"] = function()
  local hl = require("gitlad.ui.hl")

  eq(hl.get_lang_for_path("test.LUA"), "lua")
  eq(hl.get_lang_for_path("test.PY"), "python")
end

T["hl"]["get_lang_for_path returns nil for unknown extensions"] = function()
  local hl = require("gitlad.ui.hl")

  eq(hl.get_lang_for_path("test.xyz123unknown"), nil)
  eq(hl.get_lang_for_path("noextension"), nil)
  eq(hl.get_lang_for_path(""), nil)
  eq(hl.get_lang_for_path(nil), nil)
end

T["hl"]["get_lang_for_path handles files with multiple dots"] = function()
  local hl = require("gitlad.ui.hl")

  eq(hl.get_lang_for_path("test.config.lua"), "lua")
  eq(hl.get_lang_for_path("app.test.ts"), "typescript")
  eq(hl.get_lang_for_path("file.min.js"), "javascript")
end

-- =============================================================================
-- Parser availability tests
-- =============================================================================

T["hl"]["parser_available returns true for lua"] = function()
  local hl = require("gitlad.ui.hl")
  -- Lua parser should always be available in nvim test environment
  eq(hl.parser_available("lua"), true)
end

T["hl"]["parser_available returns false for nonexistent language"] = function()
  local hl = require("gitlad.ui.hl")
  eq(hl.parser_available("nonexistent_lang_xyz123"), false)
end

T["hl"]["parser_available returns false for nil"] = function()
  local hl = require("gitlad.ui.hl")
  eq(hl.parser_available(nil), false)
end

-- =============================================================================
-- Highlight query tests
-- =============================================================================

T["hl"]["get_highlight_query returns query for lua"] = function()
  local hl = require("gitlad.ui.hl")
  local query = hl.get_highlight_query("lua")
  -- Should return a query object, not nil
  if query == nil then
    error("Expected highlight query for lua")
  end
end

T["hl"]["get_highlight_query returns nil for unknown language"] = function()
  local hl = require("gitlad.ui.hl")
  local query = hl.get_highlight_query("nonexistent_lang_xyz123")
  eq(query, nil)
end

T["hl"]["get_highlight_query returns nil when parser unavailable"] = function()
  local hl = require("gitlad.ui.hl")
  local query = hl.get_highlight_query(nil)
  eq(query, nil)
end

-- =============================================================================
-- Treesitter diff highlighting tests
-- =============================================================================

T["hl"]["highlight_diff_content applies highlights to correct lines"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()

  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = {
    "  @@ -0,0 +1,3 @@",
    "  +local x = 1",
    "  +local y = 2",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Apply treesitter highlighting
  local success = hl.highlight_diff_content(bufnr, lines, 0, "test.lua")
  eq(success, true)

  -- Get extmarks
  local ns = hl.get_namespaces().diff_lang
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

  -- Should have some highlights
  expect.equality(#marks > 0, true)

  -- Find the highlight for "local" keyword on line 1 (0-indexed)
  -- Line 1 is "  +local x = 1" - "local" should be at columns 3-8
  local found_local_line1 = false
  for _, m in ipairs(marks) do
    if m[2] == 1 and m[3] == 3 and m[4].end_col == 8 then
      found_local_line1 = true
      break
    end
  end
  expect.equality(found_local_line1, true)

  -- Find the highlight for "local" keyword on line 2 (0-indexed)
  -- Line 2 is "  +local y = 2" - "local" should be at columns 3-8
  local found_local_line2 = false
  for _, m in ipairs(marks) do
    if m[2] == 2 and m[3] == 3 and m[4].end_col == 8 then
      found_local_line2 = true
      break
    end
  end
  expect.equality(found_local_line2, true)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hl"]["highlight_diff_content handles hunk headers correctly"] = function()
  local hl = require("gitlad.ui.hl")
  hl.setup()

  local bufnr = vim.api.nvim_create_buf(false, true)
  -- Multiple hunks
  local lines = {
    "  @@ -1,1 +1,2 @@",
    "  +local a = 1",
    "  @@ -10,1 +11,2 @@",
    "  +local b = 2",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local success = hl.highlight_diff_content(bufnr, lines, 0, "test.lua")
  eq(success, true)

  local ns = hl.get_namespaces().diff_lang
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

  -- Should have highlights
  expect.equality(#marks > 0, true)

  -- "local" on line 1 (after first hunk header)
  local found_line1 = false
  for _, m in ipairs(marks) do
    if m[2] == 1 and m[3] == 3 and m[4].end_col == 8 then
      found_line1 = true
      break
    end
  end
  expect.equality(found_line1, true)

  -- "local" on line 3 (after second hunk header)
  local found_line3 = false
  for _, m in ipairs(marks) do
    if m[2] == 3 and m[3] == 3 and m[4].end_col == 8 then
      found_line3 = true
      break
    end
  end
  expect.equality(found_line3, true)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
