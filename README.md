# gitlad.nvim

A fast, well-tested git interface for Neovim. Inspired by magit, fugitive, and lazygit.

> **Status:** Active development (Phase 2 complete). Status view with staging, inline diffs, hunk staging, and commit popup. See [PLAN.md](PLAN.md) for roadmap.

## Goals

- **Fast** - Optimistic state updates with manual refresh, instant UI response even in large repos
- **Well-tested** - Comprehensive automated tests, not "works on my machine"
- **Magit UX** - Transient-style popup menus, familiar keybindings

## Performance Philosophy

In large monorepos (1M+ files), `git status` can take seconds. gitlad.nvim avoids this bottleneck through **optimistic state updates**:

1. **No automatic git syncing** - The UI never automatically runs `git status` after operations
2. **Optimistic Lua-side updates** - When you stage/unstage a file:
   - Run the git command (e.g., `git add`)
   - Check the exit code
   - If success: update the in-memory state directly (move file between sections)
   - If failure: show error, state unchanged
3. **Manual refresh** - Press `g` to sync with git when needed

This means the UI may occasionally be out of sync with git (if you run git commands outside the plugin), but `g` is always available to resync.

## Installation

Using lazy.nvim:
```lua
{
  "actionshrimp/gitlad.nvim",
  config = function()
    require("gitlad").setup()
  end,
}
```

## Usage

```vim
:Gitlad          " Open status view
```

### Status View Keybindings

| Key | Action |
|-----|--------|
| `s` | Stage file/hunk at cursor |
| `u` | Unstage file/hunk at cursor |
| `S` | Stage all |
| `U` | Unstage all |
| `x` | Discard changes at cursor |
| `n`/`p` | Next/previous file |
| `M-n`/`M-p` | Next/previous section |
| `TAB` | Toggle inline diff |
| `RET` | Visit file |
| `c` | Commit popup |
| `g` | Refresh |
| `$` | Git command history |
| `q` | Close |
| `?` | Help |

## Development

```bash
make dev      # Run Neovim with plugin loaded
make test     # Run tests
make lint     # Check formatting
```

### GitHub Account Setup (Optional)

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

## License

MIT
