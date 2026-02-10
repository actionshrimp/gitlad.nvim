# gitlad.nvim

A magit-inspired git interface for Neovim, built for large monorepos.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "actionshrimp/gitlad.nvim",
  config = function()
    require("gitlad").setup()
  end,
}
```

Optionally add [diffview.nvim](https://github.com/sindrets/diffview.nvim) for full-buffer diffs and 3-way staging:

```lua
{
  "actionshrimp/gitlad.nvim",
  dependencies = {
    {
      "actionshrimp/diffview.nvim",
      branch = "3-way-staging",
    },
  },
  config = function()
    require("gitlad").setup()
  end,
}
```

Then open any git repo and run `:Gitlad`.

## Features

- **Status view** with unstaged, staged, untracked, and conflicted sections
- **Inline diff expansion** - TAB on a file shows the diff inline
- **Hunk-level staging** - Stage/unstage individual hunks or visual selections
- **Transient-style popups** for commit, push, pull, fetch, branch, log, diff, stash, rebase, merge, cherry-pick, revert, reset, and submodule
- **Interactive rebase editor** with pick/reword/edit/squash/fixup/drop
- **Upstream tracking** - Unpushed/unpulled commits, ahead/behind counts
- **Git command history** - `$` shows every git command run with output and exit codes
- **diffview.nvim integration** - Full-buffer diffs and 3-way merge conflict resolution

## Performance

In large monorepos (1M+ files), `git status` can take seconds. gitlad avoids this bottleneck with **optimistic state updates**:

1. **No automatic git syncing** - The UI never runs `git status` after operations
2. **Instant updates** - Stage a file → run `git add` → check exit code → update UI state directly in Lua
3. **Manual refresh** - Press `gr` when you want to resync with git

A file watcher detects external changes (terminal commands, other git clients) and shows a stale indicator. See [configuration](#configuration) for auto-refresh options.

## Keybindings

Follows [evil-collection-magit](https://github.com/emacs-evil/evil-collection/blob/master/modes/magit/evil-collection-magit.el) conventions.

**Staging**
| Key | Action |
|-----|--------|
| `s` | Stage file/hunk at cursor |
| `u` | Unstage file/hunk at cursor |
| `S` / `U` | Stage / unstage all |
| `x` | Discard changes at cursor |

**Popups**
| Key | Popup |
|-----|-------|
| `c` | Commit |
| `b` | Branch |
| `f` | Fetch |
| `F` | Pull |
| `p` | Push |
| `l` | Log |
| `d` | Diff |
| `z` | Stash |
| `r` | Rebase |
| `m` | Merge |
| `A` | Cherry-pick |
| `_` | Revert |
| `X` | Reset |
| `'` | Submodule |

**Navigation**
| Key | Action |
|-----|--------|
| `gj` / `gk` | Next/previous file or commit |
| `M-n` / `M-p` | Next/previous section |
| `TAB` | Toggle inline diff / expand commit |
| `RET` | Visit file at cursor |
| `gr` | Refresh |
| `$` | Git command history |
| `?` | Help |
| `q` | Close |

## Configuration

The defaults work out of the box. Pass only what you want to change.

For all available options and their defaults, see [`lua/gitlad/config.lua`](lua/gitlad/config.lua).

```lua
require("gitlad").setup({
  -- Example: enable auto-refresh when external tools change git state
  watcher = {
    auto_refresh = true,
    auto_refresh_debounce_ms = 1000,
  },

  -- Example: customise which sections appear in the status buffer
  status = {
    sections = {
      "untracked",
      "unstaged",
      "staged",
      "conflicted",
      "stashes",
      "submodules",
      { "worktrees", min_count = 2 },
      "unpushed",
      "unpulled",
      { "recent", count = 10 },
    },
  },
})
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, running tests, and code style.

## License

MIT
