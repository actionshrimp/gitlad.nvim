# gitlad.nvim

A performance-focused, magit-inspired git interface for Neovim.

<p align="center">
  <a href="https://actionshrimp.com/gitlad.nvim/#demo">
    <img src="https://github.com/actionshrimp/gitlad.nvim/raw/main/docs/demo-preview.gif" alt="gitlad.nvim demo">
  </a>
  <br>
  <em><a href="https://actionshrimp.com/gitlad.nvim/#demo">Interactive demo</a></em>
</p>

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "actionshrimp/gitlad.nvim",
  dependencies = {
    {
      -- Fork with 3-way staging support (magit/ediff style).
      -- The original sindrets/diffview.nvim also works if you prefer.
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

gitlad uses **optimistic state updates** to keep the UI fast regardless of repo size:

1. **Instant updates** - Stage a file → run `git add` → check exit code → update UI state directly in Lua (no `git status` round-trip)
2. **Manual refresh** - Press `gr` when you want to resync with git

### File watcher (optional)

An optional file watcher detects external changes (terminal commands, other editors, `git push`) and either shows a **stale indicator** or **auto-refreshes** the status buffer. Both the watcher and auto-refresh are configurable — see [configuration](#configuration).

The watcher uses libuv's `fs_event` under the hood. On macOS and Windows this provides recursive directory watching with no polling overhead. On Linux, `fs_event` is non-recursive, so the watcher covers `.git/` subdirectories and the repo root, with Neovim autocmds (`BufWritePost`, `FocusGained`) as a fallback for changes in nested working tree files.

## Keybindings

Follows [evil-collection-magit](https://github.com/emacs-evil/evil-collection/blob/master/modes/magit/evil-collection-magit.el) conventions. If you're familiar with magit, you'll feel right at home.

All keybindings are discoverable from within the plugin — press `?` in any gitlad buffer to open the help popup showing every available key.

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
      "rebase_sequence",
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
