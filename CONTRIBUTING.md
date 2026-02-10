# Contributing to gitlad.nvim

## Getting Started

```bash
# Clone and install dependencies
git clone https://github.com/actionshrimp/gitlad.nvim
cd gitlad.nvim
make deps
```

## Development

```bash
make dev       # Run Neovim with the plugin loaded
make dev-repo  # Create a test repo and open with plugin
make test      # Run all tests (unit + e2e)
make test-unit # Run only unit tests
make test-e2e  # Run only e2e tests
make test-file FILE=tests/e2e/test_rebase.lua  # Run a single test file
make format    # Format code with stylua
make lint      # Check formatting
```

## Code Style

- Formatted with [stylua](https://github.com/JohnnyMorganz/StyLua) (2-space indent, 100 char width)
- LuaCATS annotations for types (`---@param`, `---@return`, etc.)
- Run `make format` before committing

## Tests

Every change should include tests. The test suite uses [mini.test](https://github.com/echasnovski/mini.test).

- `tests/unit/` - Pure Lua unit tests (fast, isolated)
- `tests/e2e/` - Full Neovim integration tests (slower, comprehensive)
- `tests/helpers.lua` - Shared test utilities for creating isolated git repos

When iterating on a feature, run just the relevant test file for faster feedback, then `make test` before committing.

## GitHub Account Setup (Optional)

If you have multiple GitHub accounts and need to use a specific one for this project:

```bash
# 1. Add your account to gh CLI if not already
gh auth login

# 2. Run setup (prompts for account name, creates local .envrc)
make setup-gh

# 3. Allow direnv
direnv allow
```

This sets `GH_TOKEN` automatically when you're in this directory.

## CI

All PRs must pass:
1. Tests on Neovim stable
2. Tests on Neovim nightly
3. stylua lint check
