-- Tests for gitlad.ui.views.status_cursor module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

-- Lazy-load the module under test
local function get_cursor_mod()
  return require("gitlad.ui.views.status_cursor")
end

-- Helper: build a mock StatusBuffer with line_map and section_lines
local function mock_buffer(opts)
  opts = opts or {}
  return {
    line_map = opts.line_map or {},
    section_lines = opts.section_lines or {},
    expanded_files = opts.expanded_files or {},
    expanded_commits = opts.expanded_commits or {},
    diff_cache = opts.diff_cache or {},
    remembered_file_states = opts.remembered_file_states or {},
    repo_state = opts.repo_state or { status = opts.status or {} },
    winnr = opts.winnr,
    bufnr = opts.bufnr,
  }
end

-- =============================================================================
-- save_cursor_identity tests
-- =============================================================================

T["save_cursor_identity"] = MiniTest.new_set()

T["save_cursor_identity"]["returns nil for invalid window"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({ winnr = nil })
  local result = mod._save_cursor_identity(buf)
  eq(result, nil)
end

T["save_cursor_identity"]["returns nil for non-existent window"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({ winnr = 99999 })
  local result = mod._save_cursor_identity(buf)
  eq(result, nil)
end

T["save_cursor_identity"]["identifies section header"] = function()
  local mod = get_cursor_mod()
  -- Create a real buffer and window for testing
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "Unstaged (1)", "line3" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    section_lines = {
      [2] = { name = "Unstaged", section = "unstaged" },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "section")
  eq(result.section_key, "unstaged")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies file line"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "section", "  M file.txt" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 3, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [3] = { type = "file", path = "file.txt", section = "unstaged" },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "file")
  eq(result.path, "file.txt")
  eq(result.section_key, "unstaged")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies hunk header"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "file", "@@ -1,3 +1,3 @@" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 3, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [3] = {
        type = "file",
        path = "file.txt",
        section = "unstaged",
        hunk_index = 1,
        is_hunk_header = true,
      },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "hunk_header")
  eq(result.path, "file.txt")
  eq(result.hunk_index, 1)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies diff content line with offset"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(
    bufnr,
    0,
    -1,
    false,
    { "file", "@@ header", " context", "-old", "+new" }
  )
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 5, 0 }) -- on "+new" line

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [1] = { type = "file", path = "file.txt", section = "unstaged" },
      [2] = {
        type = "file",
        path = "file.txt",
        section = "unstaged",
        hunk_index = 1,
        is_hunk_header = true,
      },
      [3] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
      [4] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
      [5] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "diff_line")
  eq(result.path, "file.txt")
  eq(result.hunk_index, 1)
  eq(result.line_in_hunk, 3) -- 3 lines after hunk header

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies commit"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "abc1234 commit msg" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [2] = {
        type = "commit",
        section = "recent",
        commit = { hash = "abc1234567890" },
      },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "commit")
  eq(result.hash, "abc1234567890")
  eq(result.section_key, "recent")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies stash"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "stash@{0} WIP" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [2] = {
        type = "stash",
        section = "stashes",
        stash = { ref = "stash@{0}", message = "WIP" },
      },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "stash")
  eq(result.stash_ref, "stash@{0}")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies submodule"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "  sub/path" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [2] = {
        type = "submodule",
        section = "submodules",
        submodule = { path = "sub/path" },
      },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "submodule")
  eq(result.submodule_path, "sub/path")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies worktree"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "main  /path/to/wt" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [2] = {
        type = "worktree",
        section = "worktrees",
        worktree = { path = "/path/to/wt" },
      },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "worktree")
  eq(result.worktree_path, "/path/to/wt")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["identifies rebase_commit"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "pick abc1234 msg" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
    line_map = {
      [2] = {
        type = "rebase_commit",
        hash = "abc1234",
        rebase_state = "todo",
        action = "pick",
      },
    },
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "rebase_commit")
  eq(result.hash, "abc1234")
  eq(result.rebase_state, "todo")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["save_cursor_identity"]["returns fallback for blank lines"] = function()
  local mod = get_cursor_mod()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "", "something" })
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_cursor(winnr, { 2, 0 })

  local buf = mock_buffer({
    winnr = winnr,
    bufnr = bufnr,
  })
  local result = mod._save_cursor_identity(buf)
  eq(result.type, "fallback")
  eq(result.raw_line, 2)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- =============================================================================
-- find_cursor_target tests
-- =============================================================================

T["find_cursor_target"] = MiniTest.new_set()

T["find_cursor_target"]["exact match for file"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "file.txt", section = "unstaged" },
      [8] = { type = "file", path = "other.txt", section = "unstaged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "file",
    section_key = "unstaged",
    path = "file.txt",
  })
  eq(result, 5)
end

T["find_cursor_target"]["exact match for section"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    section_lines = {
      [3] = { name = "Unstaged", section = "unstaged" },
      [10] = { name = "Staged", section = "staged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "section",
    section_key = "staged",
  })
  eq(result, 10)
end

T["find_cursor_target"]["exact match for commit"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [7] = { type = "commit", section = "recent", commit = { hash = "abc123" } },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "commit",
    section_key = "recent",
    hash = "abc123",
  })
  eq(result, 7)
end

T["find_cursor_target"]["cross-section fallback (file moved)"] = function()
  local mod = get_cursor_mod()
  -- File was in unstaged, now it's in staged (after staging), no siblings remain
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "file.txt", section = "staged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "file",
    section_key = "unstaged",
    path = "file.txt",
  })
  eq(result, 5) -- Found in staged section
end

T["find_cursor_target"]["sibling in same section wins over cross-section"] = function()
  local mod = get_cursor_mod()
  -- file.txt was staged, but other.txt remains in unstaged. Also file.txt exists in staged.
  -- Nearest sibling (same section) should win over cross-section match.
  local buf = mock_buffer({
    line_map = {
      [3] = { type = "file", path = "file.txt", section = "staged" },
      [6] = { type = "file", path = "other.txt", section = "unstaged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "file",
    section_key = "unstaged",
    path = "file.txt",
  })
  eq(result, 6) -- Stays in unstaged section on sibling, not following to staged
end

T["find_cursor_target"]["parent fallback (hunk gone, file remains)"] = function()
  local mod = get_cursor_mod()
  -- Cursor was on hunk header, but diff collapsed. File line still exists.
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "file.txt", section = "unstaged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "hunk_header",
    section_key = "unstaged",
    path = "file.txt",
    hunk_index = 1,
  })
  eq(result, 5) -- Falls back to file line
end

T["find_cursor_target"]["parent fallback for diff_line"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "file.txt", section = "unstaged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "diff_line",
    section_key = "unstaged",
    path = "file.txt",
    hunk_index = 1,
    line_in_hunk = 3,
  })
  eq(result, 5) -- Falls back to file line
end

T["find_cursor_target"]["sibling fallback (file gone)"] = function()
  local mod = get_cursor_mod()
  -- file.txt was committed and gone from unstaged, but other.txt remains
  local buf = mock_buffer({
    line_map = {
      [6] = { type = "file", path = "other.txt", section = "unstaged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "file",
    section_key = "unstaged",
    path = "file.txt",
  })
  eq(result, 6) -- Falls back to sibling in same section
end

T["find_cursor_target"]["section header fallback"] = function()
  local mod = get_cursor_mod()
  -- All files gone from unstaged, but section header remains
  local buf = mock_buffer({
    section_lines = {
      [3] = { name = "Unstaged", section = "unstaged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "file",
    section_key = "unstaged",
    path = "file.txt",
  })
  eq(result, 3) -- Falls back to section header
end

T["find_cursor_target"]["nearest section fallback"] = function()
  local mod = get_cursor_mod()
  -- Section completely gone, only other sections remain
  local buf = mock_buffer({
    section_lines = {
      [3] = { name = "Staged", section = "staged" },
      [10] = { name = "Recent", section = "recent" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "file",
    section_key = "unstaged",
    path = "file.txt",
    raw_line = nil,
  })
  -- Should find nearest section header (section_key falls back to nearest)
  expect.no_equality(result, nil)
end

T["find_cursor_target"]["first item fallback on empty buffer"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "only.txt", section = "staged" },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "fallback",
    raw_line = 50,
  })
  -- No section_lines, raw_line won't find sections, falls back to first item
  eq(result, 5)
end

T["find_cursor_target"]["returns nil for nil identity"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer()
  local result = mod._find_cursor_target(buf, nil)
  eq(result, nil)
end

T["find_cursor_target"]["diff_line exact match with offset"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [10] = {
        type = "file",
        path = "file.txt",
        section = "unstaged",
        hunk_index = 1,
        is_hunk_header = true,
      },
      [11] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
      [12] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
      [13] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "diff_line",
    section_key = "unstaged",
    path = "file.txt",
    hunk_index = 1,
    line_in_hunk = 2,
  })
  eq(result, 12) -- hunk header at 10 + offset 2 = 12
end

T["find_cursor_target"]["diff_line clamps to end of hunk when offset exceeds"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [10] = {
        type = "file",
        path = "file.txt",
        section = "unstaged",
        hunk_index = 1,
        is_hunk_header = true,
      },
      [11] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
      [12] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
    },
  })
  local result = mod._find_cursor_target(buf, {
    type = "diff_line",
    section_key = "unstaged",
    path = "file.txt",
    hunk_index = 1,
    line_in_hunk = 10, -- Way past end
  })
  eq(result, 12) -- Clamped to last line of hunk
end

-- =============================================================================
-- cleanup_stale_expansion tests
-- =============================================================================

T["cleanup_stale_expansion"] = MiniTest.new_set()

T["cleanup_stale_expansion"]["removes stale file entries"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    status = {
      staged = { { path = "kept.txt" } },
      unstaged = {},
      untracked = {},
      conflicted = {},
    },
    expanded_files = {
      ["staged:kept.txt"] = true,
      ["unstaged:gone.txt"] = true, -- This file no longer exists
    },
    diff_cache = {
      ["staged:kept.txt"] = { hunks = {} },
      ["unstaged:gone.txt"] = { hunks = {} }, -- Stale
    },
    remembered_file_states = {
      ["staged:kept.txt"] = {},
      ["unstaged:gone.txt"] = {}, -- Stale
    },
  })
  mod._cleanup_stale_expansion(buf)
  eq(buf.expanded_files["staged:kept.txt"], true)
  eq(buf.expanded_files["unstaged:gone.txt"], nil)
  expect.no_equality(buf.diff_cache["staged:kept.txt"], nil)
  eq(buf.diff_cache["unstaged:gone.txt"], nil)
  expect.no_equality(buf.remembered_file_states["staged:kept.txt"], nil)
  eq(buf.remembered_file_states["unstaged:gone.txt"], nil)
end

T["cleanup_stale_expansion"]["removes stale commit entries"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    status = {
      staged = {},
      unstaged = {},
      untracked = {},
      conflicted = {},
      recent = { { hash = "abc123" } },
    },
    expanded_commits = {
      ["abc123"] = true,
      ["def456"] = true, -- Stale
    },
  })
  mod._cleanup_stale_expansion(buf)
  eq(buf.expanded_commits["abc123"], true)
  eq(buf.expanded_commits["def456"], nil)
end

T["cleanup_stale_expansion"]["keeps submodule entries"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    status = {
      staged = {},
      unstaged = {},
      untracked = {},
      conflicted = {},
      submodules = { { path = "sub/mod" } },
    },
    expanded_files = {
      ["submodule:sub/mod"] = true,
      ["submodule:gone/mod"] = true, -- Stale
    },
  })
  mod._cleanup_stale_expansion(buf)
  eq(buf.expanded_files["submodule:sub/mod"], true)
  eq(buf.expanded_files["submodule:gone/mod"], nil)
end

T["cleanup_stale_expansion"]["handles nil status gracefully"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    expanded_files = { ["unstaged:file.txt"] = true },
  })
  buf.repo_state.status = nil
  -- Should not error
  mod._cleanup_stale_expansion(buf)
  -- State unchanged when status is nil
  eq(buf.expanded_files["unstaged:file.txt"], true)
end

T["cleanup_stale_expansion"]["handles empty status"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    status = {
      staged = {},
      unstaged = {},
      untracked = {},
      conflicted = {},
    },
    expanded_files = {
      ["unstaged:file.txt"] = true,
    },
    expanded_commits = {
      ["abc123"] = true,
    },
  })
  mod._cleanup_stale_expansion(buf)
  eq(buf.expanded_files["unstaged:file.txt"], nil)
  eq(buf.expanded_commits["abc123"], nil)
end

-- =============================================================================
-- Helper function tests
-- =============================================================================

T["helpers"] = MiniTest.new_set()

T["helpers"]["find_nearest_section finds closest section"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    section_lines = {
      [3] = { name = "Unstaged", section = "unstaged" },
      [10] = { name = "Staged", section = "staged" },
      [20] = { name = "Recent", section = "recent" },
    },
  })
  eq(mod._find_nearest_section(buf, 8), 10)
  eq(mod._find_nearest_section(buf, 1), 3)
  eq(mod._find_nearest_section(buf, 25), 20)
end

T["helpers"]["find_nearest_section returns nil for empty sections"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer()
  eq(mod._find_nearest_section(buf, 5), nil)
end

T["helpers"]["find_first_item returns smallest line number"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [10] = { type = "file", path = "b.txt", section = "unstaged" },
      [5] = { type = "file", path = "a.txt", section = "unstaged" },
      [15] = { type = "file", path = "c.txt", section = "unstaged" },
    },
  })
  eq(mod._find_first_item(buf), 5)
end

T["helpers"]["find_first_item returns nil for empty line_map"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer()
  eq(mod._find_first_item(buf), nil)
end

T["helpers"]["find_file_any_section skips hunk lines"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "file.txt", section = "unstaged", hunk_index = 1 },
      [3] = { type = "file", path = "file.txt", section = "staged" },
    },
  })
  eq(mod._find_file_any_section(buf, "file.txt"), 3)
end

T["helpers"]["find_nearest_sibling returns first entry in section"] = function()
  local mod = get_cursor_mod()
  local buf = mock_buffer({
    line_map = {
      [5] = { type = "file", path = "a.txt", section = "unstaged" },
      [7] = { type = "file", path = "b.txt", section = "unstaged" },
      [6] = { type = "file", path = "a.txt", section = "unstaged", hunk_index = 1 },
    },
  })
  eq(mod._find_nearest_sibling(buf, "unstaged"), 5)
end

return T
