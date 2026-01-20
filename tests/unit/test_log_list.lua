local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local log_list = require("gitlad.ui.components.log_list")

-- Test fixtures
local function make_commit(hash, subject, opts)
  opts = opts or {}
  return {
    hash = hash,
    subject = subject,
    author = opts.author,
    date = opts.date,
    body = opts.body,
    refs = opts.refs,
  }
end

local function make_ref(name, type, opts)
  opts = opts or {}
  return {
    name = name,
    type = type or "local",
    is_head = opts.is_head or false,
    is_combined = opts.is_combined or false,
  }
end

-- =============================================================================
-- render() tests
-- =============================================================================

T["render()"] = MiniTest.new_set()

T["render()"]["returns empty result for empty commits"] = function()
  local result = log_list.render({}, nil, nil)

  eq(result.lines, {})
  eq(result.line_info, {})
  eq(result.commit_ranges, {})
end

T["render()"]["renders single commit with default options"] = function()
  local commits = {
    make_commit("abc1234def5678", "Fix bug in parser"),
  }

  local result = log_list.render(commits, nil, nil)

  eq(#result.lines, 1)
  eq(result.lines[1], "  abc1234 Fix bug in parser")

  -- Check line_info
  local info = result.line_info[1]
  expect.equality(info.type, "commit")
  expect.equality(info.hash, "abc1234def5678")
  expect.equality(info.section, "log")
  expect.equality(info.expanded, false)

  -- Check commit_ranges
  local range = result.commit_ranges["abc1234def5678"]
  eq(range.start, 1)
  eq(range.end_line, 1)
end

T["render()"]["renders multiple commits"] = function()
  local commits = {
    make_commit("abc1234", "First commit"),
    make_commit("def5678", "Second commit"),
    make_commit("ghi9012", "Third commit"),
  }

  local result = log_list.render(commits, nil, nil)

  eq(#result.lines, 3)
  eq(result.lines[1], "  abc1234 First commit")
  eq(result.lines[2], "  def5678 Second commit")
  eq(result.lines[3], "  ghi9012 Third commit")

  -- Each line should have line_info
  for i = 1, 3 do
    expect.equality(result.line_info[i].type, "commit")
  end

  -- Each commit should have a range
  eq(result.commit_ranges["abc1234"].start, 1)
  eq(result.commit_ranges["def5678"].start, 2)
  eq(result.commit_ranges["ghi9012"].start, 3)
end

T["render()"]["respects indent option"] = function()
  local commits = { make_commit("abc1234", "Test") }

  local result = log_list.render(commits, nil, { indent = 4 })
  eq(result.lines[1], "    abc1234 Test")

  result = log_list.render(commits, nil, { indent = 0 })
  eq(result.lines[1], "abc1234 Test")
end

T["render()"]["respects hash_length option"] = function()
  local commits = { make_commit("abc1234def5678901234", "Test") }

  local result = log_list.render(commits, nil, { hash_length = 10 })
  eq(result.lines[1], "  abc1234def Test")

  result = log_list.render(commits, nil, { hash_length = 4 })
  eq(result.lines[1], "  abc1 Test")
end

T["render()"]["respects section option"] = function()
  local commits = { make_commit("abc1234", "Test") }

  local result = log_list.render(commits, nil, { section = "unpushed_upstream" })
  eq(result.line_info[1].section, "unpushed_upstream")
end

T["render()"]["truncates subject with max_subject_len"] = function()
  local commits =
    { make_commit("abc1234", "This is a very long commit message that should be truncated") }

  local result = log_list.render(commits, nil, { max_subject_len = 20 })
  eq(result.lines[1], "  abc1234 This is a very lo...")
end

T["render()"]["shows author when show_author is true"] = function()
  local commits = { make_commit("abc1234", "Test", { author = "John Doe" }) }

  local result = log_list.render(commits, nil, { show_author = true })
  eq(result.lines[1], "  abc1234 Test (John Doe)")
end

T["render()"]["shows date when show_date is true"] = function()
  local commits = { make_commit("abc1234", "Test", { date = "2 days ago" }) }

  local result = log_list.render(commits, nil, { show_date = true })
  eq(result.lines[1], "  abc1234 Test 2 days ago")
end

T["render()"]["shows both author and date"] = function()
  local commits = { make_commit("abc1234", "Test", { author = "Jane", date = "1 hour ago" }) }

  local result = log_list.render(commits, nil, { show_author = true, show_date = true })
  eq(result.lines[1], "  abc1234 Test (Jane) 1 hour ago")
end

-- =============================================================================
-- render() with refs tests
-- =============================================================================

T["render() refs"] = MiniTest.new_set()

T["render() refs"]["includes refs after hash when present"] = function()
  local commits = {
    make_commit("abc1234", "Fix bug", {
      refs = { make_ref("origin/main", "remote", { is_combined = true }) },
    }),
  }

  local result = log_list.render(commits, nil, nil)

  eq(result.lines[1], "  abc1234 origin/main Fix bug")
end

T["render() refs"]["omits refs when show_refs is false"] = function()
  local commits = {
    make_commit("abc1234", "Fix bug", {
      refs = { make_ref("main", "local") },
    }),
  }

  local result = log_list.render(commits, nil, { show_refs = false })

  eq(result.lines[1], "  abc1234 Fix bug")
end

T["render() refs"]["skips current branch (HEAD) refs"] = function()
  local commits = {
    make_commit("abc1234", "Fix bug", {
      refs = { make_ref("main", "local", { is_head = true }) },
    }),
  }

  local result = log_list.render(commits, nil, nil)

  -- Current branch is skipped - it's obvious from context
  eq(result.lines[1], "  abc1234 Fix bug")
end

T["render() refs"]["formats multiple refs with spaces"] = function()
  local commits = {
    make_commit("abc1234", "Fix bug", {
      refs = {
        make_ref("origin/main", "remote", { is_combined = true }),
        make_ref("origin/feature", "remote"),
      },
    }),
  }

  local result = log_list.render(commits, nil, nil)

  eq(result.lines[1], "  abc1234 origin/main origin/feature Fix bug")
end

T["render() refs"]["hides tags by default"] = function()
  local commits = {
    make_commit("abc1234", "Release", {
      refs = { make_ref("v1.0.0", "tag") },
    }),
  }

  local result = log_list.render(commits, nil, nil)

  -- Tags are hidden by default (show_tags = false)
  eq(result.lines[1], "  abc1234 Release")
end

T["render() refs"]["shows tags when show_tags option is true"] = function()
  local commits = {
    make_commit("abc1234", "Release", {
      refs = { make_ref("v1.0.0", "tag") },
    }),
  }

  local result = log_list.render(commits, nil, { show_tags = true })

  eq(result.lines[1], "  abc1234 v1.0.0 Release")
end

T["render() refs"]["handles commit without refs (empty array)"] = function()
  local commits = {
    make_commit("abc1234", "Fix bug", { refs = {} }),
  }

  local result = log_list.render(commits, nil, nil)

  eq(result.lines[1], "  abc1234 Fix bug")
end

T["render() refs"]["handles commit without refs field (nil)"] = function()
  local commits = {
    make_commit("abc1234", "Fix bug"),
  }

  local result = log_list.render(commits, nil, nil)

  eq(result.lines[1], "  abc1234 Fix bug")
end

-- =============================================================================
-- render() with expansion tests
-- =============================================================================

T["render() expansion"] = MiniTest.new_set()

T["render() expansion"]["expands commit body when hash is in expanded_hashes"] = function()
  local commits = {
    make_commit("abc1234", "Add feature", { body = "Line 1\nLine 2\nLine 3" }),
  }

  local result = log_list.render(commits, { ["abc1234"] = true }, nil)

  eq(#result.lines, 4) -- 1 main line + 3 body lines
  eq(result.lines[1], "  abc1234 Add feature")
  eq(result.lines[2], "    Line 1")
  eq(result.lines[3], "    Line 2")
  eq(result.lines[4], "    Line 3")

  -- All lines should have line_info pointing to same commit
  for i = 1, 4 do
    eq(result.line_info[i].hash, "abc1234")
    eq(result.line_info[i].type, "commit")
  end

  -- First line expanded = false (or true based on arg), body lines expanded = true
  eq(result.line_info[1].expanded, true)
  eq(result.line_info[2].expanded, true)

  -- commit_ranges should span all lines
  eq(result.commit_ranges["abc1234"].start, 1)
  eq(result.commit_ranges["abc1234"].end_line, 4)
end

T["render() expansion"]["does not expand commit without body"] = function()
  local commits = {
    make_commit("abc1234", "No body commit"),
  }

  local result = log_list.render(commits, { ["abc1234"] = true }, nil)

  eq(#result.lines, 1) -- Just the main line, no body to expand
end

T["render() expansion"]["expands only specified commits"] = function()
  local commits = {
    make_commit("abc1234", "First", { body = "Body 1" }),
    make_commit("def5678", "Second", { body = "Body 2" }),
    make_commit("ghi9012", "Third", { body = "Body 3" }),
  }

  -- Only expand the middle commit
  local result = log_list.render(commits, { ["def5678"] = true }, nil)

  eq(#result.lines, 4) -- 1 + 2 (expanded) + 1
  eq(result.lines[1], "  abc1234 First")
  eq(result.lines[2], "  def5678 Second")
  eq(result.lines[3], "    Body 2")
  eq(result.lines[4], "  ghi9012 Third")
end

-- =============================================================================
-- get_commits_in_range() tests
-- =============================================================================

T["get_commits_in_range()"] = MiniTest.new_set()

T["get_commits_in_range()"]["returns empty array for empty range"] = function()
  local result = log_list.get_commits_in_range({}, 1, 5)
  eq(result, {})
end

T["get_commits_in_range()"]["returns single commit for single line"] = function()
  local commit = make_commit("abc1234", "Test")
  local line_info = {
    [5] = { type = "commit", hash = "abc1234", commit = commit, section = "log" },
  }

  local result = log_list.get_commits_in_range(line_info, 5, 5)

  eq(#result, 1)
  eq(result[1].hash, "abc1234")
end

T["get_commits_in_range()"]["returns multiple commits for range"] = function()
  local commits = {
    make_commit("abc1234", "First"),
    make_commit("def5678", "Second"),
    make_commit("ghi9012", "Third"),
  }

  local line_info = {
    [1] = { type = "commit", hash = "abc1234", commit = commits[1], section = "log" },
    [2] = { type = "commit", hash = "def5678", commit = commits[2], section = "log" },
    [3] = { type = "commit", hash = "ghi9012", commit = commits[3], section = "log" },
  }

  local result = log_list.get_commits_in_range(line_info, 1, 3)

  eq(#result, 3)
  eq(result[1].hash, "abc1234")
  eq(result[2].hash, "def5678")
  eq(result[3].hash, "ghi9012")
end

T["get_commits_in_range()"]["deduplicates commits from expanded lines"] = function()
  local commit = make_commit("abc1234", "Test", { body = "Line 1\nLine 2" })

  -- Simulate expanded commit: multiple lines point to same commit
  local line_info = {
    [1] = { type = "commit", hash = "abc1234", commit = commit, section = "log", expanded = true },
    [2] = { type = "commit", hash = "abc1234", commit = commit, section = "log", expanded = true },
    [3] = { type = "commit", hash = "abc1234", commit = commit, section = "log", expanded = true },
  }

  local result = log_list.get_commits_in_range(line_info, 1, 3)

  eq(#result, 1) -- Only one unique commit
  eq(result[1].hash, "abc1234")
end

T["get_commits_in_range()"]["handles sparse line_info (non-commit lines)"] = function()
  local commits = {
    make_commit("abc1234", "First"),
    make_commit("def5678", "Second"),
  }

  -- Sparse: lines 1, 3, 5 have commits; 2, 4 are empty (section headers, blank lines, etc.)
  local line_info = {
    [1] = { type = "commit", hash = "abc1234", commit = commits[1], section = "log" },
    -- line 2 is empty
    [3] = { type = "commit", hash = "def5678", commit = commits[2], section = "log" },
    -- lines 4, 5 are empty
  }

  local result = log_list.get_commits_in_range(line_info, 1, 5)

  eq(#result, 2)
  eq(result[1].hash, "abc1234")
  eq(result[2].hash, "def5678")
end

T["get_commits_in_range()"]["handles selection starting on section header"] = function()
  -- Line 1 is a section header (no entry in line_info)
  -- Lines 2-4 are commits
  local commits = {
    make_commit("abc1234", "First"),
    make_commit("def5678", "Second"),
  }

  local line_info = {
    -- line 1: section header (not in line_info)
    [2] = { type = "commit", hash = "abc1234", commit = commits[1], section = "log" },
    [3] = { type = "commit", hash = "def5678", commit = commits[2], section = "log" },
  }

  local result = log_list.get_commits_in_range(line_info, 1, 3)

  eq(#result, 2)
  eq(result[1].hash, "abc1234")
  eq(result[2].hash, "def5678")
end

T["get_commits_in_range()"]["handles selection across multiple sections"] = function()
  local commits = {
    make_commit("abc1234", "Unpushed 1"),
    make_commit("def5678", "Unpushed 2"),
    make_commit("ghi9012", "Unpulled 1"),
  }

  local line_info = {
    -- Section: Unpushed
    [2] = { type = "commit", hash = "abc1234", commit = commits[1], section = "unpushed" },
    [3] = { type = "commit", hash = "def5678", commit = commits[2], section = "unpushed" },
    -- Blank line at 4
    -- Section: Unpulled
    [6] = { type = "commit", hash = "ghi9012", commit = commits[3], section = "unpulled" },
  }

  local result = log_list.get_commits_in_range(line_info, 1, 7)

  -- Returns commits in order, across both sections
  eq(#result, 3)
  eq(result[1].hash, "abc1234")
  eq(result[2].hash, "def5678")
  eq(result[3].hash, "ghi9012")
end

return T
