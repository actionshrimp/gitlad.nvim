# gitlad.nvim Development Plan

## Core Architecture Principles

### Performance-First Design for Large Repos

**Problem:** In large monorepos (1M+ files), `git status` can take several seconds. Automatically syncing from git after every operation creates unacceptable latency.

**Solution: Optimistic State Updates**

1. **No automatic git syncing** - Never automatically run `git status` after user operations
2. **Manual refresh only** - User triggers refresh with `g` key, shows "Refreshing..." indicator
3. **Optimistic Lua-side updates** - When user stages/unstages:
   - Run the git command (e.g., `git add`)
   - Check exit code
   - If success: update the in-memory state directly (move file between sections)
   - If failure: show error, state unchanged
4. **Git command history** - Log all git commands, args, output, and exit codes for transparency

This means the UI may occasionally be out of sync with git (if user runs git commands outside the plugin), but the `g` refresh is always available to resync.

### Leverage diffview.nvim for Full-Buffer Diffs

**Principle:** Don't reinvent the wheel for diff viewing.

- **Full-buffer diff views** (side-by-side diffs, commit diffs, file history) → Delegate to `diffview.nvim`
- **Status buffer inline diffs** (hunk preview, hunk staging) → Our own implementation

`diffview.nvim` is a mature, well-tested plugin that handles all the complexity of diff rendering, navigation, and 3-way merge views. We should integrate with it rather than building our own.

**What we build ourselves:**
- Inline diff expansion in the status buffer (TAB on a file)
- Hunk parsing for staging/unstaging individual hunks
- Diff highlighting within the status buffer

**What we delegate to diffview.nvim:**
- `d` popup actions that open full diff views
- Side-by-side file comparison
- Commit diff viewing
- File history / log diff viewing
- 3-way merge conflict resolution

This keeps gitlad.nvim focused on the status/staging workflow while leveraging diffview.nvim's strengths.

---

## Current State (Phase 4 Nearly Complete)

### What's Built
- Project structure with proper module organization
- Async git CLI wrapper (`git/cli.lua`) using `vim.fn.jobstart`
- Git output parsing (`git/parse.lua`) for porcelain v2 format
- Cache utilities (`state/cache.lua`)
- AsyncHandler pattern (`state/async.lua`) for request ordering
- Debounce/throttle utilities
- RepoState coordinator with event system (`state/init.lua`)
- **Optimistic state updates** - Commands/reducer pattern for pure state mutations
- **Refresh indicator** - "(Refreshing...)" shown in header during manual refresh
- **Git command history** - `$` keybinding opens history view
- **Full magit keybindings** - n/p, M-n/M-p, TAB, RET, s/u, S/U, x, g, q, ?, $
- **Inline diff expansion** - TAB on file shows diff with syntax highlighting
- **Hunk-level staging** - s/u on diff lines stages/unstages individual hunks
- **Popup system** - Transient-style popups with switches, options, and actions
- Status buffer view with full staging/unstaging workflow
- **Push popup** - `p` keybinding for push with switches/options/actions
- **Fetch popup** - `f` keybinding for fetch with switches/options/actions
- **Pull popup** - `F` keybinding for pull with switches/options/actions
- **Branch popup** - `b` keybinding for branch operations (checkout, create, delete, rename, set upstream, configure push remote)
- **Upstream/Push tracking** - Status shows Head/Merge/Push with commit messages, unpushed/unpulled commit sections
- **Log popup and view** - `l` keybinding for log with expandable commit details
- **Diff popup** - `d` keybinding, integrates with diffview.nvim
- **Stash popup** - `z` keybinding for stash operations
- **Rebase popup** - `r` keybinding for interactive rebase, continue, abort, skip
- **Interactive rebase editor** - Custom buffer with p/r/e/s/f/d keybindings, M-j/M-k to reorder
- **Instant fixup** - `c F` creates fixup commit and immediately rebases to apply it
- **Cherry-pick popup** - `A` keybinding with conflict detection
- **Revert popup** - `_` keybinding with conflict detection
- **Reset popup** - `X` keybinding with mixed, soft, hard, keep modes
- **Merge popup** - `m` keybinding with full magit-style switches (mutually exclusive ff options, whitespace, gpg-sign) and choice options (strategy, strategy-option, diff-algorithm)
- **Submodule popup** - `'` keybinding for init, update, add, deinit operations
- **Refs popup and view** - `yr` keybinding for branch/tag reference comparison
- **Streaming output viewer** - floating window for real-time git hook output
- Test infrastructure with mini.test (940+ tests across 73 test files)
- CI workflow for Neovim stable/nightly

### Architecture Decisions Made
- Shell out to `git` (not libgit2) - simpler, portable, what others do
- Porcelain v2 format for stable machine-readable output
- Line map approach for buffer -> file mapping (no text parsing)
- Event-driven updates (RepoState emits events, views subscribe)
- Elm-style Commands/Reducer for pure state mutations

---

## Phase 2: Core Functionality

### 2.1 Optimistic State Updates - COMPLETE

Implemented using Commands/Reducer pattern (Elm Architecture):
- [x] `state/commands.lua` - Command definitions (stage_file, unstage_file, etc.)
- [x] `state/reducer.lua` - Pure state mutations
- [x] `RepoState:apply_command()` - Applies command and notifies listeners
- [x] Stage/unstage use optimistic updates (no auto-refresh)

### 2.2 Refresh Indicator - COMPLETE

- [x] `refreshing` boolean in RepoState
- [x] "(Refreshing...)" shown in status buffer header during manual refresh

### 2.3 Git Command History - COMPLETE

- [x] `git/history.lua` - Ring buffer tracking all git commands
- [x] `ui/views/history.lua` - History view buffer
- [x] `$` keybinding opens command history

### 2.4 Full Magit Keybindings - COMPLETE

- [x] Navigation: `n`/`p` (next/prev item), `M-n`/`M-p` (next/prev section)
- [x] `TAB` - expand/collapse inline diff
- [x] `RET` - visit file at point
- [x] `s`/`u` - stage/unstage
- [x] `S`/`U` - stage all / unstage all
- [x] `x` - discard changes at point
- [x] `g` - refresh
- [x] `q` - close
- [x] `$` - show git command history
- [x] `?` - show help popup

### 2.5 Inline Diff Expansion - COMPLETE

- [x] `TAB` on file shows/hides diff inline
- [x] Track expanded state per file in StatusBuffer
- [x] Fetch diff async when expanding
- [x] Syntax highlighting for diff (add/remove lines)
- [ ] Hunk headers clickable/navigable (enhancement for later)

### 2.6 Hunk-Level Staging - COMPLETE

- [x] Parse diff into hunks
- [x] `s`/`u` on hunk stages/unstages just that hunk
- [x] Use `git apply --cached` for hunk staging
- [x] Visual feedback for partially staged files

### 2.7 Popup System - COMPLETE

Transient-style popup system inspired by neogit/magit:

- [x] `lua/gitlad/ui/popup/init.lua` - PopupBuilder fluent API and PopupData
- [x] Switches (boolean flags like `-a`, `--all`)
- [x] Options (key-value like `--author=`)
- [x] Actions (commands that execute)
- [x] Grouping with headings
- [x] Prefix keybindings (`-` for switches, `=` for options)
- [x] Close with `q` or `<Esc>`
- [ ] Persistent switch state between sessions (enhancement for later)

### 2.8 Commit Popup - COMPLETE (MVP)

- [x] `c` opens commit popup
- [x] Switches: `-a` (all), `-e` (allow-empty), `-v` (verbose), `-n` (no-verify)
- [x] Options: `--author=`, `--signoff`
- [x] Actions:
  - [x] `c` - Commit (opens message editor buffer)
  - [x] `e` - Extend (amend without editing message)
  - [x] `a` - Amend (opens editor with previous message)
  - [ ] `f` - Fixup (future: requires commit selection)
  - [ ] `s` - Squash (future: requires commit selection)
- [x] Open `COMMIT_EDITMSG` buffer for message editing
- [x] `C-c C-c` to confirm commit, `C-c C-k` to abort
- [x] Verbose mode shows diff in editor
- [ ] Handle commit hooks (pre-commit, commit-msg) - hooks run automatically via git

**Files created:**
- `lua/gitlad/popups/commit.lua` - Popup definition and actions
- `lua/gitlad/ui/views/commit_editor.lua` - Commit message buffer
- `tests/unit/test_commit_popup.lua` - Unit tests
- `tests/e2e/test_commit.lua` - E2E tests

---

## Phase 3: Git Operations

### 3.1 Push Popup - COMPLETE

- [x] `P` opens push popup
- [x] Switches: `--force-with-lease`, `--force`, `--dry-run`, `--tags`, `--set-upstream`
- [x] Options: remote selection (`=r`), refspec (`=b`)
- [x] Actions: push to upstream (`p`), push elsewhere (`e`)
- [x] Validation: warns when no upstream configured
- [ ] Show push progress (streaming output) - future enhancement

**Files created:**
- `lua/gitlad/popups/push.lua` - Popup definition and actions
- `lua/gitlad/git/parse.lua` - Added `parse_remotes()` function
- `lua/gitlad/git/init.lua` - Added `remotes()` and `push()` functions
- `tests/unit/test_push_popup.lua` - Unit tests (13 tests)
- `tests/e2e/test_push.lua` - E2E tests (6 tests)

### 3.2 Pull/Fetch Popups - COMPLETE

- [x] `F` opens pull popup, `f` opens fetch popup
- [x] Pull: `--rebase`, `--ff-only`, `--no-ff`, `--autostash` switches
- [x] Fetch: `--prune`, `--tags`, `--all` switches
- [x] Remote selection via option (`=o` for pull, `=r` for fetch)
- [x] Actions: pull/fetch from upstream, pull/fetch elsewhere, fetch all remotes

**Files created:**
- `lua/gitlad/popups/fetch.lua` - Fetch popup definition and actions
- `lua/gitlad/popups/pull.lua` - Pull popup definition and actions
- `lua/gitlad/git/init.lua` - Added `fetch()` and `pull()` functions
- `tests/unit/test_fetch_popup.lua` - Unit tests (7 tests)
- `tests/unit/test_pull_popup.lua` - Unit tests (7 tests)
- `tests/e2e/test_fetch.lua` - E2E tests (6 tests)
- `tests/e2e/test_pull.lua` - E2E tests (6 tests)

### 3.3 Branch Popup - COMPLETE

- [x] `b` opens branch popup
- [x] Actions: checkout, create, delete, rename
- [x] Create from: current HEAD, specific ref (via base prompt)
- [x] Force delete switch (`-f`) for unmerged branches
- [x] Show branch list with current indicator (via vim.ui.select)
- [x] Configure group: set upstream (`u`), configure push remote (`r`)

**Files created:**
- `lua/gitlad/popups/branch.lua` - Popup definition and actions
- `lua/gitlad/git/init.lua` - Added `checkout()`, `checkout_new_branch()`, `create_branch()`, `delete_branch()`, `rename_branch()`, `set_upstream()`, `set_push_remote()`, `remote_branches()`, `remote_names()` functions
- `tests/unit/test_branch_popup.lua` - Unit tests (10 tests)
- `tests/e2e/test_branch.lua` - E2E tests (11 tests)

### 3.4 Upstream/Push Remote Tracking in Status - COMPLETE

- [x] Status header shows Head/Merge/Push with commit messages
- [x] "Merge:" line replaces "Upstream:" (shows upstream tracking branch)
- [x] "Push:" line shows push remote when different from merge remote
- [x] Ahead/behind counts shown for both remotes
- [x] Unpushed/Unpulled commit sections (when commits exist)

**Files modified:**
- `lua/gitlad/git/parse.lua` - Added `GitCommitInfo` type, `parse_log_oneline()`, `parse_remote_branches()`, extended `GitStatusResult`
- `lua/gitlad/git/init.lua` - Added `get_commit_subject()`, `get_commits_between()`, `get_push_remote()`
- `lua/gitlad/state/reducer.lua` - Extended `copy_status()` with new fields
- `lua/gitlad/state/init.lua` - Added `_fetch_extended_status()`, extended `refresh_status()`
- `lua/gitlad/ui/views/status.lua` - Updated header rendering, added commit sections
- `tests/unit/test_parse.lua` - Tests for parse functions
- `tests/unit/test_status.lua` - Tests for header rendering
- `tests/e2e/test_status_view.lua` - Tests for Merge line display

### 3.5 Log View ✓
- [x] `l` opens log popup, then actions open log buffer
- [x] Show commit list with: hash, author, date, message
- [x] Navigation through commits (j/k)
- [x] `RET`/`TAB` on commit expands commit details (body)
- [x] `d` shows diff for commit (via diffview.nvim)
- [x] `y` yanks commit hash to clipboard
- [x] Limit options: `-n`, `--since`, `--until`, `--author`
- [x] Reusable log_list component for embedding in other views

**Files created:**
- `lua/gitlad/ui/views/log.lua` - Log buffer view
- `lua/gitlad/popups/log.lua` - Log popup with switches/options/actions
- `lua/gitlad/ui/components/log_list.lua` - Reusable commit list component
- `tests/unit/test_log_list.lua` - Unit tests for log_list component
- `tests/unit/test_log_popup.lua` - Unit tests for log popup
- `tests/e2e/test_log.lua` - E2E tests for log functionality

**Files modified:**
- `lua/gitlad/git/init.lua` - Added log(), log_detailed(), show_commit()
- `lua/gitlad/git/parse.lua` - Extended GitCommitInfo, added parse_log_format()
- `lua/gitlad/ui/views/status.lua` - Added `l` keymap, integrated log_list component
- `lua/gitlad/ui/hl.lua` - Added commit-related highlight groups

### 3.6 Diff View (via diffview.nvim) ✓

**Note:** Full-buffer diff views delegate to `diffview.nvim` - see "Leverage diffview.nvim" section above.

- [x] `d` opens diff popup (from both status and log views)
- [x] Actions invoke `diffview.nvim` commands:
  - Diff dwim (context-aware) → smart selection based on cursor position
  - Diff staged → `diffview.open({"--cached"})`
  - Diff unstaged → `diffview.open({})`
  - Diff worktree → `diffview.open({"HEAD"})`
  - Diff range → prompt for refs, `diffview.open({ref1..ref2})`
  - Show commit → `diffview.open({hash .. "^!"})`
- [x] Graceful fallback if diffview.nvim not installed (terminal with git diff)
- [ ] Optional: config to use built-in `vimdiff` instead (future enhancement)

**Files created:**
- `lua/gitlad/popups/diff.lua` - Diff popup definition and actions
- `tests/unit/test_diff_popup.lua` - Unit tests (12 tests)
- `tests/e2e/test_diff.lua` - E2E tests (7 tests)

**Files modified:**
- `lua/gitlad/ui/views/status.lua` - Changed `d` keymap to open diff popup, added `_get_diff_context()`
- `lua/gitlad/ui/views/log.lua` - Changed `d` keymap to open diff popup

### 3.7 Stash Popup ✅
- [x] `z` opens stash popup
- [x] Actions: stash (`z`), stash index (`i`), pop (`p`), apply (`a`), drop (`d`)
- [x] Switches: `-u` (include-untracked), `-a` (all), `-k` (keep-index)
- [x] Stash selection via `vim.ui.select` for pop/apply/drop

**Files created:**
- `lua/gitlad/popups/stash.lua` - Stash popup with switches and actions
- `tests/unit/test_stash_popup.lua` - Unit tests for popup structure
- `tests/e2e/test_stash.lua` - E2E tests for stash operations

**Files modified:**
- `lua/gitlad/git/init.lua` - Added stash_push, stash_pop, stash_apply, stash_drop, stash_list
- `lua/gitlad/git/parse.lua` - Added StashEntry type and parse_stash_list
- `lua/gitlad/ui/views/status.lua` - Added `z` keybinding for stash popup
- `lua/gitlad/popups/help.lua` - Added `z` (Stash) and `d` (Diff) entries

---

## Phase 4: Advanced Features

### 4.1 Rebase Popup - COMPLETE
- [x] `r` opens rebase popup
- [x] Actions: interactive (`i`), autosquash (`a`), onto (`o`), continue (`r`), abort (`A`), skip (`s`)
- [x] Switches: `--autostash`, `--preserve-merges`/`--rebase-merges`, `--interactive`, `--autosquash`
- [x] Context-aware: if cursor on commit, uses that as target for interactive/onto
- [x] Interactive rebase with custom editor buffer (evil-collection keybindings)
- [x] pick/reword/edit/squash/fixup/drop commands with single keystrokes
- [x] M-j/M-k to reorder commits, ZZ to submit, ZQ to abort

**Files created:**
- `lua/gitlad/popups/rebase.lua` - Rebase popup with switches and actions
- `lua/gitlad/client.lua` - RPC client for headless Neovim editor integration
- `lua/gitlad/ui/views/rebase_editor.lua` - Interactive rebase todo editor buffer
- `tests/unit/test_rebase_popup.lua` - Unit tests for popup structure
- `tests/unit/test_rebase_editor.lua` - Unit tests for rebase editor
- `tests/e2e/test_rebase.lua` - E2E tests for rebase operations
- `tests/e2e/test_rebase_editor.lua` - E2E tests for rebase editor

### 4.1.1 Instant Fixup (commit popup) - COMPLETE
- [x] `c F` in commit popup creates fixup commit and immediately rebases
- [x] `c S` in commit popup creates squash commit and immediately rebases
- [x] Commit selector UI for choosing target commit
- [x] Uses `git commit --fixup=<hash>` then `git rebase --autosquash`

**Files created:**
- `lua/gitlad/ui/views/commit_select.lua` - Floating commit selector window
- `lua/gitlad/git/init.lua` - Added `rebase_instantly()` function

**Files modified:**
- `lua/gitlad/popups/commit.lua` - Added "Instant" action group with F/S actions

### 4.2 Merge & Conflict Resolution (3-way merge via diffview.nvim)

**Note:** 3-way merge views delegate to `diffview.nvim` - see "Leverage diffview.nvim" section above.

This feature is implemented in **3 PRs** for incremental delivery:

#### PR 1: Merge State Detection & Basic Popup - COMPLETE

**Scope:** Detect merge-in-progress state, show in status header, create basic merge popup.

- [x] Merge state detection via `.git/MERGE_HEAD` file
- [x] Status header shows "Merging: <hash> <subject>" when merge in progress
- [x] `m` opens merge popup (matches magit/evil-collection)
- [x] Normal state switches: `-f` (`--ff-only`), `-n` (`--no-ff`)
- [x] Normal state actions: `m` (Merge), `e` (Merge, edit message), `n` (Merge, don't commit), `s` (Squash merge)
- [x] In-progress state actions: `m` (Commit merge), `a` (Abort merge)
- [x] Help popup updated with `m` entry
- [x] `s` on conflicted file stages it (marks as resolved)
- [x] `s` on Conflicted section header stages all conflicted files
- [x] Conflict marker safeguard: `s` on file with markers shows confirmation prompt
- [x] `e` or `RET` on conflicted file opens diffview.nvim merge tool
- [x] Graceful fallback if diffview.nvim not installed (opens file with conflict markers)

**Files created:**
- `lua/gitlad/popups/merge.lua` - Merge popup with switches and actions
- `tests/unit/test_merge_popup.lua` - Unit tests for popup structure
- `tests/e2e/test_merge.lua` - E2E tests for merge operations

**Files modified:**
- `lua/gitlad/git/init.lua` - Add `get_merge_state()`, `merge()`, `merge_continue()`, `merge_abort()`
- `lua/gitlad/git/parse.lua` - Extend `GitStatusResult` with `merge_in_progress`, `merge_head_oid`, `merge_head_subject`
- `lua/gitlad/state/init.lua` - Fetch merge state during refresh
- `lua/gitlad/state/reducer.lua` - Copy merge fields in reducer
- `lua/gitlad/ui/views/status.lua` - Header display, `m` keybinding, staging conflicted files, `e` keybinding, diffview integration
- `lua/gitlad/popups/help.lua` - Add `m` (Merge), `e` (Edit) entries

#### PR 2: Full Merge Popup Options - COMPLETE

**Scope:** Add all magit-style switches and options.

- [x] Additional switches: `-b` (`-Xignore-space-change`), `-w` (`-Xignore-all-space`), `-S` (`--gpg-sign`)
- [x] Strategy option (`--strategy=`): resolve, recursive, octopus, ours, subtree
- [x] Strategy-option (`--strategy-option=`): ours, theirs, patience
- [x] Diff algorithm (`-Xdiff-algorithm=`): default, minimal, patience, histogram
- [x] Mark `--ff-only` and `--no-ff` as mutually exclusive

**Implementation notes:**
- Added `exclusive_with` option to PopupBuilder switches for mutual exclusivity
- Added `choice_option()` method to PopupBuilder for constrained choice options using `vim.ui.select`
- Also updated Pull popup to use mutual exclusivity for `--ff-only` and `--no-ff`

**Files modified:**
- `lua/gitlad/ui/popup/init.lua` - Added `exclusive_with`, `choice_option()`, updated `=` handler
- `lua/gitlad/popups/merge.lua` - Added new switches and choice options
- `lua/gitlad/popups/pull.lua` - Added `exclusive_with` to ff switches
- `tests/unit/test_popup.lua` - Tests for PopupBuilder extensions
- `tests/unit/test_merge_popup.lua` - Tests for new merge popup features
- `tests/e2e/test_merge.lua` - E2E tests for merge popup

#### PR 3: Conflict Resolution Workflow - COMPLETE (merged into PR 1)

**Scope:** Enhance conflict resolution with diffview.nvim integration.

- [x] `e` or `RET` on conflicted file opens diffview.nvim merge tool (implemented in PR 1)
- [x] Graceful fallback if diffview.nvim not installed (implemented in PR 1)

**Magit parity notes:**
- Magit's "absorb", "preview", and "dissolve" actions are advanced features that even neogit hasn't implemented - skipped initially

### 4.3 Blame View
- [ ] `:Gitlad blame` or `B` from file
- [ ] Show blame annotations inline
- [ ] Navigate to commit from blame line
- [ ] Blame at specific revision

### 4.4 Cherry-pick & Revert (COMPLETE)
- [x] `A` cherry-pick popup
- [x] `_` revert popup (uses `_` like evil-collection-magit - "subtracting" a commit)
- [x] Handle conflicts (in-progress state detection)
- [x] Status header shows "Cherry-picking: <hash> <subject>" or "Reverting: <hash> <subject>"

**Files created/modified:**
- `lua/gitlad/git/init.lua` - cherry_pick, revert, get_sequencer_state functions
- `lua/gitlad/popups/cherrypick.lua` - Cherry-pick popup with switches/options/actions
- `lua/gitlad/popups/revert.lua` - Revert popup with switches/options/actions
- `lua/gitlad/ui/views/status.lua` - Added keybindings, sequencer state in header
- `lua/gitlad/popups/help.lua` - Added help entries
- `lua/gitlad/git/parse.lua` - Extended GitStatusResult with sequencer fields
- `lua/gitlad/state/init.lua` - Fetch sequencer state during refresh
- `lua/gitlad/state/reducer.lua` - Copy sequencer fields in reducer
- `tests/unit/test_cherrypick_popup.lua` - Cherry-pick popup tests
- `tests/unit/test_revert_popup.lua` - Revert popup tests
- `tests/e2e/test_cherrypick.lua` - E2E tests for cherry-pick and revert
- `tests/e2e/test_sequencer_state.lua` - Sequencer state detection tests

### 4.5 Reset Popup (COMPLETE)
- [x] `X` reset popup (neogit/evil-collection-magit style)
- [x] Reset modes: mixed, soft, hard, keep, index, worktree
- [x] Context-aware: if cursor on commit, uses that as target
- [x] Confirmation prompt for destructive operations (hard, worktree)

**Files created/modified:**
- `lua/gitlad/git/init.lua` - reset_keep, reset_index, reset_worktree functions
- `lua/gitlad/popups/reset.lua` - Reset popup with all modes
- `lua/gitlad/ui/views/status.lua` - Added `X` keybinding
- `lua/gitlad/popups/help.lua` - Added `X` help entry
- `tests/unit/test_reset_popup.lua` - Reset popup tests
- `tests/e2e/test_reset.lua` - E2E tests for reset operations

### 4.6 Refs Popup and View (COMPLETE)
- [x] `yr` opens refs popup
- [x] Actions: show refs at HEAD, at current branch, at other ref
- [x] Refs view buffer shows all branches and tags
- [x] Grouped by: local branches, remote branches (per-remote), tags
- [x] Expandable refs showing ahead/behind info and cherry commits
- [x] Base ref comparison (configurable)

**Files created:**
- `lua/gitlad/popups/refs.lua` - Refs popup with actions
- `lua/gitlad/ui/views/refs.lua` - Refs view buffer

---

## Phase 5: Polish & Optional Features

### 5.1 Optional File Watcher (Disabled by Default)
For users who want auto-refresh and don't have large repo concerns.

- [ ] Config option: `auto_refresh = false` (default off)
- [ ] When enabled: watch `.git/` directory using `vim.loop.new_fs_event()`
- [ ] Debounce events (500ms) to coalesce rapid changes
- [ ] Ignore noise: `*.lock`, `ORIG_HEAD`, temp files
- [ ] Clear warning in docs about performance implications

**Files to create:**
- `lua/gitlad/watcher.lua` (new)

### 5.2 Submodule Support - COMPLETE
- [x] Show submodule status in status buffer (with status indicators)
- [x] `'` keybinding opens submodule popup
- [x] Actions: init, update (with fetch options), add, deinit
- [x] Switches: `--force`, `--recursive`, `--no-fetch`
- [ ] Config to disable submodule checking (future enhancement)

**Files created:**
- `lua/gitlad/popups/submodule.lua` - Submodule popup with switches and actions
- `lua/gitlad/ui/views/status.lua` - Submodules section rendering

### 5.3 User Configuration
- [ ] Customizable keybindings
- [ ] Per-popup keybinding overrides
- [ ] Color scheme / highlight customization
- [ ] Integration hooks (on_commit, on_push, etc.)

### 5.4 Documentation
- [ ] Vimdoc (`:help gitlad`)
- [ ] README with screenshots
- [ ] Example configurations

---

## Phase 6: Code Architecture Improvements (Future)

### 6.1 BufferBase Class Extraction

**Status:** Not started - documented for future refactoring

All three buffer views (status, log, history) share mechanical code that could be extracted to a base class.

**Current Duplication (~100 lines per view):**
1. **Singleton management** (~15 lines each): "If buffer exists and is valid, return it"
2. **Buffer setup** (~20 lines each): Create buffer, set `buftype=nofile`, `modifiable=false`, cleanup autocommands
3. **Window management** (~10 lines each): Open in window, set window-local options
4. **Lifecycle methods**: `close()`, `render()`, `_apply_highlights()`, `_place_signs()`

**Proposed structure:**
```lua
-- lua/gitlad/ui/buffer_base.lua
local BufferBase = {}
BufferBase.__index = BufferBase

function BufferBase:new(opts)
  -- Singleton check via opts.cache_key
  -- Create buffer with standard options
  -- Setup cleanup autocommands
end

function BufferBase:open()
  -- Window management, standard options
end

function BufferBase:close() ... end

-- Subclass hooks
function BufferBase:render() error("subclass must implement") end
function BufferBase:_setup_keymaps() error("subclass must implement") end
```

**Impact:** Would eliminate ~300 lines of boilerplate total

**Why deferred:** Too invasive for a cleanup PR; the current code works and is well-tested. Better to do this as a dedicated refactoring effort.

---

## Reference Projects

Cloned in parent directory:
- `../neogit/` - Popup system, comprehensive features, async patterns
- `../vim-fugitive/` - Performance patterns, vim-way design, caching
- `../lazygit/` - AsyncHandler pattern, loader architecture, Go but transferable

External dependency:
- `diffview.nvim` - Full-buffer diff views, side-by-side diffs, 3-way merge (we integrate rather than reinvent)

## Key Files to Study

**Neogit popup system:**
- `neogit/lua/neogit/lib/popup/builder.lua` - fluent API
- `neogit/lua/neogit/lib/popup/init.lua` - state management
- `neogit/lua/neogit/popups/commit/init.lua` - example popup

**Fugitive performance:**
- `vim-fugitive/autoload/fugitive.vim` - caching patterns (search for `s:*_cache`)

**Lazygit async:**
- `lazygit/pkg/tasks/async_handler.go` - request ordering pattern (already implemented)
