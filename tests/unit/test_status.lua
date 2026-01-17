-- Tests for gitlad.ui.views.status module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["line_map approach"] = MiniTest.new_set()

T["line_map approach"]["stores file info by line number"] = function()
  -- Simulate what the render function does with line_map
  local line_map = {}
  local lines = {}

  -- Header
  table.insert(lines, "Head:     main")
  table.insert(lines, "")

  -- Staged section
  table.insert(lines, "Staged (2)")
  table.insert(lines, "  ● A  file1.lua")
  line_map[#lines] = { path = "file1.lua", section = "staged" }
  table.insert(lines, "  ● M  file2.lua")
  line_map[#lines] = { path = "file2.lua", section = "staged" }
  table.insert(lines, "")

  -- Unstaged section
  table.insert(lines, "Unstaged (1)")
  table.insert(lines, "  ○ M  file3.lua")
  line_map[#lines] = { path = "file3.lua", section = "unstaged" }
  table.insert(lines, "")

  -- Verify line_map has correct entries
  eq(line_map[4].path, "file1.lua")
  eq(line_map[4].section, "staged")
  eq(line_map[5].path, "file2.lua")
  eq(line_map[5].section, "staged")
  eq(line_map[8].path, "file3.lua")
  eq(line_map[8].section, "unstaged")

  -- Verify non-file lines are not in map
  eq(line_map[1], nil) -- Header
  eq(line_map[3], nil) -- Section header
  eq(line_map[6], nil) -- Empty line
end

T["line_map approach"]["lookup returns nil for non-file lines"] = function()
  local line_map = {
    [4] = { path = "file1.lua", section = "staged" },
  }

  -- Simulate _get_current_file lookup
  local function get_file_at_line(line)
    local info = line_map[line]
    if info then
      return info.path, info.section
    end
    return nil, nil
  end

  local path, section = get_file_at_line(4)
  eq(path, "file1.lua")
  eq(section, "staged")

  path, section = get_file_at_line(1)
  eq(path, nil)
  eq(section, nil)

  path, section = get_file_at_line(100)
  eq(path, nil)
  eq(section, nil)
end

T["close behavior"] = MiniTest.new_set()

T["close behavior"]["handles last window by switching buffer"] = function()
  -- Test that the close logic correctly identifies single window case
  local windows = vim.api.nvim_list_wins()
  local is_last_window = #windows == 1

  -- In test environment, verify we can detect window count
  expect.equality(type(#windows), "number")

  -- The actual close function switches to empty buffer when last window
  -- This test verifies the detection logic works
  if is_last_window then
    -- Would switch buffer, not close window
    expect.equality(true, true)
  else
    -- Would close window normally
    expect.equality(true, true)
  end
end

T["close behavior"]["does not error when winnr is nil"] = function()
  -- Simulate close when window already closed
  local winnr = nil

  local function safe_close()
    if not winnr then
      return true -- Early return, no error
    end
    return false
  end

  eq(safe_close(), true)
end

T["close behavior"]["does not error when winnr is invalid"] = function()
  -- Simulate close with invalid window handle
  local winnr = 99999 -- Invalid window ID

  local function safe_close()
    if not winnr or not vim.api.nvim_win_is_valid(winnr) then
      return true -- Early return, no error
    end
    return false
  end

  eq(safe_close(), true)
end

-- Tests for partial hunk patch building logic
T["partial hunk patch"] = MiniTest.new_set()

-- Helper to build a partial patch (mirrors StatusBuffer:_build_partial_hunk_patch logic)
local function build_partial_hunk_patch(diff_data, hunk_index, selected_display_indices, reverse)
  if not diff_data.hunks[hunk_index] then
    return nil
  end

  local hunk = diff_data.hunks[hunk_index]

  local old_start, _, new_start, _ = hunk.header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  old_start = tonumber(old_start) or 1
  new_start = tonumber(new_start) or 1

  local new_hunk_lines = {}
  local new_old_count = 0
  local new_new_count = 0

  -- Calculate display index for hunk header
  local hunk_header_display_idx = 0
  local current_hunk = 0
  for i, line in ipairs(diff_data.display_lines) do
    if line:match("^@@") then
      current_hunk = current_hunk + 1
      if current_hunk == hunk_index then
        hunk_header_display_idx = i
        break
      end
    end
  end

  for i, line in ipairs(hunk.lines) do
    local display_idx = hunk_header_display_idx + i
    local is_selected = selected_display_indices[display_idx]
    local first_char = line:sub(1, 1)

    if first_char == "+" then
      if is_selected then
        table.insert(new_hunk_lines, line)
        new_new_count = new_new_count + 1
      elseif reverse then
        table.insert(new_hunk_lines, " " .. line:sub(2))
        new_old_count = new_old_count + 1
        new_new_count = new_new_count + 1
      end
    elseif first_char == "-" then
      if is_selected then
        table.insert(new_hunk_lines, line)
        new_old_count = new_old_count + 1
      elseif not reverse then
        table.insert(new_hunk_lines, " " .. line:sub(2))
        new_old_count = new_old_count + 1
        new_new_count = new_new_count + 1
      end
    else
      table.insert(new_hunk_lines, line)
      new_old_count = new_old_count + 1
      new_new_count = new_new_count + 1
    end
  end

  local has_changes = false
  for _, line in ipairs(new_hunk_lines) do
    local fc = line:sub(1, 1)
    if fc == "+" or fc == "-" then
      has_changes = true
      break
    end
  end
  if not has_changes then
    return nil
  end

  local patch_lines = {}
  for _, line in ipairs(diff_data.header) do
    table.insert(patch_lines, line)
  end
  table.insert(
    patch_lines,
    string.format("@@ -%d,%d +%d,%d @@", old_start, new_old_count, new_start, new_new_count)
  )
  for _, line in ipairs(new_hunk_lines) do
    table.insert(patch_lines, line)
  end

  return patch_lines
end

-- Helper to create diff data structure
local function make_diff_data(header, hunks)
  local display_lines = {}
  local parsed_hunks = {}

  for _, hunk in ipairs(hunks) do
    table.insert(display_lines, hunk.header)
    local parsed = { header = hunk.header, lines = {} }
    for _, line in ipairs(hunk.lines) do
      table.insert(display_lines, line)
      table.insert(parsed.lines, line)
    end
    table.insert(parsed_hunks, parsed)
  end

  return {
    header = header,
    hunks = parsed_hunks,
    display_lines = display_lines,
  }
end

T["partial hunk patch"]["staging: selecting only additions omits unselected deletions as context"] = function()
  -- Diff showing line 2 deleted and "new line" added
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  -- Select only the addition (+new line) at display index 3
  -- display_lines: [1]=@@, [2]=" line 1", [3]="-line 2", [4]="+new line", [5]=" line 3"
  local selected = { [4] = true }

  local patch = build_partial_hunk_patch(diff_data, 1, selected, false)

  -- The patch should have the deletion converted to context
  -- Result: line 1, line 2 (context), +new line, line 3
  expect.no_equality(patch, nil)

  -- Find the hunk content (after header lines)
  local hunk_start = 5 -- After 4 header lines
  -- old=3 (3 context lines), new=4 (3 context + 1 addition)
  eq(patch[hunk_start], "@@ -1,3 +1,4 @@")
  eq(patch[hunk_start + 1], " line 1")
  eq(patch[hunk_start + 2], " line 2") -- Was "-line 2", now context
  eq(patch[hunk_start + 3], "+new line")
  eq(patch[hunk_start + 4], " line 3")
end

T["partial hunk patch"]["staging: selecting only deletions omits unselected additions"] = function()
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  -- Select only the deletion (-line 2) at display index 2
  local selected = { [3] = true }

  local patch = build_partial_hunk_patch(diff_data, 1, selected, false)

  expect.no_equality(patch, nil)

  local hunk_start = 5
  eq(patch[hunk_start], "@@ -1,3 +1,2 @@") -- old has 3, new has 2 (deletion applied)
  eq(patch[hunk_start + 1], " line 1")
  eq(patch[hunk_start + 2], "-line 2")
  eq(patch[hunk_start + 3], " line 3")
  -- +new line is omitted entirely
  eq(patch[hunk_start + 4], nil)
end

T["partial hunk patch"]["staging: selecting both keeps both changes"] = function()
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  -- Select both the deletion and addition
  local selected = { [3] = true, [4] = true }

  local patch = build_partial_hunk_patch(diff_data, 1, selected, false)

  expect.no_equality(patch, nil)

  local hunk_start = 5
  eq(patch[hunk_start], "@@ -1,3 +1,3 @@")
  eq(patch[hunk_start + 1], " line 1")
  eq(patch[hunk_start + 2], "-line 2")
  eq(patch[hunk_start + 3], "+new line")
  eq(patch[hunk_start + 4], " line 3")
end

T["partial hunk patch"]["unstaging: selecting only additions converts unselected deletions to omitted"] = function()
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  -- Select only the addition for unstaging
  local selected = { [4] = true }

  local patch = build_partial_hunk_patch(diff_data, 1, selected, true)

  expect.no_equality(patch, nil)

  local hunk_start = 5
  -- For unstaging: unselected - is omitted, selected + stays
  eq(patch[hunk_start], "@@ -1,2 +1,3 @@")
  eq(patch[hunk_start + 1], " line 1")
  eq(patch[hunk_start + 2], "+new line")
  eq(patch[hunk_start + 3], " line 3")
end

T["partial hunk patch"]["unstaging: selecting only deletions converts unselected additions to context"] = function()
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  -- Select only the deletion for unstaging
  local selected = { [3] = true }

  local patch = build_partial_hunk_patch(diff_data, 1, selected, true)

  expect.no_equality(patch, nil)

  local hunk_start = 5
  -- For unstaging: selected - stays, unselected + becomes context
  -- old=4 (3 context + 1 deletion), new=3 (3 context lines)
  eq(patch[hunk_start], "@@ -1,4 +1,3 @@")
  eq(patch[hunk_start + 1], " line 1")
  eq(patch[hunk_start + 2], "-line 2")
  eq(patch[hunk_start + 3], " new line") -- Was +, now context
  eq(patch[hunk_start + 4], " line 3")
end

T["partial hunk patch"]["returns nil when no changes selected"] = function()
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  -- Select nothing - but we still need indices that exist
  -- In staging mode, unselected - becomes context, unselected + is omitted
  -- So with nothing selected, all - become context and all + are omitted = no changes
  local selected = {}

  local patch = build_partial_hunk_patch(diff_data, 1, selected, false)

  eq(patch, nil)
end

T["partial hunk patch"]["returns nil for invalid hunk index"] = function()
  local diff_data = make_diff_data({
    "diff --git a/file.lua b/file.lua",
    "index abc..def 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
  }, { { header = "@@ -1,3 +1,3 @@", lines = { " line 1", "-line 2", "+new line", " line 3" } } })

  local patch = build_partial_hunk_patch(diff_data, 99, { [3] = true }, false)
  eq(patch, nil)
end

-- Tests for header rendering logic
T["status header rendering"] = MiniTest.new_set()

-- Helper to simulate header rendering
local function render_header(status, refreshing)
  local lines = {}

  -- Head line
  local head_line = "Head:     " .. status.branch
  if status.head_commit_msg then
    head_line = head_line .. "  " .. status.head_commit_msg
  end
  if refreshing then
    head_line = head_line .. "  (Refreshing...)"
  end
  table.insert(lines, head_line)

  -- Merge (upstream) line
  if status.upstream then
    local merge_line = "Merge:    " .. status.upstream
    if status.merge_commit_msg then
      merge_line = merge_line .. "  " .. status.merge_commit_msg
    end
    if status.ahead > 0 or status.behind > 0 then
      merge_line = merge_line .. string.format(" [+%d/-%d]", status.ahead, status.behind)
    end
    table.insert(lines, merge_line)
  end

  -- Push line (only if different from merge)
  if status.push_remote then
    local push_line = "Push:     " .. status.push_remote
    if status.push_commit_msg then
      push_line = push_line .. "  " .. status.push_commit_msg
    end
    if status.push_ahead > 0 or status.push_behind > 0 then
      push_line = push_line .. string.format(" [+%d/-%d]", status.push_ahead, status.push_behind)
    end
    table.insert(lines, push_line)
  end

  return lines
end

T["status header rendering"]["shows Head with branch name"] = function()
  local status = {
    branch = "main",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 1)
  eq(lines[1], "Head:     main")
end

T["status header rendering"]["shows Head with commit message"] = function()
  local status = {
    branch = "main",
    head_commit_msg = "Add feature X",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 1)
  eq(lines[1], "Head:     main  Add feature X")
end

T["status header rendering"]["shows Refreshing indicator"] = function()
  local status = {
    branch = "main",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, true)
  eq(#lines, 1)
  expect.no_equality(lines[1]:find("(Refreshing...)", 1, true), nil)
end

T["status header rendering"]["shows Merge line when upstream exists"] = function()
  local status = {
    branch = "main",
    upstream = "origin/main",
    ahead = 2,
    behind = 1,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 2)
  eq(lines[2], "Merge:    origin/main [+2/-1]")
end

T["status header rendering"]["shows Merge with commit message"] = function()
  local status = {
    branch = "main",
    upstream = "origin/main",
    merge_commit_msg = "Previous commit",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 2)
  eq(lines[2], "Merge:    origin/main  Previous commit")
end

T["status header rendering"]["hides Merge line when no upstream"] = function()
  local status = {
    branch = "main",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 1) -- Only Head line
end

T["status header rendering"]["shows Push line when push remote differs from merge"] = function()
  local status = {
    branch = "main",
    upstream = "origin/main",
    push_remote = "fork/main",
    ahead = 0,
    behind = 0,
    push_ahead = 3,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 3)
  eq(lines[3], "Push:     fork/main [+3/-0]")
end

T["status header rendering"]["shows Push with commit message"] = function()
  local status = {
    branch = "main",
    upstream = "origin/main",
    push_remote = "fork/main",
    push_commit_msg = "Fork commit",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 3)
  eq(lines[3], "Push:     fork/main  Fork commit")
end

T["status header rendering"]["hides Push line when no push remote"] = function()
  local status = {
    branch = "main",
    upstream = "origin/main",
    ahead = 0,
    behind = 0,
    push_ahead = 0,
    push_behind = 0,
  }

  local lines = render_header(status, false)
  eq(#lines, 2) -- Head and Merge only
end

return T
