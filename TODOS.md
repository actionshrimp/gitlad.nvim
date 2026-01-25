Done:
- [x] Show refs on the log views in the status buffer
- [x] Add `origin/` and local ref highlighting to those refs in those views to see if things are in sync
- [x] Add that same highlighting to the refs at the top of the status buffer (e.g. Push: branch)
- [x] Move idle/refreshing display to very top of status buffer with faint background colour
- [x] Show loading state with full-buffer faint background on initial open, transitioning to just the first line
- [x] Fix line numbers being disabled globally instead of just locally for gitlad buffers
- [x] if you've explicitly run the :Gitlad command, we should trigger a refresh, even if we already have some state present
- [x] pressing 'p' on a stash opens the stash popup menu instead of directly popping
- [x] on the refs view, the individual commits under a particular ref (for cherries etc) are not indented
- [x] diffing from refs view: diff popup on cherries shows commit diff, `d r` on refs uses multi-step workflow (pick base → pick range type `..` or `...`)
- [x] Currently when using diffview to edit what is staged vs unstaged, we have a regular diffview screen with 2 splits and at the time I asked about if it was possible to do a 3-split view so we could see origina/index/unstaged - it seemed like it wasn't possible to get diffview to do that. However, with the recent work on merge conflicts, it transpires that the Diffview conflict resolution screen definitely has 3 splits! can we use that for a better view on the current status by treating it as a 'conflict' of sorts? ideally it would be original on left, index in the middle, and unstaged on the right
- [x] commit hook output popup improvements/fixes
- [x] When unstaging files, the cursor doesnt move to the next staged file to make it easy to keep pressing 'u' repeatedly
- [x] <cr> on a commit is a shortcut for `d d`
- [x] <cr> on a hunk in staging view, jump to same line in file
- [x] reorder commit sections: user's commits first, then unpulled, with upstream last
- [x] instant fixup
- [x] help popup is wrong (e.g. 'refresh' is now `gr` and not `g`)
- [x] add a shift+tab bind to toggle all sections. also, a magit style meta+1/2/3/4 (I think it's these keys at least) to collapse/expand certain levels on the status view
- [x] hunk level toggle/expansion
- [ ] some highlighting in the various popup menus are wrong - the key isnt always highlighted purple

Now:
- [x] the help popup is a bit long now! it would be good if it could be rendered as two columns with some logical grouping of different sections
- [ ] for some reason text in brackets in commit lists is highlighted green

Upcoming:
- [ ] Reflog HEAD on log view
- [ ] add a 'view is stale' indicator
- [ ] 'when i have scrolled down in the status buffer, then close it with `q`, when i reopen it again it would be nice to scroll to the top
- [ ] for a moved file, only show the actual file changes in the diff
- [ ] support 'remotes' popup
- [ ] Weird highlighting issue where line highlighting somehow gets enabled and line numbers disappear - i think this is actually sidekick.nvim
- [ ] pressing 'p p' for a new branch errors saying there's no remote set, it would be nice if it could default to creating a branch with the same name on the 'default remote' (usually origin) if git has such a concept and there's one configured? it's a bit annoying to have to manually set the upstream to origin first.
