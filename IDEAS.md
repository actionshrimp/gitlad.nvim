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
