- [x] do we have tests that check the actual git config values are being updated in the file correctly? if not can we add some
- [x] when the upstream is changed, can we force a refresh of the git state, as the status window is highly dependent on that config
- [x] better 'q' behaviour and buffer tracking
- [x] when reopening status buffer, position cursor at first item (not header)
- [x] discard hunks with 'x' - we can discard whole files but this should also work at hunk level
- [x] "diffs" / pressing RET on stashes doesnt seem to work. Does diffview support this?
- [x] update casing of 'pushremote' in places where it's all lower case to 'pushRemote'
- [x] is there some way we can make partial staging of untracked files work? perhaps with `git add -N` followed by a similar approach to how we do staging of visually selected lines for unstaged changes?
- [x] add 'o' to push popup (push other branch)
- [x] 'no upstream configured for main, cannot spin off'
- [x] configurable status buffer sections: allow users to configure the order and presence of different sections (staged, unstaged, untracked, worktrees, stashes, etc.) - some users may not want certain sections shown or may prefer them at different positions. Could also include section-specific options like 'number of recent commits' to display.
- [ ] add a 'view is stale' indicator
- [ ] for a moved file, only show the actual file changes in the diff
- [ ] Weird highlighting issue where line highlighting somehow gets enabled and line numbers disappear - i think this is actually sidekick.nvim
- [ ] improve look and feel of '$' / command history (from screenshot)
- [ ] hook output window should only appear if hooks are actually configured. Before implementing, consider a holistic approach: detect configured hooks and show progress/output for all git operations that may trigger them (commit, push, etc.). This may warrant a dedicated phase in PLAN.md.

some other text
