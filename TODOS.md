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

Now:

Upcoming:
- [ ] Weird highlighting issue where line highlighting somehow gets enabled and line numbers disappear
- [ ] Reflog HEAD on log view
- [ ] The Diffview conflict resolution screen definitely has 3 splits! can we use that for a better view on original/unstaged/index?
- [ ] as we get the notification for lint failures, i think we can just make the commit hook popup dispapear after a slightly longer delay in the error case. users can look in their notification history to see the failure
