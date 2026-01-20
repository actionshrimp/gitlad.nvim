Done:
- [x] Show refs on the log views in the status buffer
- [x] Add `origin/` and local ref highlighting to those refs in those views to see if things are in sync
- [x] Add that same highlighting to the refs at the top of the status buffer (e.g. Push: branch)
- [x] Move idle/refreshing display to very top of status buffer with faint background colour
- [x] Show loading state with full-buffer faint background on initial open, transitioning to just the first line
- [x] Fix line numbers being disabled globally instead of just locally for gitlad buffers

Now:

Upcoming:
- [ ] pressing 'p' on a stash directly tries to pop it, should open the popup menu instead
- [ ] is git hook output definitely streaming?
- [ ] Weird highlighting issue where line highlighting somehow gets enabled and line numbers disappear
- [ ] diffing from refs view doesnt work
- [ ] refs view cherry indent is still annoying
- [ ] would be nice to have an easy 'diff this branch with x' ... that auto completed based on context under point
