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

---

## Current State (Phase 1 Complete)

### What's Built
- Project structure with proper module organization
- Async git CLI wrapper (`git/cli.lua`) using `vim.fn.jobstart`
- Git output parsing (`git/parse.lua`) for porcelain v2 format
- Timestamp-based cache invalidation (`state/cache.lua`) - **to be removed/simplified**
- AsyncHandler pattern (`state/async.lua`) for request ordering
- Debounce/throttle utilities
- RepoState coordinator with event system (`state/init.lua`)
- Basic status buffer view with staging/unstaging
- Test infrastructure with mini.test (37 tests passing)
- CI workflow for Neovim stable/nightly

### Architecture Decisions Made
- Shell out to `git` (not libgit2) - simpler, portable, what others do
- Porcelain v2 format for stable machine-readable output
- Line map approach for buffer -> file mapping (no text parsing)
- Event-driven updates (RepoState emits events, views subscribe)

### Architecture Changes Needed
- **Remove automatic refresh after stage/unstage** (`state/init.lua:169-170, 184-185`)
- **Add optimistic state mutation** - Move file entries between sections on success
- **Add "Refreshing..." indicator** in status buffer during manual refresh
- **Add git command history module**

---

## Phase 2: Core Functionality

### 2.1 Optimistic State Updates (PRIORITY)

Refactor stage/unstage to update Lua state directly instead of refreshing from git.

- [ ] Add state mutation helpers to RepoState:
  - `move_to_staged(path)` - move entry from unstaged/untracked to staged
  - `move_to_unstaged(path)` - move entry from staged to unstaged
- [ ] Refactor `RepoState:stage()`:
  - Run `git add`
  - On success: call `move_to_staged(path)`, emit "status" event
  - On failure: show error, no state change
  - **Remove** `self:refresh_status()` call
- [ ] Refactor `RepoState:unstage()`:
  - Run `git reset HEAD`
  - On success: call `move_to_unstaged(path)`, emit "status" event
  - On failure: show error, no state change
  - **Remove** `self:refresh_status()` call
- [ ] Handle edge cases:
  - Staging untracked file (needs to set index_status appropriately)
  - Partially staged files (file in both staged and unstaged)

**Files to modify:**
- `lua/gitlad/state/init.lua`

### 2.2 Refresh Indicator

Show visual feedback during manual refresh so user knows it's working.

- [ ] Add `refreshing` boolean to RepoState
- [ ] Set `refreshing = true` at start of `refresh_status()`, `false` on completion
- [ ] Emit "refreshing" event (or include in "status" event)
- [ ] Update status buffer to show "Refreshing..." when `refreshing == true`
- [ ] Consider: spinner animation? Or just static text?

**Files to modify:**
- `lua/gitlad/state/init.lua`
- `lua/gitlad/ui/views/status.lua`

### 2.3 Git Command History

Track all git commands for transparency and debugging.

- [ ] Create `lua/gitlad/git/history.lua` module:
  - Ring buffer of last N commands (configurable, default 100)
  - Each entry: `{ cmd, args, cwd, exit_code, stdout, stderr, timestamp, duration_ms }`
- [ ] Integrate with `git/cli.lua` to log every command
- [ ] Add `$` keybinding to open command history buffer
- [ ] History buffer shows commands in reverse chronological order
- [ ] `RET` on a command expands to show full output

**Files to create:**
- `lua/gitlad/git/history.lua`
- `lua/gitlad/ui/views/history.lua`

**Files to modify:**
- `lua/gitlad/git/cli.lua`
- `lua/gitlad/ui/views/status.lua` (add `$` keybinding)

### 2.4 Full Magit Keybindings
- [ ] Navigation: `n`/`p` (next/prev item), `M-n`/`M-p` (next/prev section)
- [ ] `TAB` - expand/collapse section or show inline diff
- [ ] `RET` - visit file at point
- [ ] `s`/`u` - stage/unstage (done)
- [ ] `S`/`U` - stage all / unstage all
- [ ] `x` - discard changes at point (with confirmation)
- [ ] `g` - refresh (done)
- [ ] `q` - close (done)
- [ ] `$` - show git command history
- [ ] `?` - show help popup with all keybindings

**Files to modify:**
- `lua/gitlad/ui/views/status.lua`

### 2.5 Inline Diff Expansion
- [ ] `TAB` on file shows/hides diff inline
- [ ] Track expanded state per file in StatusBuffer
- [ ] Fetch diff async when expanding
- [ ] Syntax highlighting for diff (add/remove lines)
- [ ] Hunk headers clickable/navigable

**Files to modify:**
- `lua/gitlad/ui/views/status.lua`
- `lua/gitlad/git/init.lua` (add diff fetching)

### 2.6 Hunk-Level Staging
- [ ] Parse diff into hunks
- [ ] `s`/`u` on hunk stages/unstages just that hunk
- [ ] Use `git apply --cached` for hunk staging
- [ ] Visual feedback for partially staged files
- [ ] **Optimistic update:** On hunk stage success, update diff state without re-fetching

**Files to create/modify:**
- `lua/gitlad/git/diff.lua` (new - hunk parsing)
- `lua/gitlad/git/init.lua` (add `stage_hunk`, `unstage_hunk`)

### 2.7 Popup System
Port neogit's PopupBuilder pattern for transient-style menus.

- [ ] `lua/gitlad/ui/popup/builder.lua` - fluent API for building popups
- [ ] `lua/gitlad/ui/popup/init.lua` - popup state, rendering, key handling
- [ ] Support for:
  - Switches (boolean flags like `-a`, `--all`)
  - Options (key-value like `--author=`)
  - Actions (commands that execute)
  - Grouping with headings
- [ ] Persistent switch state between sessions

**Reference:** `/Users/dave/dev/actionshrimp/neogit/lua/neogit/lib/popup/`

### 2.8 Commit Popup
- [ ] `c` opens commit popup
- [ ] Switches: `-a` (all), `-e` (edit), `-v` (verbose), `--amend`
- [ ] Options: `--author=`, `--signoff`
- [ ] Actions:
  - `c` - Commit
  - `e` - Extend (amend without editing message)
  - `a` - Amend
  - `f` - Fixup
  - `s` - Squash
- [ ] Open `COMMIT_EDITMSG` in buffer for message editing
- [ ] Handle commit hooks (pre-commit, commit-msg)

**Files to create:**
- `lua/gitlad/popups/commit/init.lua`
- `lua/gitlad/popups/commit/actions.lua`

---

## Phase 3: Git Operations

### 3.1 Push Popup
- [ ] `P` opens push popup
- [ ] Switches: `--force-with-lease`, `--force`, `--dry-run`, `--tags`
- [ ] Options: remote selection, refspec
- [ ] Actions: push to upstream, push to different remote
- [ ] Show push progress (streaming output)

### 3.2 Pull/Fetch Popups
- [ ] `F` opens pull popup, `f` opens fetch popup
- [ ] Pull: `--rebase`, `--ff-only`, `--no-ff` switches
- [ ] Fetch: `--prune`, `--tags`, `--all` switches
- [ ] Remote selection

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

### 3.5 Diff View
- [ ] `d` opens diff popup
- [ ] Compare: working tree vs index, index vs HEAD, arbitrary refs
- [ ] Side-by-side or unified view (config option)
- [ ] Integration with existing diff plugins? (diffview.nvim)

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

### 4.2 Merge & Conflict Resolution
- [ ] `m` opens merge popup
- [ ] Show merge conflicts in status buffer
- [ ] `e` on conflicted file opens 3-way merge view
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

## Key Files to Study

**Neogit popup system:**
- `neogit/lua/neogit/lib/popup/builder.lua` - fluent API
- `neogit/lua/neogit/lib/popup/init.lua` - state management
- `neogit/lua/neogit/popups/commit/init.lua` - example popup

**Fugitive performance:**
- `vim-fugitive/autoload/fugitive.vim` - caching patterns (search for `s:*_cache`)

**Lazygit async:**
- `lazygit/pkg/tasks/async_handler.go` - request ordering pattern (already implemented)
