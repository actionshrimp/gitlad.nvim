# gitlad.nvim Development Guide

## ⚠️ Kaizen: Continuous Improvement

**This is a living document.** Our development practices should evolve as we learn.

When you notice something that could be improved—whether it's a process that's too slow, documentation that's unclear, a pattern that keeps causing bugs, or a tool that could help—**speak up and suggest changes** to this guide and PLAN.md.

Examples of improvements to watch for:
- Repetitive manual steps that could be automated
- Test patterns that are brittle or hard to maintain
- Documentation gaps that caused confusion
- Better ways to structure code or tests
- Tools or plugins that could speed up development

**Don't just follow the process—help improve it.**

---

**Important**: If TODOs are mentioned, make sure to check in the TODOS.md file.

## Project Vision

A fast, well-tested git interface for Neovim inspired by magit, fugitive, and lazygit. Key differentiators:

- **Performance-first**: Optimistic state updates, no automatic git syncing (critical for large monorepos)
- **Properly tested**: Comprehensive automated tests are mandatory, not optional
- **Magit UX**: Transient-style popup menus and magit keybindings
- **Transparent**: Git command history shows exactly what commands are running

### Core Performance Principle

**No automatic git syncing.** In large monorepos (1M+ files), `git status` can take seconds. Instead:

1. **Manual refresh only** - User presses `gr` to refresh, with visual "Refreshing..." indicator
2. **Optimistic updates** - When staging/unstaging, run git command, check exit code, update Lua state directly
3. **Git command history** - `$` shows all git commands run, their output, and exit codes

### Leverage diffview.nvim for Full-Buffer Diffs

**Don't reinvent the wheel.** For full-buffer diff views, delegate to `diffview.nvim`:

| What | Who handles it |
|------|----------------|
| **Status buffer inline diffs** (hunk preview, hunk staging) | gitlad.nvim (our own implementation) |
| **Full-buffer diff views** (side-by-side, commit diffs, file history) | diffview.nvim |
| **3-way merge conflict resolution** | diffview.nvim |

This keeps gitlad.nvim focused on the status/staging workflow while leveraging diffview.nvim's mature diff rendering.

## Golden Rule: Automated Testing

**Every change MUST include automated tests. No exceptions.**

This is the most important rule in this codebase. Code without tests is incomplete code.

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
- Unit tests must be very fast (unit tests < 1s each)
- **Important**: E2E tests should aim to be cover as many user-facing scenarios as possible.
- **Important**: E2E tests should use condition based waits where possible - see the `helpers.wait_for_*` functions
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
**Important:** If iterating on a particular feature, consider running just that test file directly, rather than the whole suite - this will speed up iteration times considerably. However, once the whole task appears to be done, make sure you run `make test` to verify everything passes.

### Local Development

```bash
# Run Neovim with the plugin loaded (from project directory)
make dev

# Then use :Gitlad to open status view
```

### Writing lua

If you need to try out any isolated snippets of lua that don't require the vim
environment, the `lua` CLI command is available for a lua interpreter.

### Test Structure

- `tests/unit/` - Pure Lua unit tests (fast, isolated)
- `tests/e2e/` - Full Neovim integration tests (slower, comprehensive)
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
│   ├── diff.lua          # Diff popup (integrates with diffview.nvim)
│   ├── fetch.lua         # Fetch popup
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
    │   └── log_list.lua  # Reusable commit list component
    ├── hl.lua            # Highlight groups and namespace management
    └── views/
        ├── status.lua        # Main status buffer view
        ├── log.lua           # Log view buffer
        ├── refs.lua          # References view buffer
        ├── commit_editor.lua # Commit message editor buffer
        ├── rebase_editor.lua # Interactive rebase todo editor
        ├── output.lua        # Streaming output viewer (git hooks)
        └── history.lua       # Git command history view
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
   - Used by all git operation popups (commit, push, pull, etc.)

8. **Reusable Components** (`ui/components/`)
   - `log_list.lua`: Renders commit lists with expandable details
   - Used by both status view (unpushed/unpulled sections) and log view
   - Configurable via options (indent, hash length, author/date display)

9. **Utility Modules** (`utils/`)
   - `errors.lua`: Centralized error handling (`result_to_callback`, `notify`)
   - `keymap.lua`: Simplified buffer-local keymap setup
   - Reduces duplication and ensures consistent patterns across codebase

10. **Ref Prompts with Picker/Completion** (`utils/prompt.lua`)
    - Three-tier picker with graceful fallback: snacks.nvim → mini.pick → vim.ui.input
    - Shows suggestions (branches, tags, recent commits) while accepting arbitrary input
    - Matches magit's `completing-read` with `require-match = 'any'` behavior
    - **Preferred pattern** for any feature needing user to select a ref, commit, or branch
    - No forced dependencies - works with whatever picker the user has installed
    - Example: `prompt.prompt_for_ref({ prompt = "Rebase onto: " }, callback)`

## Keybindings (evil-collection-magit Style)

**Note:** We follow [evil-collection-magit](https://github.com/emacs-evil/evil-collection/blob/master/modes/magit/evil-collection-magit.el) conventions, not vanilla magit. Key differences from vanilla magit:
- `j`/`k` for standard line movement (vim default)
- `gj`/`gk` for section sibling navigation (jump to next/previous file or commit)
- Push uses `p` (lowercase) instead of `P`

This makes the plugin more comfortable for vim/evil users.

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

### Rebase Editor (when editing git-rebase-todo)
| Key | Action |
|-----|--------|
| `p` | Pick (use commit) |
| `r` | Reword (edit message) |
| `e` | Edit (stop for amending) |
| `s` | Squash (meld into previous) |
| `f` | Fixup (meld, discard message) |
| `d` | Drop (remove commit) |
| `x` | Exec (insert shell command) |
| `b` | Break (insert break line) |
| `M-j` / `M-k` | Move commit down/up |
| `ZZ` / `C-c C-c` | Submit (apply rebase) |
| `ZQ` / `C-c C-k` | Abort (cancel rebase) |
| `<CR>` | Show commit at point |

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

See **PLAN.md** for the detailed development roadmap with specific tasks, files to create/modify, and implementation notes.

### Current Status: Phase 4 Nearly Complete

**What's built:**
- Async git CLI wrapper with porcelain v2 parsing
- Elm Architecture (Commands/Reducer) for predictable state updates
- Optimistic state updates - instant UI response without git status refresh
- Status buffer with full staging workflow (file, hunk, visual selection)
- Inline diff expansion with syntax highlighting
- Git command history view (`$` keybinding)
- Transient-style popup system (PopupBuilder)
- Log view with expandable commit details, reusable log_list component
- All Phase 3 popups: Commit, Push, Pull, Fetch, Branch, Log, Diff, Stash
- Phase 4 popups: Rebase, Cherry-pick, Revert, Reset, Merge
- Interactive rebase editor with p/r/e/s/f/d keybindings (evil-collection style)
- Instant fixup/squash (`c F` / `c S`) - creates fixup commit and rebases immediately
- Sequencer state detection (shows cherry-pick/revert in progress)
- Submodule popup (`'` keybinding) - init, update, add, deinit
- Refs popup and view (`yr` keybinding) - branch/tag comparison
- Streaming output viewer for git hook output
- 940+ tests across 73 test files, CI configured

**Next up:**
- Tag popup
- Blame view

See PLAN.md for the detailed roadmap.

## Reference Projects

Cloned in parent directory for reference:

- `../magit/` - Popup system architecture, comprehensive features
- `../evil-collection/` - Canonical keybindings reference
- `../vim-fugitive/` - Performance patterns, vim-way design
- `../neogit/` - Popup system architecture, neovim implementation details, comprehensive features
- `../lazygit/` - AsyncHandler pattern, loader architecture

External dependency (integrate, don't reinvent):

- `diffview.nvim` - Full-buffer diff views, side-by-side diffs, 3-way merge conflict resolution

## Development Workflow

### Starting a New Feature

> **⚠️ CRITICAL: Always start from an up-to-date main branch!**
>
> Before starting ANY new work, you MUST fetch and update main first. Failing to do this causes merge conflicts and wastes time rebasing later.

```bash
git checkout main
git fetch origin
git reset --hard origin/main   # Ensure local main matches remote
git checkout -b feature/your-feature-name
```

This ensures:
- You're building on the latest code
- No conflicts from stale branches
- Clean git history

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
| **CI updates** | Any changes to workflow files needed for the feature |
| **Plan updates** | Update PLAN.md or goal-level docs with progress |
| **Implementation** | The feature/fix code itself |
| **Keybindings** | Any new mappings and their tests |

**Every commit must pass all checks:**
```bash
make format   # Format code
make lint     # Check formatting
make test     # Run all tests (unit + e2e)
```

Do not move to the next logical step until the current commit is complete and green.

### PR-Based Workflow

Once you have a commit or sequence of commits for a higher-level goal, follow this workflow:

#### 1. Local Review
```
- Use a sub-agent to review all changes locally (review-local skill)
- Address any feedback from the local review
- Ensure all commits are clean and well-structured
```

#### 2. Submit PR
```
- Push the branch and create a PR
- Wait for CI workflows to complete
- All checks must pass before proceeding
```

#### 3. PR Review
```
- Use a sub-agent to review the PR
- Address any feedback from the review
- Push fixes and ensure CI remains green
```

#### 4. Human Approval
```
- Once everything is green, notify a human
- Request manual testing and final review
- Only merge after human approval
```

**Never merge a PR without human sign-off.**

## Code Style

- Format with stylua (`make format`)
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
2. Run the specific failing test in isolation
3. Add print statements if needed (remove before committing)
4. Check if it's a timing issue (async tests may need `vim.wait`)
5. Never mark a task complete with failing tests
