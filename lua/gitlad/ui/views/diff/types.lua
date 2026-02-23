---@mod gitlad.ui.views.diff.types Diff viewer type definitions
---@brief [[
--- Type definitions for the native diff viewer.
--- All diff sources produce a common DiffSpec that the viewer renders.
---@brief ]]

---@alias DiffLineType "context"|"add"|"delete"|"change"|"filler"

---@class DiffLinePair
---@field left_line string|nil Left side content (nil for filler)
---@field right_line string|nil Right side content (nil for filler)
---@field left_type DiffLineType Type of the left line
---@field right_type DiffLineType Type of the right line
---@field left_lineno number|nil Original file line number for left side
---@field right_lineno number|nil Original file line number for right side

---@class DiffHunkHeader
---@field old_start number Start line in old file
---@field old_count number Line count in old file
---@field new_start number Start line in new file
---@field new_count number Line count in new file
---@field text string The full @@ header line

---@class DiffSideBySideHunk
---@field header DiffHunkHeader Parsed hunk header
---@field pairs DiffLinePair[] Side-by-side line pairs

---@class DiffFilePair
---@field old_path string Path in old version (a/ side)
---@field new_path string Path in new version (b/ side)
---@field status string File status: "M" (modified), "A" (added), "D" (deleted), "R" (renamed), "C" (copied)
---@field hunks DiffSideBySideHunk[] Side-by-side hunks
---@field additions number Number of added lines
---@field deletions number Number of deleted lines
---@field is_binary boolean Whether the file is binary

---@class DiffPRCommit
---@field oid string Full commit hash
---@field short_oid string Short commit hash
---@field message_headline string First line of commit message
---@field author_name string Author name
---@field author_date string Authored date (ISO format)
---@field additions number Lines added
---@field deletions number Lines deleted

---@class DiffPRInfo
---@field number number PR number
---@field title string PR title
---@field base_ref string Base branch ref (e.g., "main")
---@field head_ref string Head branch ref (e.g., "feature/foo")
---@field base_oid string Base commit OID
---@field head_oid string Head commit OID
---@field commits DiffPRCommit[] Commits in the PR

---@alias DiffSourceType "staged"|"unstaged"|"worktree"|"commit"|"range"|"stash"|"pr"|"three_way"|"merge"

---@class DiffSource
---@field type DiffSourceType
---@field ref string|nil Commit ref (for commit/stash sources)
---@field range string|nil Range expression (for range sources)
---@field pr_info DiffPRInfo|nil PR info (for pr sources)
---@field selected_commit number|nil Index of selected commit in PR (nil = all changes)

---@class DiffSpec
---@field source DiffSource How this diff was produced
---@field file_pairs DiffFilePair[] Files changed in this diff
---@field title string Display title for the diff viewer tab
---@field repo_root string Repository root path
---@field three_way_files ThreeWayFileDiff[]|nil Files for 3-way view (only when source.type == "three_way" or "merge")

-- =============================================================================
-- Three-Way Diff Types
-- =============================================================================

---@class ThreeWayFileDiff
---@field path string File path
---@field staged_hunks DiffSideBySideHunk[] Hunks from staged diff (HEAD → INDEX)
---@field unstaged_hunks DiffSideBySideHunk[] Hunks from unstaged diff (INDEX → WORKTREE)
---@field status_staged string|nil File status in staged diff ("M", "A", "D", etc.)
---@field status_unstaged string|nil File status in unstaged diff
---@field additions number Total lines added (staged + unstaged)
---@field deletions number Total lines deleted (staged + unstaged)

---@class ThreeWayLineInfo
---@field left_type DiffLineType Type of the left (HEAD) line
---@field mid_type DiffLineType Type of the middle (INDEX) line
---@field right_type DiffLineType Type of the right (WORKTREE) line
---@field left_lineno number|nil HEAD file line number
---@field mid_lineno number|nil INDEX file line number
---@field right_lineno number|nil WORKTREE file line number
---@field hunk_index number|nil Which hunk region this belongs to (1-based)
---@field is_hunk_boundary boolean True for first line of a hunk region

---@class ThreeWayAlignedContent
---@field left_lines string[] Lines for left (HEAD) buffer
---@field mid_lines string[] Lines for middle (INDEX) buffer
---@field right_lines string[] Lines for right (WORKTREE) buffer
---@field line_map ThreeWayLineInfo[] Maps buffer line index (1-based) to metadata

return {}
