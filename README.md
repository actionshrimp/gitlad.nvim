# gitlad.nvim

A fast, well-tested git interface for Neovim. Inspired by magit, fugitive, and lazygit.

> **Status:** Active development (Phase 3 complete, Phase 4 partial). Full staging workflow with inline diffs, hunk staging, and comprehensive popups for commit, push, pull, fetch, branch, log, diff, stash, rebase, cherry-pick, revert, and reset. See [PLAN.md](PLAN.md) for roadmap.

## Goals

- **Fast** - Optimistic state updates with manual refresh, instant UI response even in large repos
- **Well-tested** - Comprehensive automated tests, not "works on my machine"
- **Magit UX** - Transient-style popup menus, familiar keybindings

## Features

- **Status view** with unstaged, staged, and untracked sections
- **Inline diff expansion** - TAB on a file shows the diff inline
- **Hunk-level staging** - Stage/unstage individual hunks or visual selections
- **Git command history** - `$` shows all git commands run with their output
- **Transient-style popups** for all git operations
- **Upstream tracking** - Shows unpushed/unpulled commits, ahead/behind counts
- **diffview.nvim integration** - Full-buffer diffs delegate to diffview

## Performance Philosophy

In large monorepos (1M+ files), `git status` can take seconds. gitlad.nvim avoids this bottleneck through **optimistic state updates**:

1. **No automatic git syncing** - The UI never automatically runs `git status` after operations
2. **Optimistic Lua-side updates** - When you stage/unstage a file:
   - Run the git command (e.g., `git add`)
   - Check the exit code
   - If success: update the in-memory state directly (move file between sections)
   - If failure: show error, state unchanged
3. **Manual refresh** - Press `gr` to sync with git when needed

This means the UI may occasionally be out of sync with git (if you run git commands outside the plugin), but `gr` is always available to resync.

## Installation

Using lazy.nvim:
```lua
{
  "actionshrimp/gitlad.nvim",
  dependencies = {
    -- Optional: for full-buffer diffs and 3-way staging view
    -- Use the 3-way-staging branch for HEAD|INDEX|WORKING view support
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

> **Note:** The 3-way staging view (`d` then `3` on staged/unstaged files) requires the `3-way-staging` branch from the [actionshrimp/diffview.nvim](https://github.com/actionshrimp/diffview.nvim/tree/3-way-staging) fork. This feature shows HEAD | INDEX | WORKING side-by-side with editable index buffers.

## Configuration

Below are the default settings. You only need to pass options you want to change.

```lua
require("gitlad").setup({
  -- Refresh status buffer when Neovim gains focus
  refresh_on_focus = true,

  -- Watch .git directory for changes and auto-refresh
  watch_gitdir = true,

  -- Signs shown in the status buffer
  signs = {
    staged = "●",
    unstaged = "○",
    untracked = "?",
    conflict = "!",
  },

  -- Commit editor behavior
  commit_editor = {
    split = "above", -- "above" = split above status, "replace" = replace current buffer
  },

  -- Worktree creation behavior
  worktree = {
    directory_strategy = "sibling", -- "sibling" = suggest sibling directory, "prompt" = always prompt
  },

  -- Status buffer configuration
  status = {
    -- Section order and visibility. Omit a section to hide it.
    -- Use string for defaults, or table for section-specific options.
    sections = {
      "untracked",
      "unstaged",
      "staged",
      "conflicted",
      "stashes",
      -- "submodules",  -- uncomment to show submodules section
      { "worktrees", min_count = 2 },  -- only show if >= min_count worktrees
      "unpushed",
      "unpulled",
      { "recent", count = 10 },  -- limit recent commits shown
    },
  },
})
```

### Available Sections

| Section | Description | Options |
|---------|-------------|---------|
| `untracked` | Untracked files | - |
| `unstaged` | Unstaged changes | - |
| `staged` | Staged changes | - |
| `conflicted` | Merge conflicts | - |
| `stashes` | Stash list | - |
| `submodules` | Submodule status | - |
| `worktrees` | Worktree list | `min_count` (default: 2) - minimum worktrees to show section |
| `unpushed` | Commits not pushed | - |
| `unpulled` | Commits not pulled | - |
| `recent` | Recent commits | `count` (default: 10) - max commits to show |

## Usage

```vim
:Gitlad          " Open status view
```

### Keybindings

**Navigation**
| Key | Action |
|-----|--------|
| `j`/`k` | Standard line movement |
| `gj`/`gk` | Next/previous file or commit |
| `M-n`/`M-p` | Next/previous section |
| `TAB` | Toggle inline diff / expand commit |
| `RET` | Visit file at cursor |

**Staging**
| Key | Action |
|-----|--------|
| `s` | Stage file/hunk at cursor |
| `u` | Unstage file/hunk at cursor |
| `S` | Stage all |
| `U` | Unstage all |
| `x` | Discard changes at cursor |

**Popup Triggers**
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

**Other**
| Key | Action |
|-----|--------|
| `gr` | Refresh status |
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
