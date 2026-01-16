# gitlad.nvim Development Guide

## Project Vision

A fast, well-tested git interface for Neovim inspired by magit, fugitive, and lazygit. Key differentiators:

- **Performance-first**: Timestamp-based cache invalidation (like fugitive), not full refreshes
- **Properly tested**: Comprehensive automated tests are mandatory, not optional
- **Magit UX**: Transient-style popup menus and magit keybindings
- **Async-aware**: AsyncHandler pattern prevents stale data, scoped refreshes

## Golden Rule: Automated Testing

**Every change MUST include automated tests. No exceptions.**

### Non-Negotiable Requirements

1. **NEVER ask the user to manually test changes** - This is disrespectful of their time
2. **NEVER consider work complete until `make test` passes** - Run tests yourself
3. **NEVER submit code without corresponding tests** - Untested code is broken code
4. **ALWAYS run `make test` before declaring any task done** - Verify it yourself
5. **ALWAYS fix failing tests before moving on** - Don't leave broken tests behind

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

### Test Quality Standards

- Tests must be deterministic (no flaky tests)
- Tests must be isolated (no shared state between tests)
- Tests must be fast (unit tests < 1s each)
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
```

### Local Development

```bash
# Run Neovim with the plugin loaded (from project directory)
make dev

# Then use :Gitlad to open status view
```

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
├── init.lua          # Entry point, setup()
├── config.lua        # User configuration
├── commands.lua      # :Gitlad command dispatcher
├── git/
│   ├── init.lua      # High-level git operations
│   ├── cli.lua       # Async job execution (vim.fn.jobstart)
│   └── parse.lua     # Git output parsers (porcelain v2)
├── state/
│   ├── init.lua      # RepoState coordinator
│   ├── cache.lua     # Timestamp-based cache invalidation
│   └── async.lua     # AsyncHandler, debounce, throttle
└── ui/
    ├── popup/        # Transient-style popup system (TODO)
    └── views/
        └── status.lua
```

### Key Patterns

1. **Timestamp-based cache** (`state/cache.lua`)
   - Watches `.git/HEAD`, `.git/index`, etc.
   - Only invalidates when files actually change
   - Avoids polling, avoids full refreshes

2. **AsyncHandler** (`state/async.lua`)
   - Tracks request IDs
   - Only applies the latest result
   - Prevents stale async results from overwriting fresh data

3. **RepoState** (`state/init.lua`)
   - One instance per repository
   - Emits events ("status", "branches", etc.)
   - Views subscribe to events for updates

4. **Porcelain v2 parsing** (`git/parse.lua`)
   - Uses `git status --porcelain=v2` for stable output
   - Machine-readable, won't break with git updates

## Keybindings (Magit-Style)

### Navigation
| Key | Action |
|-----|--------|
| `n` / `p` | Next/previous item |
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
| `P` | Push |
| `l` | Log |
| `d` | Diff |
| `m` | Merge |
| `r` | Rebase |
| `z` | Stash |
| `A` | Cherry-pick |
| `V` | Revert |
| `t` | Tag |
| `!` | Run git command |

### Other
| Key | Action |
|-----|--------|
| `g` | Refresh |
| `q` | Close buffer |
| `$` | Show git process output |
| `?` | Show help / all keybindings |

## Development Plan

See **PLAN.md** for the detailed development roadmap with specific tasks, files to create/modify, and implementation notes.

### Current Status: Phase 1 Complete

**What's built:**
- Async git CLI wrapper with porcelain v2 parsing
- Timestamp-based cache invalidation
- AsyncHandler pattern for request ordering
- Status buffer with staging/unstaging
- 37 tests passing, CI configured

**Next up (Phase 2):**
- File watcher
- Full magit keybindings
- Inline diff expansion
- Popup system
- Commit popup

## Reference Projects

Cloned in parent directory for reference:

- `../neogit/` - Popup system architecture, comprehensive features
- `../vim-fugitive/` - Performance patterns, vim-way design
- `../lazygit/` - AsyncHandler pattern, loader architecture

## Development Workflow

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
