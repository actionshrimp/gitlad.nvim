# gitlad.nvim Development Guide

## Kaizen: Continuous Improvement

**This is a living document.** When you notice something that could be improved—a process that's too slow, documentation that's unclear, a pattern that keeps causing bugs—**speak up and suggest changes** to this guide and PLAN.md.

---

**Important**: Check TODOS.md for known issues and outstanding work items.

## Project Vision

A fast, well-tested git interface for Neovim inspired by magit, fugitive, and lazygit. Key differentiators:

- **Performance-first**: Optimistic state updates, no automatic git syncing (critical for large monorepos)
- **Properly tested**: Comprehensive automated tests are mandatory, not optional
- **Magit UX**: Transient-style popup menus and evil-collection-magit keybindings
- **Transparent**: Git command history shows exactly what commands are running
- **GitHub-integrated**: Forge features for PR management and code review (via `N` popup)
- **Native diff viewer**: Built-in side-by-side diff replaces external dependencies

### Core Performance Principle

**No automatic git syncing.** In large monorepos (1M+ files), `git status` can take seconds. Instead:

1. **Manual refresh only** - User presses `gr` to refresh, with visual "Refreshing..." indicator
2. **Optimistic updates** - When staging/unstaging, run git command, check exit code, update Lua state directly
3. **Git command history** - `$` shows all git commands run, their output, and exit codes

### Diff Viewing Strategy

gitlad.nvim has a **native diff viewer** that replaces the diffview.nvim dependency:

| What | Who handles it |
|------|----------------|
| **Status buffer inline diffs** (hunk preview, hunk staging) | gitlad.nvim (existing) |
| **Full-buffer diff views** (side-by-side, commit diffs, file history) | gitlad.nvim native diff viewer |
| **PR review diffs** (inline comments, review threads) | gitlad.nvim native diff viewer + forge module (Milestone 5) |
| **3-way merge conflict resolution** | Planned for Milestone 6 |

The native diff viewer opens in a new tab page with a file panel sidebar and two synchronized side-by-side buffers. It supports staged, unstaged, worktree, commit, range, stash, and PR diffs with word-level inline highlighting.

## Current Status

**What's built (core git workflow is complete):**
- Async git CLI wrapper with porcelain v2 parsing
- Elm Architecture (Commands/Reducer) for predictable state updates
- Optimistic state updates - instant UI response without git status refresh
- Status buffer with full staging workflow (file, hunk, visual selection)
- Inline diff expansion with syntax highlighting
- Git command history view (`$` keybinding)
- Transient-style popup system (PopupBuilder)
- All git operation popups: Commit, Push, Pull, Fetch, Branch, Log, Diff, Stash, Rebase, Cherry-pick, Revert, Reset, Merge
- Interactive rebase editor (evil-collection style)
- Instant fixup/squash (`c F` / `c S`)
- Sequencer state detection (cherry-pick/revert in progress)
- Submodule popup, Refs popup/view, Reflog view, Blame view
- Streaming output viewer for git hook output
- File watcher with stale indicator
- 970+ tests across 75+ test files, CI configured

**Current focus: GitHub forge integration + native diff viewer** — See PLAN.md.

## Golden Rule: Automated Testing

**Every change MUST include automated tests. No exceptions.**

Code without tests is incomplete code.

### Non-Negotiable Requirements

1. **NEVER ask the user to manually test changes** - This is disrespectful of their time
2. **NEVER consider work complete until `make test` passes** - Run tests yourself
3. **NEVER submit code without corresponding tests** - Untested code is broken code
4. **ALWAYS run `make test` before declaring any task done** - Verify it yourself
5. **ALWAYS fix failing tests before moving on** - Don't leave broken tests behind
6. **ALWAYS check if tests exist for changed code** - If you modify a function and there are no tests for it, add them

### Test-First Development

- Write tests BEFORE or ALONGSIDE implementation, not after
- If you're unsure how something should behave, write a test to specify it
- Tests are documentation - they show how the code is meant to be used
- If a bug is found, write a failing test first, then fix it

### What Requires Tests

| Change Type | Required Tests |
|-------------|----------------|
| New module/function | Unit tests for all public functions |
| Bug fix | Regression test that would have caught the bug |
| New UI feature | E2E test verifying the interaction |
| Refactoring | Existing tests must still pass (no new tests needed if behavior unchanged) |
| New keybinding | Test that the mapping exists and triggers correct action |
| Git operation | Test with isolated test repo via helpers |
| Modifying existing code | Check if tests exist; if not, add them before or alongside the change |

**Important:** When fixing a bug in code that lacks tests, write the tests first. This ensures the bug is properly specified and prevents regressions.

### Test Quality Standards

- Tests must be deterministic (no flaky tests)
- Tests must be isolated (no shared state between tests)
- Unit tests must be very fast (< 1s each)
- **E2E tests are cheap in this project** — don't shy away from writing them. They catch real integration issues that unit tests miss. When in doubt, write an E2E test.
- E2E tests should use condition-based waits where possible — see `helpers.wait_for_*` functions
- Test names must describe the expected behavior
- Use `before_each` hooks to reset state

### Running Tests

```bash
# Install dependencies (mini.nvim)
make deps

# Run all tests
make test

# Run only unit tests
make test-unit

# Run only e2e tests
make test-e2e

# Run a single test file for a feature that's being iterated on
make test-file FILE=tests/e2e/test_rebase.lua
```

**Important:** When iterating on a specific feature, run just that test file directly — this speeds up iteration considerably. Once the task appears done, run `make test` to verify everything passes.

### Local Development

```bash
# Run Neovim with the plugin loaded (from project directory)
make dev

# Then use :Gitlad to open status view
```

### Writing Lua

If you need to try out any isolated snippets of lua that don't require the vim environment, the `lua` CLI command is available for a lua interpreter.

### Test Structure

- `tests/unit/` - Pure Lua unit tests (fast, isolated)
- `tests/e2e/` - Full Neovim integration tests (comprehensive, condition-based waits)
- `tests/helpers.lua` - Shared test utilities
- `tests/minimal_init.lua` - Test environment setup

### Writing Tests

Use mini.test framework:

```lua
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["module"]["describes behavior"] = function()
  -- Arrange
  local thing = require("gitlad.thing")

  -- Act
  local result = thing.do_something()

  -- Assert
  eq(result, expected)
end

return T
```

For testing git operations, use the helpers to create isolated test repos:

```lua
local helpers = require("tests.helpers")
-- helpers.create_test_repo(child)
-- helpers.create_file(child, repo, "file.txt", "content")
-- helpers.git(child, repo, "add .")
```

## Architecture

### Directory Structure

```
lua/gitlad/
├── init.lua              # Entry point, setup()
├── config.lua            # User configuration
├── commands.lua          # :Gitlad command dispatcher
├── constants.lua         # Shared constants (section types, etc.)
├── git/
│   ├── init.lua          # High-level git operations
│   ├── cli.lua           # Async job execution (vim.fn.jobstart)
│   ├── parse.lua         # Git output parsers (porcelain v2)
│   └── history.lua       # Git command history ring buffer
├── forge/                # GitHub/forge integration (in progress)
│   ├── init.lua          # Provider detection from remote URL, auth check
│   ├── http.lua          # Async HTTP client (curl + jobstart)
│   ├── types.lua         # Shared forge types (PR, Review, Comment)
│   └── github/
│       ├── init.lua      # GitHub provider implementation
│       ├── graphql.lua   # GraphQL queries and response parsing
│       ├── pr.lua        # PR operations
│       └── review.lua    # Review/comment operations
├── state/
│   ├── init.lua          # RepoState coordinator + optimistic updates
│   ├── commands.lua      # Elm-style command definitions
│   ├── reducer.lua       # Pure state reducer (commands → state)
│   ├── cache.lua         # Timestamp-based cache utilities
│   └── async.lua         # AsyncHandler, debounce, throttle
├── utils/
│   ├── init.lua          # Utility module index
│   ├── errors.lua        # Centralized error handling
│   ├── keymap.lua        # Buffer-local keymap helpers
│   └── prompt.lua        # Ref prompt with completion (magit-style)
├── popups/
│   ├── branch.lua        # Branch popup (checkout, create, delete, rename)
│   ├── cherrypick.lua    # Cherry-pick popup with conflict detection
│   ├── commit.lua        # Commit popup with switches/options/actions
│   ├── diff.lua          # Diff popup (routes to native diff viewer)
│   ├── fetch.lua         # Fetch popup
│   ├── forge.lua         # Forge popup (N keybinding, GitHub PRs)
│   ├── help.lua          # Help popup showing all keybindings
│   ├── log.lua           # Log popup and view
│   ├── merge.lua         # Merge popup with conflict resolution
│   ├── pull.lua          # Pull popup with rebase/ff options
│   ├── push.lua          # Push popup with force/upstream options
│   ├── rebase.lua        # Rebase popup (interactive, onto, continue, abort)
│   ├── refs.lua          # References popup for branch/tag comparison
│   ├── reset.lua         # Reset popup (mixed, soft, hard, keep)
│   ├── revert.lua        # Revert popup with conflict detection
│   ├── stash.lua         # Stash popup (push, pop, apply, drop)
│   └── submodule.lua     # Submodule popup (init, update, add, deinit)
└── ui/
    ├── popup/
    │   └── init.lua      # PopupBuilder - transient-style popup system
    ├── components/
    │   ├── log_list.lua  # Reusable commit list component
    │   ├── pr_list.lua   # Reusable PR list component
    │   ├── comment.lua   # Comment/thread rendering component
    │   └── checks.lua    # CI checks section component
    ├── hl.lua            # Highlight groups and namespace management
    └── views/
        ├── status.lua        # Main status buffer view
        ├── log.lua           # Log view buffer
        ├── refs.lua          # References view buffer
        ├── blame.lua         # Side-by-side blame view
        ├── commit_editor.lua # Commit message editor buffer
        ├── rebase_editor.lua # Interactive rebase todo editor
        ├── output.lua        # Streaming output viewer (git hooks)
        ├── history.lua       # Git command history view
        ├── pr_list.lua       # PR list buffer
        ├── pr_detail.lua     # PR detail/discussion buffer
        └── diff/             # Native diff viewer
            ├── init.lua      # DiffView coordinator
            ├── types.lua     # Type definitions
            ├── hunk.lua      # Hunk parsing, side-by-side alignment
            ├── source.lua    # DiffSpec producers
            ├── content.lua   # File content retrieval + alignment
            ├── buffer.lua    # Side-by-side buffer pair
            ├── panel.lua     # File panel sidebar + commit selector
            └── inline.lua    # Word-level inline diff
```

### Key Patterns

1. **Elm Architecture: Commands + Reducer** (`state/commands.lua`, `state/reducer.lua`)
   - Commands are data structures describing state changes (stage_file, unstage_file, etc.)
   - Reducer is a pure function: `(status, command) → new_status`
   - Enables predictable, testable state transitions
   - State is immutable - reducer returns new state, doesn't mutate

2. **Optimistic State Updates** (`state/init.lua`)
   - On stage/unstage: run git command, check exit code
   - On success: create command, apply via reducer, notify listeners
   - On failure: show error, state unchanged
   - **Never** automatically call `git status` after operations

3. **Event-Driven Views** (`state/init.lua`, `ui/views/status.lua`)
   - RepoState emits events ("status") when state changes
   - Views subscribe to events and re-render on notification
   - Decouples state management from UI rendering

4. **Git Command History** (`git/history.lua`)
   - Ring buffer of all git commands run
   - Each entry: command, args, exit code, stdout, stderr, duration
   - Accessible via `$` keybinding

5. **AsyncHandler** (`state/async.lua`)
   - Tracks request IDs for manual refreshes
   - Only applies the latest result
   - Prevents stale async results from overwriting fresh data

6. **Porcelain v2 parsing** (`git/parse.lua`)
   - Uses `git status --porcelain=v2` for stable output
   - Machine-readable, won't break with git updates

7. **PopupBuilder** (`ui/popup/init.lua`)
   - Fluent API for building transient-style popups
   - Switches (boolean), options (key-value), actions (callbacks)
   - Choice options with `vim.ui.select`, mutually exclusive switches
   - Used by all git operation popups (commit, push, pull, etc.)

8. **Reusable Components** (`ui/components/`)
   - Stateless render functions: take data + options, return `{ lines, line_info, ranges }`
   - `log_list.lua`: Renders commit lists with expandable details
   - Used by both status view (unpushed/unpulled sections) and log view
   - **New components should follow this same pattern**

9. **Singleton Buffer Views** (`ui/views/log.lua`, `ui/views/refs.lua`, etc.)
   - One buffer instance per repo root, keyed by `repo_root`
   - `buftype=nofile`, `bufhidden=hide`, cleanup via `BufWipeout` autocmd
   - `line_map` table mapping line numbers to metadata for context-aware actions
   - Standard keymaps: `gj`/`gk` navigate, `gr` refresh, `q` close, `?` help

10. **Ref Prompts with Picker/Completion** (`utils/prompt.lua`)
    - Three-tier picker with graceful fallback: snacks.nvim → mini.pick → vim.ui.input
    - Shows suggestions (branches, tags, recent commits) while accepting arbitrary input
    - **Preferred pattern** for any feature needing user to select a ref, commit, or branch

11. **Async HTTP Client** (`forge/http.lua`)
    - `curl` + `vim.fn.jobstart` (same async pattern as `git/cli.lua`)
    - Auth token from `gh auth token` — no custom OAuth
    - Used for GitHub GraphQL/REST API calls
    - `gh` CLI only for: auth, `gh pr checkout`, `gh pr create`, `gh pr merge`

## Keybindings (evil-collection-magit Style)

**Note:** We follow [evil-collection-magit](https://github.com/emacs-evil/evil-collection/blob/master/modes/magit/evil-collection-magit.el) conventions, not vanilla magit. Key differences from vanilla magit:
- `j`/`k` for standard line movement (vim default)
- `gj`/`gk` for section sibling navigation (jump to next/previous file or commit)
- Push uses `p` (lowercase) instead of `P`

This makes the plugin more comfortable for vim/evil users.

**Important:** When adding new keybindings, always update the relevant sections below AND the help popup (`popups/help.lua`). Keybinding documentation must stay in sync with the implementation.

### Navigation
| Key | Action |
|-----|--------|
| `j` / `k` | Normal line movement (vim default) |
| `gj` / `gk` | Next/previous file or commit |
| `M-n` / `M-p` | Next/previous section |
| `TAB` | Expand/collapse section or diff |
| `RET` | Visit file at point |

### Staging
| Key | Action |
|-----|--------|
| `s` | Stage item/hunk at point |
| `u` | Unstage item/hunk at point |
| `x` | Discard changes at point |
| `S` | Stage all |
| `U` | Unstage all |

### Popup Triggers
| Key | Popup |
|-----|-------|
| `c` | Commit |
| `b` | Branch |
| `f` | Fetch |
| `F` | Pull |
| `p` | Push |
| `l` | Log |
| `d` | Diff |
| `m` | Merge |
| `r` | Rebase |
| `z` | Stash |
| `A` | Cherry-pick |
| `_` | Revert |
| `X` | Reset |
| `'` | Submodule |
| `yr` | References |
| `N` | Forge (GitHub PRs) |
| `B` | Blame (from status view) |
| `t` | Tag (not yet implemented) |
| `!` | Run git command (not yet implemented) |

### Log Popup Reflog Actions
| Key | Action |
|-----|--------|
| `l r` | Reflog current branch |
| `l O` | Reflog other ref (prompts) |
| `l H` | Reflog HEAD |

### Reflog View
| Key | Action |
|-----|--------|
| `gj` / `gk` | Next/previous entry |
| `<CR>` | Show commit diff |
| `y` | Yank commit hash |
| `gr` | Refresh |
| `q` | Close |
| `A` | Cherry-pick popup |
| `X` | Reset popup |
| `b` / `c` / `r` / `d` | Branch/Commit/Rebase/Diff popups |

### Log View
| Key | Action |
|-----|--------|
| `gj` / `gk` | Next/previous commit |
| `<CR>` | Show commit diff |
| `<Tab>` | Expand/collapse commit details |
| `y` | Yank commit hash |
| `+` | Double commit limit |
| `-` | Halve commit limit |
| `=` | Toggle limit (remove/reset to 256) |
| `gr` | Refresh |
| `q` | Close |
| `b` / `c` / `r` / `d` | Branch/Commit/Rebase/Diff popups |
| `A` / `_` / `X` | Cherry-pick/Revert/Reset popups |

### Blame View
| Key | Action |
|-----|--------|
| `gj` / `gk` | Next/previous blame chunk |
| `gJ` / `gK` | Next/previous same-commit chunk |
| `<CR>` | Show commit diff |
| `b` | Blame at parent (blame-on-blame) |
| `y` | Yank commit hash |
| `B` | Blame popup (switches: -w, -M, -C) |
| `gr` | Refresh |
| `q` | Close |

### Diff Viewer
| Key | Action |
|-----|--------|
| `q` | Close diff view (close tab) |
| `gj` / `gk` | Next/previous file |
| `]c` / `[c` | Next/previous hunk |
| `<CR>` | Select file (in panel) |
| `gr` | Refresh |
| `C-n` / `C-p` | Next/previous commit (PR mode) |

### Forge Popup Actions
| Key | Action |
|-----|--------|
| `N l` | List pull requests |
| `N v` | View current branch PR |
| `N c` | Checkout PR branch |
| `N n` | Create pull request (opens `gh pr create --web`) |
| `N m` | Merge pull request (prompts for PR# and strategy) |
| `N C` | Close pull request |
| `N R` | Reopen pull request |
| `N o` | Open current branch PR in browser |

### PR List View
| Key | Action |
|-----|--------|
| `gj` / `gk` | Next/previous PR |
| `<CR>` | View PR detail |
| `y` | Yank PR number |
| `o` | Open in browser |
| `gr` | Refresh |
| `q` | Close |
| `?` | Show help |

### PR Detail View
| Key | Action |
|-----|--------|
| `gj` / `gk` | Next/previous comment/check |
| `<CR>` | Open check in browser (on check line) |
| `<Tab>` | Toggle checks section collapsed/expanded |
| `c` | Add comment |
| `e` | Edit comment at cursor |
| `y` | Yank PR number |
| `o` | Open PR in browser |
| `d` | View diff in native diff viewer |
| `gr` | Refresh |
| `q` | Close |
| `?` | Show help |

### Comment Editor
| Key | Action |
|-----|--------|
| `C-c C-c` | Submit comment |
| `C-c C-k` | Abort |
| `ZZ` | Submit comment |
| `ZQ` | Abort |
| `q` | Abort (normal mode) |

### Rebase Editor (when editing git-rebase-todo)

The rebase editor is a normal vim buffer. Use standard vim motions to edit freely.
Action abbreviations (e.g. `f` → `fixup`) auto-expand when you leave insert mode.

| Key | Action |
|-----|--------|
| `cw f<Esc>` | Change action to fixup (auto-expands from `f`) |
| `dd` | Delete (drop) a commit line |
| `ddp` | Move commit down (cut + paste below) |
| `ddkP` | Move commit up (cut + paste above) |
| `ZZ` / `C-c C-c` | Submit (apply rebase) |
| `ZQ` / `C-c C-k` | Abort (cancel rebase) |
| `<CR>` | Show commit at point |
| `q` | Close (prompts to save if modified) |

### Commit Popup Actions
| Key | Action |
|-----|--------|
| `c c` | Commit (opens editor) |
| `c e` | Extend (amend without editing) |
| `c w` | Reword (edit message only) |
| `c a` | Amend (amend with editor) |
| `c F` | Instant fixup (fixup + autosquash rebase) |
| `c S` | Instant squash (squash + autosquash rebase) |

### Rebase Popup Actions
| Key | Action |
|-----|--------|
| `r i` | Interactive rebase (uses commit at point as target) |
| `r p` | Rebase onto pushremote |
| `r u` | Rebase onto upstream |
| `r e` | Rebase elsewhere (prompts for branch) |

### Other
| Key | Action |
|-----|--------|
| `gr` | Refresh |
| `q` | Close buffer |
| `$` | Show git process output |
| `?` | Show help / all keybindings |

## Development Plan

See **PLAN.md** for the detailed development roadmap. Current focus:

1. **Milestone 1**: Forge foundation — HTTP client, GitHub GraphQL, forge popup (`N`), PR list
2. **Milestone 2**: PR management — detail view, comments, actions
3. **Milestone 3**: CI checks viewer — check status in PR list, detail, and status buffer (done)
4. **Milestone 4**: Native diff viewer — replacing diffview.nvim (done)
5. **Milestone 5**: PR review — inline comments in native diff viewer
6. **Milestone 6**: Polish — 3-way merge, PR creation, notifications

Milestones 1-2 (forge) and Milestone 4 (diff viewer) are independent and can proceed in parallel.

## Reference Projects

Cloned in parent directory for reference:

- `dev/magit/` - Popup system architecture, comprehensive features, forge integration
- `dev/evil-collection/` - Canonical keybindings reference
- `dev/vim-fugitive/` - Performance patterns, vim-way design
- `dev/lazygit/` - AsyncHandler pattern, loader architecture
- `dev/neogit/` - Useful for neovim-specific details, but strongly prefer magit for overarching design!

## Development Workflow

### Starting a New Feature

> **CRITICAL: Always start from an up-to-date main branch!**
>
> Before starting ANY new work, you MUST fetch and update main first.

```bash
git checkout main
git fetch origin
git reset --hard origin/main   # Ensure local main matches remote
git checkout -b feature/your-feature-name
```

**Never skip this step.** Even if you think main hasn't changed, always verify.

### Planning First

**For bigger features, use plan mode before writing any code.** This ensures we:
- Understand the current goal clearly
- Break the work into a sequence of logical, atomic steps
- Identify what tests, keybindings, and documentation each step needs
- Avoid scope creep and stay focused

Each logical step in the plan should be implementable as a single commit.

### Test-First Development

Every task follows this workflow:

```
1. Understand the requirement
2. Write/update tests that specify the behavior
3. Run `make test` - new tests should FAIL (they test unimplemented behavior)
4. Implement the feature/fix
5. Run `make test` - all tests should PASS
6. Run `make lint` - code should be formatted
7. Only then is the task complete
```

**If you skip step 5, the task is NOT complete.**

### Atomic Commits

Each logical step from the plan should be committed as a complete unit. A commit is complete when it includes **all** of the following (as applicable):

| Component | Description |
|-----------|-------------|
| **Tests** | Both unit tests and e2e tests for the new functionality |
| **Implementation** | The feature/fix code itself |
| **Keybindings** | Any new mappings, their tests, AND updates to help popup and CLAUDE.md keybinding docs |
| **Documentation** | Update keybinding tables, PLAN.md progress, help popup entries |

**Every commit must pass all checks:**
```bash
make format   # Format code (runs automatically via hook on file changes)
make lint     # Check formatting
make test     # Run all tests (unit + e2e)
```

Do not move to the next logical step until the current commit is complete and green.

### Documentation Maintenance

**Keep keybinding documentation in sync.** When adding or changing keybindings:

1. Update the **help popup** (`popups/help.lua`) — this is what users see with `?`
2. Update the **keybinding tables in this file** (CLAUDE.md) — this is the developer reference
3. Add **tests** that verify the keybinding exists and triggers the correct action

Stale documentation is worse than no documentation. If you notice keybindings that are documented but don't match the implementation (or vice versa), fix the discrepancy.

### PR-Based Workflow

Once you have a commit or sequence of commits for a higher-level goal:

1. **Local Review** - Use a sub-agent to review all changes locally
2. **Submit PR** - Push the branch and create a PR, wait for CI
3. **PR Review** - Use a sub-agent to review the PR, address feedback
4. **Human Approval** - Once everything is green, notify the human. **Never merge without human sign-off.**

## Code Style

- Format with stylua (`make format`) — runs automatically via PostToolUse hook
- 2-space indentation
- 100 character line width
- Use LuaCATS annotations for types (`---@param`, `---@return`, etc.)

## CI Requirements

All PRs must pass:
1. Tests on Neovim stable
2. Tests on Neovim nightly
3. stylua lint check

## Debugging Test Failures

When tests fail:

1. Read the error message carefully
2. Run the specific failing test in isolation: `make test-file FILE=<path>`
3. Add print statements if needed (remove before committing)
4. Check if it's a timing issue (async tests may need condition-based waits via `helpers.wait_for_*`)
5. Never mark a task complete with failing tests
