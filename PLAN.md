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

## Current State (Phase 2.1-2.6 Complete)

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
- Test infrastructure with mini.test (230 tests passing)
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

### 3.3 Branch Popup
- [ ] `b` opens branch popup
- [ ] Actions: checkout, create, delete, rename
- [ ] Create from: current HEAD, specific ref, remote branch
- [ ] Track remote branches
- [ ] Show branch list with current indicator

### 3.4 Log View
- [ ] `l` opens log popup, then actions open log buffer
- [ ] Show commit list with: hash, author, date, message
- [ ] Navigation through commits
- [ ] `RET` on commit shows commit details
- [ ] `d` shows diff for commit
- [ ] Limit options: `-n`, `--since`, `--author`, path filtering

**Files to create:**
- `lua/gitlad/ui/views/log.lua`
- `lua/gitlad/popups/log/init.lua`

### 3.5 Diff View (via diffview.nvim)

**Note:** Full-buffer diff views delegate to `diffview.nvim` - see "Leverage diffview.nvim" section above.

- [ ] `d` opens diff popup
- [ ] Actions invoke `diffview.nvim` commands:
  - Compare working tree vs index → `:DiffviewOpen`
  - Compare index vs HEAD → `:DiffviewOpen --cached`
  - Compare arbitrary refs → `:DiffviewOpen ref1..ref2`
- [ ] Graceful fallback if diffview.nvim not installed (error message with install hint)
- [ ] Optional: config to use built-in `vimdiff` instead

### 3.6 Stash Popup
- [ ] `z` opens stash popup
- [ ] Actions: stash, pop, apply, drop, list
- [ ] Switches: `--include-untracked`, `--keep-index`
- [ ] Show stash list, preview stash contents

---

## Phase 4: Advanced Features

### 4.1 Interactive Rebase
- [ ] `r` opens rebase popup
- [ ] Actions: interactive, onto, continue, abort, skip
- [ ] Rebase editor buffer for reordering commits
- [ ] pick/reword/edit/squash/fixup/drop commands
- [ ] Handle rebase conflicts

### 4.2 Merge & Conflict Resolution (3-way merge via diffview.nvim)

**Note:** 3-way merge views delegate to `diffview.nvim` - see "Leverage diffview.nvim" section above.

- [ ] `m` opens merge popup
- [ ] Show merge conflicts in status buffer
- [ ] `e` on conflicted file opens diffview.nvim's merge tool (`:DiffviewOpen` with merge conflict handling)
- [ ] Mark resolved with `s` (stage)
- [ ] Abort/continue merge actions

### 4.3 Blame View
- [ ] `:Gitlad blame` or `B` from file
- [ ] Show blame annotations inline
- [ ] Navigate to commit from blame line
- [ ] Blame at specific revision

### 4.4 Cherry-pick & Revert
- [ ] `A` cherry-pick popup
- [ ] `V` revert popup
- [ ] Handle conflicts

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

### 5.2 Submodule Support
- [ ] Show submodule status (async, non-blocking!)
- [ ] Config to disable submodule checking
- [ ] Actions: update, init, sync

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
