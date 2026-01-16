# gitlad.nvim Development Plan

## Current State (Phase 1 Complete)

### What's Built
- Project structure with proper module organization
- Async git CLI wrapper (`git/cli.lua`) using `vim.fn.jobstart`
- Git output parsing (`git/parse.lua`) for porcelain v2 format
- Timestamp-based cache invalidation (`state/cache.lua`)
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

---

## Phase 2: Core Functionality

### 2.1 File Watcher
- [ ] Watch `.git/` directory using `vim.loop.new_fs_event()`
- [ ] Debounce events (200ms) to coalesce rapid changes
- [ ] Ignore noise: `*.lock`, `ORIG_HEAD`, temp files
- [ ] Auto-refresh status on relevant changes
- [ ] Config option to disable (`watch_gitdir = false`)

**Files to create/modify:**
- `lua/gitlad/watcher.lua` (new)
- `lua/gitlad/state/init.lua` (integrate watcher)

### 2.2 Full Magit Keybindings
- [ ] Navigation: `n`/`p` (next/prev item), `M-n`/`M-p` (next/prev section)
- [ ] `TAB` - expand/collapse section or show inline diff
- [ ] `RET` - visit file at point
- [ ] `s`/`u` - stage/unstage (done)
- [ ] `S`/`U` - stage all / unstage all
- [ ] `x` - discard changes at point (with confirmation)
- [ ] `g` - refresh (done)
- [ ] `q` - close (done)
- [ ] `?` - show help popup with all keybindings

**Files to modify:**
- `lua/gitlad/ui/views/status.lua`

### 2.3 Inline Diff Expansion
- [ ] `TAB` on file shows/hides diff inline
- [ ] Track expanded state per file in StatusBuffer
- [ ] Fetch diff async when expanding
- [ ] Syntax highlighting for diff (add/remove lines)
- [ ] Hunk headers clickable/navigable

**Files to modify:**
- `lua/gitlad/ui/views/status.lua`
- `lua/gitlad/git/init.lua` (add diff fetching)

### 2.4 Hunk-Level Staging
- [ ] Parse diff into hunks
- [ ] `s`/`u` on hunk stages/unstages just that hunk
- [ ] Use `git apply --cached` for hunk staging
- [ ] Visual feedback for partially staged files

**Files to create/modify:**
- `lua/gitlad/git/diff.lua` (new - hunk parsing)
- `lua/gitlad/git/init.lua` (add `stage_hunk`, `unstage_hunk`)

### 2.5 Popup System
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

### 2.6 Commit Popup
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

## Phase 5: Polish & Performance

### 5.1 Large Repo Performance
- [ ] Profile on large monorepos (1M+ files)
- [ ] Optimize status refresh (sparse checkout awareness?)
- [ ] Lazy loading of sections
- [ ] Virtual scrolling for long file lists?

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
