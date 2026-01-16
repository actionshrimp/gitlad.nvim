# gitlad.nvim

A fast, well-tested git interface for Neovim. Inspired by magit, fugitive, and lazygit.

> **Status:** Early development (Phase 1 complete). Basic status view with staging/unstaging works. See [PLAN.md](PLAN.md) for roadmap.

## Goals

- **Fast** - Timestamp-based cache invalidation, async operations, scoped refreshes
- **Well-tested** - Comprehensive automated tests, not "works on my machine"
- **Magit UX** - Transient-style popup menus, familiar keybindings

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
| `s` | Stage file |
| `u` | Unstage file |
| `g` | Refresh |
| `q` | Close |

## Development

```bash
make dev      # Run Neovim with plugin loaded
make test     # Run tests
make lint     # Check formatting
```

## License

MIT
