# QoL Improvements Tracker

This document tracks Quality of Life improvements being worked on.

## In Progress

### 1. Reorder status view sections to match magit
**Status:** Complete
- Moved untracked → unstaged → staged → conflicted to the top (after header)
- Commit sections (unpulled/unpushed/recent) now appear below file sections
- Matches magit's typical section ordering

### 2. Support log keybinds on status buffer commits
**Status:** Pending
- Commits shown in status buffer (recent commits, unpushed, unpulled) should support the same keybinds as the full log view
- e.g., viewing commit details, cherry-pick, revert, etc.

### 3. Make section headers bold and standout
**Status:** Pending
- Section headers currently show as plain text
- Make them bold with a more visible color
- Check highlight group definitions and ensure they're being applied

## Completed

(None yet)

---

## Notes

New improvements may be added during development. Each improvement should be tackled as a separate commit.
