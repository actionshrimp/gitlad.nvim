-- Tests for gitlad.git.parse module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_status"] = MiniTest.new_set()

T["parse_status"]["parses branch header"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123def456",
  })

  eq(result.branch, "main")
  eq(result.oid, "abc123def456")
end

T["parse_status"]["parses upstream info"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "# branch.upstream origin/main",
    "# branch.ab +2 -1",
  })

  eq(result.upstream, "origin/main")
  eq(result.ahead, 2)
  eq(result.behind, 1)
end

T["parse_status"]["parses untracked files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "? newfile.txt",
    "? another.lua",
  })

  eq(#result.untracked, 2)
  eq(result.untracked[1].path, "newfile.txt")
  eq(result.untracked[2].path, "another.lua")
end

T["parse_status"]["parses staged files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 abc123def456abc123def456abc123def456abc123 staged.txt",
  })

  eq(#result.staged, 1)
  eq(result.staged[1].path, "staged.txt")
  eq(result.staged[1].index_status, "A")
end

T["parse_status"]["parses unstaged files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "1 .M N... 100644 100644 100644 abc123def456abc123def456abc123def456abc123 abc123def456abc123def456abc123def456abc123 modified.txt",
  })

  eq(#result.unstaged, 1)
  eq(result.unstaged[1].path, "modified.txt")
  eq(result.unstaged[1].worktree_status, "M")
end

T["parse_status"]["parses file with both staged and unstaged changes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "1 MM N... 100644 100644 100644 abc123def456abc123def456abc123def456abc123 abc123def456abc123def456abc123def456abc123 both.txt",
  })

  eq(#result.staged, 1)
  eq(#result.unstaged, 1)
  eq(result.staged[1].path, "both.txt")
  eq(result.unstaged[1].path, "both.txt")
end

T["parse_status"]["parses renamed files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "2 R. N... 100644 100644 100644 abc123def456abc123def456abc123def456abc123 abc123def456abc123def456abc123def456abc123 R100 newname.txt\toldname.txt",
  })

  eq(#result.staged, 1)
  eq(result.staged[1].path, "newname.txt")
  eq(result.staged[1].orig_path, "oldname.txt")
end

T["parse_status"]["parses conflicted files"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
    "u UU N... 100644 100644 100644 100644 abc123 def456 789abc conflict.txt",
  })

  eq(#result.conflicted, 1)
  eq(result.conflicted[1].path, "conflict.txt")
end

T["parse_status"]["handles empty status"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_status({
    "# branch.head main",
    "# branch.oid abc123",
  })

  eq(#result.staged, 0)
  eq(#result.unstaged, 0)
  eq(#result.untracked, 0)
  eq(#result.conflicted, 0)
end

T["parse_branches"] = MiniTest.new_set()

T["parse_branches"]["parses branch list"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_branches({
    "  feature/branch",
    "* main",
    "  develop",
  })

  eq(#result, 3)
  eq(result[1].name, "feature/branch")
  eq(result[1].current, false)
  eq(result[2].name, "main")
  eq(result[2].current, true)
  eq(result[3].name, "develop")
  eq(result[3].current, false)
end

T["status_description"] = MiniTest.new_set()

T["status_description"]["returns correct descriptions"] = function()
  local parse = require("gitlad.git.parse")

  eq(parse.status_description("M"), "modified")
  eq(parse.status_description("A"), "added")
  eq(parse.status_description("D"), "deleted")
  eq(parse.status_description("."), "unmodified")
  eq(parse.status_description("X"), "unknown")
end

T["parse_log_oneline"] = MiniTest.new_set()

T["parse_log_oneline"]["parses commits correctly"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_log_oneline({
    "abc1234 Add feature X",
    "def5678 Fix bug Y",
    "111aaaa Initial commit",
  })

  eq(#result, 3)
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "Add feature X")
  eq(result[2].hash, "def5678")
  eq(result[2].subject, "Fix bug Y")
  eq(result[3].hash, "111aaaa")
  eq(result[3].subject, "Initial commit")
end

T["parse_log_oneline"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_log_oneline({})

  eq(#result, 0)
end

T["parse_log_oneline"]["handles commit messages with spaces"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_log_oneline({
    "abc1234 feat: add new feature with multiple words",
  })

  eq(#result, 1)
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "feat: add new feature with multiple words")
end

T["parse_log_oneline"]["handles hash-only lines"] = function()
  local parse = require("gitlad.git.parse")

  -- Edge case: commit with empty subject
  local result = parse.parse_log_oneline({
    "abc1234 ",
  })

  eq(#result, 1)
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "")
end

T["parse_log_oneline"]["parses decorated output with refs"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_log_oneline({
    "abc1234 (HEAD -> main, origin/main) Add feature X",
    "def5678 Fix bug Y",
    "111aaaa (tag: v1.0.0) Release 1.0.0",
  })

  eq(#result, 3)
  -- First commit has combined refs
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "Add feature X")
  expect.equality(result[1].refs ~= nil, true)
  eq(#result[1].refs, 1) -- combined main + origin/main
  eq(result[1].refs[1].name, "origin/main")
  eq(result[1].refs[1].is_combined, true)
  eq(result[1].refs[1].is_head, true)
  -- Second commit has no refs
  eq(result[2].hash, "def5678")
  eq(result[2].subject, "Fix bug Y")
  eq(#result[2].refs, 0)
  -- Third commit has tag
  eq(result[3].hash, "111aaaa")
  eq(result[3].subject, "Release 1.0.0")
  eq(#result[3].refs, 1)
  eq(result[3].refs[1].name, "v1.0.0")
  eq(result[3].refs[1].type, "tag")
end

T["parse_log_oneline"]["handles refs with parentheses in subject"] = function()
  local parse = require("gitlad.git.parse")

  -- Tricky case: subject contains parentheses
  local result = parse.parse_log_oneline({
    "abc1234 (main) fix(parser): handle edge case",
    "def5678 feat: add feature (experimental)",
  })

  eq(#result, 2)
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "fix(parser): handle edge case")
  eq(#result[1].refs, 1)
  eq(result[1].refs[1].name, "main")
  -- Second commit has no refs (parentheses are part of subject)
  eq(result[2].hash, "def5678")
  eq(result[2].subject, "feat: add feature (experimental)")
  eq(#result[2].refs, 0)
end

T["parse_remote_branches"] = MiniTest.new_set()

T["parse_remote_branches"]["parses remote branches correctly"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remote_branches({
    "  origin/main",
    "  origin/develop",
    "  upstream/main",
  })

  eq(#result, 3)
  eq(result[1], "origin/main")
  eq(result[2], "origin/develop")
  eq(result[3], "upstream/main")
end

T["parse_remote_branches"]["skips HEAD pointers"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remote_branches({
    "  origin/HEAD -> origin/main",
    "  origin/main",
    "  origin/develop",
  })

  eq(#result, 2)
  eq(result[1], "origin/main")
  eq(result[2], "origin/develop")
end

T["parse_remote_branches"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remote_branches({})

  eq(#result, 0)
end

T["parse_remote_branches"]["handles branches with slashes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_remote_branches({
    "  origin/feature/add-login",
    "  origin/bugfix/fix-crash",
  })

  eq(#result, 2)
  eq(result[1], "origin/feature/add-login")
  eq(result[2], "origin/bugfix/fix-crash")
end

-- =============================================================================
-- parse_log_format tests
-- =============================================================================

T["parse_log_format"] = MiniTest.new_set()

-- Helper: build a log record with RS (0x1E) record separator and US (0x1F) field separator
-- Fields: hash, decorations, author, date, subject, body
local function log_record(hash, decorations, author, date, subject, body)
  local RS = "\x1e"
  local US = "\x1f"
  return RS
    .. hash
    .. US
    .. (decorations or "")
    .. US
    .. (author or "")
    .. US
    .. (date or "")
    .. US
    .. (subject or "")
    .. US
    .. (body or "")
end

T["parse_log_format"]["parses commits with all fields"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record("abc1234", "", "John Doe", "2 hours ago", "Add feature X")
    .. log_record("def5678", "", "Jane Smith", "1 day ago", "Fix bug Y")

  local result = parse.parse_log_format(output)

  eq(#result, 2)
  eq(result[1].hash, "abc1234")
  eq(result[1].author, "John Doe")
  eq(result[1].date, "2 hours ago")
  eq(result[1].subject, "Add feature X")
  eq(result[1].body, nil)
  eq(result[2].hash, "def5678")
  eq(result[2].author, "Jane Smith")
  eq(result[2].date, "1 day ago")
  eq(result[2].subject, "Fix bug Y")
  eq(result[2].body, nil)
end

T["parse_log_format"]["handles empty output"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_log_format("")

  eq(#result, 0)
end

T["parse_log_format"]["handles commits with empty optional fields"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record("abc1234", "", "", "", "Just a hash and subject")

  local result = parse.parse_log_format(output)

  eq(#result, 1)
  eq(result[1].hash, "abc1234")
  eq(result[1].author, nil)
  eq(result[1].date, nil)
  eq(result[1].subject, "Just a hash and subject")
end

T["parse_log_format"]["handles subjects with special characters"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record("abc1234", "", "John", "1 hour ago", "feat: add login (WIP) [#123]")

  local result = parse.parse_log_format(output)

  eq(#result, 1)
  eq(result[1].subject, "feat: add login (WIP) [#123]")
end

T["parse_log_format"]["get_log_format_string returns expected format"] = function()
  local parse = require("gitlad.git.parse")

  local format = parse.get_log_format_string()

  -- Should contain placeholders for hash (full), decorations, author, date, subject, body
  expect.equality(format:match("%%H"), "%H")
  expect.equality(format:match("%%D"), "%D")
  expect.equality(format:match("%%an"), "%an")
  expect.equality(format:match("%%ar"), "%ar")
  expect.equality(format:match("%%s") ~= nil, true)
  expect.equality(format:match("%%b"), "%b")
end

T["parse_log_format"]["parses commits with refs"] = function()
  local parse = require("gitlad.git.parse")

  local output =
    log_record("abc1234", "HEAD -> main, origin/main", "John Doe", "2 hours ago", "Add feature X")

  local result = parse.parse_log_format(output)

  eq(#result, 1)
  eq(result[1].hash, "abc1234")
  eq(result[1].author, "John Doe")
  eq(result[1].date, "2 hours ago")
  eq(result[1].subject, "Add feature X")
  -- Should have refs parsed
  expect.equality(result[1].refs ~= nil, true)
  eq(#result[1].refs, 1) -- main and origin/main combined
  eq(result[1].refs[1].name, "origin/main")
  eq(result[1].refs[1].is_combined, true)
  eq(result[1].refs[1].is_head, true)
end

T["parse_log_format"]["parses commits without refs"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record("abc1234", "", "John Doe", "2 hours ago", "Add feature X")

  local result = parse.parse_log_format(output)

  eq(#result, 1)
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "Add feature X")
  -- Should have empty refs
  expect.equality(result[1].refs ~= nil, true)
  eq(#result[1].refs, 0)
end

T["parse_log_format"]["parses commits with body"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record(
    "abc1234",
    "",
    "John Doe",
    "2 hours ago",
    "Add feature X",
    "This is the body\n\nWith multiple paragraphs"
  )

  local result = parse.parse_log_format(output)

  eq(#result, 1)
  eq(result[1].subject, "Add feature X")
  eq(result[1].body, "This is the body\n\nWith multiple paragraphs")
end

T["parse_log_format"]["body is nil for commits without body"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record("abc1234", "", "John", "1 hour ago", "Simple commit")

  local result = parse.parse_log_format(output)

  eq(#result, 1)
  eq(result[1].body, nil)
end

T["parse_log_format"]["mixed commits with and without body"] = function()
  local parse = require("gitlad.git.parse")

  local output = log_record("abc1234", "", "John", "1 hour ago", "Has body", "Body text here")
    .. log_record("def5678", "", "Jane", "2 hours ago", "No body")

  local result = parse.parse_log_format(output)

  eq(#result, 2)
  eq(result[1].body, "Body text here")
  eq(result[2].body, nil)
end

-- =============================================================================
-- parse_stash_list tests
-- =============================================================================

T["parse_stash_list"] = MiniTest.new_set()

T["parse_stash_list"]["parses WIP stash entries"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_stash_list({
    "stash@{0}: WIP on main: abc1234 Add feature X",
    "stash@{1}: WIP on develop: def5678 Fix bug Y",
  })

  eq(#result, 2)
  eq(result[1].index, 0)
  eq(result[1].ref, "stash@{0}")
  eq(result[1].branch, "main")
  eq(result[1].message, "WIP on main: abc1234 Add feature X")
  eq(result[2].index, 1)
  eq(result[2].ref, "stash@{1}")
  eq(result[2].branch, "develop")
  eq(result[2].message, "WIP on develop: def5678 Fix bug Y")
end

T["parse_stash_list"]["parses custom message stash entries"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_stash_list({
    "stash@{0}: On main: my custom stash message",
    "stash@{1}: On feature/login: save work in progress",
  })

  eq(#result, 2)
  eq(result[1].index, 0)
  eq(result[1].ref, "stash@{0}")
  eq(result[1].branch, "main")
  eq(result[1].message, "my custom stash message")
  eq(result[2].index, 1)
  eq(result[2].ref, "stash@{1}")
  eq(result[2].branch, "feature/login")
  eq(result[2].message, "save work in progress")
end

T["parse_stash_list"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_stash_list({})

  eq(#result, 0)
end

T["parse_stash_list"]["handles mixed stash types"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_stash_list({
    "stash@{0}: On main: custom message",
    "stash@{1}: WIP on main: abc1234 Auto stash",
  })

  eq(#result, 2)
  eq(result[1].message, "custom message")
  eq(result[2].message, "WIP on main: abc1234 Auto stash")
end

T["parse_stash_list"]["handles branches with slashes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_stash_list({
    "stash@{0}: WIP on feature/add-login: abc1234 Work on login",
  })

  eq(#result, 1)
  eq(result[1].branch, "feature/add-login")
end

-- =============================================================================
-- parse_for_each_ref tests
-- =============================================================================

T["parse_for_each_ref"] = MiniTest.new_set()

T["parse_for_each_ref"]["parses local branches"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "main|||abc1234|||refs/heads/main|||Initial commit|||*|||origin/main",
    "develop|||def5678|||refs/heads/develop|||Add feature||||||",
  })

  eq(#result, 2)
  eq(result[1].name, "main")
  eq(result[1].hash, "abc1234")
  eq(result[1].full_name, "refs/heads/main")
  eq(result[1].subject, "Initial commit")
  eq(result[1].type, "local")
  eq(result[1].is_head, true)
  eq(result[1].upstream, "origin/main")
  eq(result[2].name, "develop")
  eq(result[2].is_head, false)
  eq(result[2].type, "local")
  eq(result[2].upstream, nil)
end

T["parse_for_each_ref"]["parses remote branches"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "origin/main|||abc1234|||refs/remotes/origin/main|||Initial commit||||||",
    "upstream/main|||def5678|||refs/remotes/upstream/main|||Upstream commit||||||",
  })

  eq(#result, 2)
  eq(result[1].name, "origin/main")
  eq(result[1].type, "remote")
  eq(result[1].remote, "origin")
  eq(result[2].name, "upstream/main")
  eq(result[2].type, "remote")
  eq(result[2].remote, "upstream")
end

T["parse_for_each_ref"]["parses tags"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "v1.0.0|||abc1234|||refs/tags/v1.0.0|||Release version 1.0.0||||||",
    "v0.9.0|||def5678|||refs/tags/v0.9.0|||Release version 0.9.0||||||",
  })

  eq(#result, 2)
  eq(result[1].name, "v1.0.0")
  eq(result[1].type, "tag")
  eq(result[1].remote, nil)
  eq(result[2].name, "v0.9.0")
  eq(result[2].type, "tag")
end

T["parse_for_each_ref"]["handles mixed ref types"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "main|||abc1234|||refs/heads/main|||Commit on main|||*|||origin/main",
    "origin/main|||abc1234|||refs/remotes/origin/main|||Commit on main||||||",
    "v1.0.0|||def5678|||refs/tags/v1.0.0|||Tag message||||||",
  })

  eq(#result, 3)
  eq(result[1].type, "local")
  eq(result[2].type, "remote")
  eq(result[3].type, "tag")
end

T["parse_for_each_ref"]["filters out remote HEAD refs"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "origin|||abc1234|||refs/remotes/origin/HEAD|||Initial commit||||||",
    "origin/main|||abc1234|||refs/remotes/origin/main|||Initial commit||||||",
    "origin/develop|||def5678|||refs/remotes/origin/develop|||Add feature||||||",
    "upstream|||ghi9012|||refs/remotes/upstream/HEAD|||Upstream commit||||||",
    "upstream/main|||ghi9012|||refs/remotes/upstream/main|||Upstream commit||||||",
  })

  -- Remote HEAD refs should be filtered out, leaving only actual branches
  eq(#result, 3)
  eq(result[1].name, "origin/main")
  eq(result[2].name, "origin/develop")
  eq(result[3].name, "upstream/main")
end

T["parse_for_each_ref"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({})

  eq(#result, 0)
end

T["parse_for_each_ref"]["handles branch names with slashes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "feature/add-login|||abc1234|||refs/heads/feature/add-login|||Add login feature||||||origin/feature/add-login",
    "origin/feature/add-login|||abc1234|||refs/remotes/origin/feature/add-login|||Add login||||||",
  })

  eq(#result, 2)
  eq(result[1].name, "feature/add-login")
  eq(result[1].type, "local")
  eq(result[1].upstream, "origin/feature/add-login")
  eq(result[2].name, "origin/feature/add-login")
  eq(result[2].type, "remote")
  eq(result[2].remote, "origin")
end

T["parse_for_each_ref"]["get_refs_format_string returns expected format"] = function()
  local parse = require("gitlad.git.parse")

  local format = parse.get_refs_format_string()

  -- Should contain placeholders for refname, objectname, upstream, etc.
  expect.equality(format:match("refname:short") ~= nil, true)
  expect.equality(format:match("objectname:short") ~= nil, true)
  expect.equality(format:match("refname") ~= nil, true)
  expect.equality(format:match("subject") ~= nil, true)
  expect.equality(format:match("HEAD") ~= nil, true)
  expect.equality(format:match("upstream:short") ~= nil, true)
end

T["parse_for_each_ref"]["parses upstream tracking info"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_for_each_ref({
    "main|||abc1234|||refs/heads/main|||Initial commit|||*|||origin/main",
    "develop|||def5678|||refs/heads/develop|||Add feature||||||",
    "feature|||ghi9012|||refs/heads/feature|||WIP||||||upstream/feature",
  })

  eq(#result, 3)
  -- main tracks origin/main
  eq(result[1].upstream, "origin/main")
  -- develop has no upstream
  eq(result[2].upstream, nil)
  -- feature tracks upstream/feature
  eq(result[3].upstream, "upstream/feature")
end

-- =============================================================================
-- parse_cherry tests
-- =============================================================================

T["parse_cherry"] = MiniTest.new_set()

T["parse_cherry"]["parses unique commits (+ prefix)"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_cherry({
    "+ abc1234 Add feature X",
    "+ def5678 Fix bug Y",
  })

  eq(#result, 2)
  eq(result[1].hash, "abc1234")
  eq(result[1].subject, "Add feature X")
  eq(result[1].equivalent, false)
  eq(result[2].hash, "def5678")
  eq(result[2].subject, "Fix bug Y")
  eq(result[2].equivalent, false)
end

T["parse_cherry"]["parses equivalent commits (- prefix)"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_cherry({
    "- abc1234 Cherry-picked commit",
    "- def5678 Another cherry-picked",
  })

  eq(#result, 2)
  eq(result[1].hash, "abc1234")
  eq(result[1].equivalent, true)
  eq(result[2].hash, "def5678")
  eq(result[2].equivalent, true)
end

T["parse_cherry"]["handles mixed unique and equivalent commits"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_cherry({
    "+ abc1234 Unique commit",
    "- def5678 Equivalent commit",
    "+ 111aaaa Another unique",
  })

  eq(#result, 3)
  eq(result[1].equivalent, false)
  eq(result[2].equivalent, true)
  eq(result[3].equivalent, false)
end

T["parse_cherry"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_cherry({})

  eq(#result, 0)
end

T["parse_cherry"]["handles commits with special characters in subject"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_cherry({
    "+ abc1234 feat: add login (WIP) [#123]",
  })

  eq(#result, 1)
  eq(result[1].subject, "feat: add login (WIP) [#123]")
end

-- =============================================================================
-- parse_rev_list_count tests
-- =============================================================================

T["parse_rev_list_count"] = MiniTest.new_set()

T["parse_rev_list_count"]["parses ahead and behind counts"] = function()
  local parse = require("gitlad.git.parse")

  local ahead, behind = parse.parse_rev_list_count({ "5\t3" })

  eq(ahead, 5)
  eq(behind, 3)
end

T["parse_rev_list_count"]["handles zero counts"] = function()
  local parse = require("gitlad.git.parse")

  local ahead, behind = parse.parse_rev_list_count({ "0\t0" })

  eq(ahead, 0)
  eq(behind, 0)
end

T["parse_rev_list_count"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local ahead, behind = parse.parse_rev_list_count({})

  eq(ahead, 0)
  eq(behind, 0)
end

T["parse_rev_list_count"]["handles nil input"] = function()
  local parse = require("gitlad.git.parse")

  local ahead, behind = parse.parse_rev_list_count(nil)

  eq(ahead, 0)
  eq(behind, 0)
end

T["parse_rev_list_count"]["handles large counts"] = function()
  local parse = require("gitlad.git.parse")

  local ahead, behind = parse.parse_rev_list_count({ "123\t456" })

  eq(ahead, 123)
  eq(behind, 456)
end

-- =============================================================================
-- parse_submodule_status tests
-- =============================================================================

T["parse_submodule_status"] = MiniTest.new_set()

T["parse_submodule_status"]["parses clean submodule (space prefix)"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({
    " abc123def456abc123def456abc123def456abc123 path/to/submodule (v1.0.0)",
  })

  eq(#result, 1)
  eq(result[1].path, "path/to/submodule")
  eq(result[1].sha, "abc123def456abc123def456abc123def456abc123")
  eq(result[1].status, "clean")
  eq(result[1].describe, "v1.0.0")
end

T["parse_submodule_status"]["parses modified submodule (+ prefix)"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({
    "+abc123def456abc123def456abc123def456abc123 vendor/lib (heads/main)",
  })

  eq(#result, 1)
  eq(result[1].path, "vendor/lib")
  eq(result[1].sha, "abc123def456abc123def456abc123def456abc123")
  eq(result[1].status, "modified")
  eq(result[1].describe, "heads/main")
end

T["parse_submodule_status"]["parses uninitialized submodule (- prefix)"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({
    "-abc123def456abc123def456abc123def456abc123 external/dep",
  })

  eq(#result, 1)
  eq(result[1].path, "external/dep")
  eq(result[1].sha, "abc123def456abc123def456abc123def456abc123")
  eq(result[1].status, "uninitialized")
  eq(result[1].describe, nil)
end

T["parse_submodule_status"]["parses merge conflict submodule (U prefix)"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({
    "Uabc123def456abc123def456abc123def456abc123 libs/conflict",
  })

  eq(#result, 1)
  eq(result[1].path, "libs/conflict")
  eq(result[1].sha, "abc123def456abc123def456abc123def456abc123")
  eq(result[1].status, "merge_conflict")
end

T["parse_submodule_status"]["handles multiple submodules"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({
    " abc123def456abc123def456abc123def456abc123 vendor/lib1 (v1.0.0)",
    "+def456abc123def456abc123def456abc123def456 vendor/lib2 (v2.0.0)",
    "-111222333444555666777888999000aaabbbcccdd external/new",
  })

  eq(#result, 3)
  eq(result[1].status, "clean")
  eq(result[1].path, "vendor/lib1")
  eq(result[2].status, "modified")
  eq(result[2].path, "vendor/lib2")
  eq(result[3].status, "uninitialized")
  eq(result[3].path, "external/new")
end

T["parse_submodule_status"]["handles empty input"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({})

  eq(#result, 0)
end

T["parse_submodule_status"]["handles paths with spaces"] = function()
  local parse = require("gitlad.git.parse")

  -- Note: git submodule paths can't actually have spaces, but test robustness
  local result = parse.parse_submodule_status({
    " abc123def456abc123def456abc123def456abc123 path/to/sub (tag-name)",
  })

  eq(#result, 1)
  eq(result[1].path, "path/to/sub")
end

T["parse_submodule_status"]["handles describe with special characters"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_submodule_status({
    " abc123def456abc123def456abc123def456abc123 submod (v1.0.0-rc1-5-gabc1234)",
  })

  eq(#result, 1)
  eq(result[1].describe, "v1.0.0-rc1-5-gabc1234")
end

-- =============================================================================
-- parse_decorations tests
-- =============================================================================

T["parse_decorations"] = MiniTest.new_set()

T["parse_decorations"]["returns empty array for empty string"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("")

  eq(#result, 0)
end

T["parse_decorations"]["parses single local branch"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("main")

  eq(#result, 1)
  eq(result[1].name, "main")
  eq(result[1].type, "local")
  eq(result[1].is_head, false)
  eq(result[1].is_combined, false)
end

T["parse_decorations"]["parses single remote branch"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("origin/main")

  eq(#result, 1)
  eq(result[1].name, "origin/main")
  eq(result[1].type, "remote")
  eq(result[1].is_head, false)
  eq(result[1].is_combined, false)
end

T["parse_decorations"]["parses tag"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("tag: v1.0.0")

  eq(#result, 1)
  eq(result[1].name, "v1.0.0")
  eq(result[1].type, "tag")
  eq(result[1].is_head, false)
  eq(result[1].is_combined, false)
end

T["parse_decorations"]["parses HEAD pointing to branch"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("HEAD -> main")

  eq(#result, 1)
  eq(result[1].name, "main")
  eq(result[1].type, "local")
  eq(result[1].is_head, true)
  eq(result[1].is_combined, false)
end

T["parse_decorations"]["parses multiple refs"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("HEAD -> main, origin/main, tag: v1.0.0")

  -- After deduplication, main and origin/main should combine
  -- So we expect: combined origin/main, tag: v1.0.0
  eq(#result, 2)
  -- First should be the combined ref
  eq(result[1].name, "origin/main")
  eq(result[1].is_head, true)
  eq(result[1].is_combined, true)
  -- Second should be the tag
  eq(result[2].name, "v1.0.0")
  eq(result[2].type, "tag")
end

T["parse_decorations"]["combines local and remote at same commit"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("main, origin/main")

  -- Should combine into single entry
  eq(#result, 1)
  eq(result[1].name, "origin/main")
  eq(result[1].type, "remote")
  eq(result[1].is_combined, true)
end

T["parse_decorations"]["handles origin/HEAD correctly"] = function()
  local parse = require("gitlad.git.parse")

  -- origin/HEAD -> origin/main should be filtered out
  local result = parse.parse_decorations("origin/HEAD -> origin/main, origin/main")

  eq(#result, 1)
  eq(result[1].name, "origin/main")
  eq(result[1].type, "remote")
end

T["parse_decorations"]["handles multiple remotes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("origin/main, upstream/main")

  eq(#result, 2)
  eq(result[1].name, "origin/main")
  eq(result[1].type, "remote")
  eq(result[2].name, "upstream/main")
  eq(result[2].type, "remote")
end

T["parse_decorations"]["handles branch names with slashes"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("feature/add-login, origin/feature/add-login")

  eq(#result, 1)
  eq(result[1].name, "origin/feature/add-login")
  eq(result[1].is_combined, true)
end

T["parse_decorations"]["preserves order: HEAD first, then tags, then branches"] = function()
  local parse = require("gitlad.git.parse")

  local result = parse.parse_decorations("tag: v1.0.0, HEAD -> develop, origin/develop")

  -- develop and origin/develop combine
  eq(#result, 2)
  -- HEAD ref should come first
  eq(result[1].name, "origin/develop")
  eq(result[1].is_head, true)
  eq(result[1].is_combined, true)
  -- Then tag
  eq(result[2].name, "v1.0.0")
  eq(result[2].type, "tag")
end

T["parse_decorations"]["handles detached HEAD"] = function()
  local parse = require("gitlad.git.parse")

  -- When HEAD is detached, it just shows HEAD without an arrow
  local result = parse.parse_decorations("HEAD, tag: v1.0.0")

  eq(#result, 2)
  eq(result[1].name, "HEAD")
  eq(result[1].type, "local")
  eq(result[1].is_head, true)
  eq(result[2].name, "v1.0.0")
  eq(result[2].type, "tag")
end

T["parse_decorations"]["does not combine unrelated branches"] = function()
  local parse = require("gitlad.git.parse")

  -- main and origin/develop should not combine
  local result = parse.parse_decorations("main, origin/develop")

  eq(#result, 2)
  eq(result[1].name, "main")
  eq(result[1].type, "local")
  eq(result[1].is_combined, false)
  eq(result[2].name, "origin/develop")
  eq(result[2].type, "remote")
  eq(result[2].is_combined, false)
end

return T
