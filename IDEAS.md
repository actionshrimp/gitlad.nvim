# Future Ideas

Ideas for future development that aren't ready for immediate planning.

---

## Post-commit hook output popup

Show the output of git commit hooks (pre-commit, commit-msg, post-commit) in a popup after committing.

**Use case:** When commit hooks run linters, formatters, or other tools, users often want to see what happened without digging through terminal output.

**Possible approach:**
- Capture stdout/stderr from the commit command
- If hooks produced output, show it in a dismissible popup
- Could distinguish between hook types (pre-commit vs post-commit)
- Consider making this opt-in via config

---

## Refs View (like magit-refs)

A dedicated view showing all refs (branches, tags, remotes) in a unified display.

**Inspiration:** magit's `y` (refs) view

**What it would show:**
- Local branches with their tracking info
- Remote branches
- Tags
- Cherries (commits that exist in one branch but not another)

**Use cases:**
- Quick overview of all branches and their status
- Cherry-picking commits between branches
- Comparing branches visually
- Managing upstream/push remotes

**Implementation notes:**
- Would reuse the log component for showing commit lists (cherries)
- Consistent look/feel with status buffer
- Cursor context for acting on specific refs/commits

---
