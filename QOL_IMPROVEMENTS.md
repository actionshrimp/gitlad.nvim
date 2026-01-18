# QoL Improvements Tracker

This document tracks Quality of Life improvements being worked on.

## In Progress

### 1. Reorder status view sections to match magit
**Status:** Complete
- Moved untracked → unstaged → staged → conflicted to the top (after header)
- Commit sections (unpulled/unpushed/recent) now appear below file sections
- Matches magit's typical section ordering

### 2. Support log keybinds on status buffer commits
**Status:** Complete
- Added `d` keybind to show commit diff (via diffview.nvim or fallback to terminal)
- Added `y` keybind to yank commit hash to clipboard
- `<CR>` now toggles commit expansion when on a commit line (same as `<Tab>`)
- Works on commits in unpulled/unpushed/recent sections

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
