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

Now:
- [ ] diffing from refs view doesnt work properly. a few notes:
  - [x] it should be possible to use the diff popup on individual cherries, to see the explicit diff in that commit
  - it should be possible to use the ref name as context for the diff popup to help pre-fill some completion. one thing i particularly want is some command from the diff popup that, if the pointer is on a ref name, just asks for what to compare it against with the `...` git range, to make it easy to see the changes on that branch vs e.g. the `main` or `develop` branch.

Upcoming:
- [ ] Weird highlighting issue where line highlighting somehow gets enabled and line numbers disappear
- [ ] would be nice to have an easy 'diff this branch with x' ... that auto completed based on context under point
