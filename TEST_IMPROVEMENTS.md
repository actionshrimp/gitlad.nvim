# E2E Test Performance Improvements

This document tracks ideas for improving E2E test performance.

## Completed Optimizations

### Condition-Based Waits (Implemented)

Replaced fixed-duration waits with condition-based waits in the slowest test files:

| Test File | Before | After | Reduction |
|-----------|--------|-------|-----------|
| test_refs | 36.2s | 7.2s | 80% |
| test_log | 28.5s | 7.5s | 74% |
| test_merge_conflicts | 24.6s | 13.9s | 43% |
| test_submodule | 23.4s | 14.4s | 38% |
| test_merge_ui | 20.1s | 8.3s | 59% |

Smart wait helpers added to `tests/helpers.lua`:
- `wait_for_status(child)` - waits for status buffer to load with content
- `wait_for_popup(child)` - waits for popup window to open
- `wait_for_popup_closed(child)` - waits for popup to close
- `wait_for_buffer(child, pattern)` - waits for buffer name match
- `wait_for_buffer_content(child, text)` - waits for specific content
- `wait_for_var(child, var)` - waits for global variable
- `wait_short(child, ms)` - short fixed wait for UI updates

---

## Future Optimization Ideas

### 1. Apply Condition-Based Waits to Remaining Slow Tests

The following tests still have potential for optimization using the same pattern:

| Test | Current Time | Estimated Potential |
|------|--------------|---------------------|
| test_stash | 17.5s | High |
| test_status_hunk | 16.0s | High |
| test_cherrypick | 14.5s | Medium |
| test_status_staging | 13.9s | Medium |
| test_commit_basic | 13.4s | Medium |

**How to identify fixed waits:**
```bash
grep -n 'vim\.wait([0-9]*' tests/e2e/test_stash.lua
```

### 2. Split Large Test Files

Files with 20+ tests could be split to improve parallelism:

| File | Tests | Suggested Split |
|------|-------|-----------------|
| test_status_hunk (24 tests) | 24 | `test_status_hunk_expand`, `test_status_hunk_staging`, `test_status_hunk_discard` |
| test_status_staging (22 tests) | 22 | `test_status_staging_file`, `test_status_staging_section` |
| test_stash (20 tests) | 20 | `test_stash_push`, `test_stash_pop`, `test_stash_apply` |

The parallel runner is bottlenecked by the slowest single file. Splitting large files allows better distribution across workers.

### 3. Run Slowest Files First

Modify `scripts/run-tests-parallel.sh` to prioritize slow tests:

```bash
# Instead of alphabetical order:
E2E_FILES=(tests/e2e/*.lua)

# Use priority-ordered list (slowest first):
E2E_FILES=(
  tests/e2e/test_stash.lua
  tests/e2e/test_status_hunk.lua
  tests/e2e/test_cherrypick.lua
  tests/e2e/test_submodule.lua
  # ... rest alphabetically
)
```

This ensures the longest tests start immediately rather than being queued behind faster ones.

### 4. Optimize Git Repository Setup

Many tests create fresh git repositories with the same boilerplate:
```lua
vim.fn.mkdir(repo, "p")
vim.fn.system("git -C " .. repo .. " init")
vim.fn.system("git -C " .. repo .. " config user.email 'test@test.com'")
vim.fn.system("git -C " .. repo .. " config user.name 'Test User'")
```

**Ideas:**
- Pre-create a template repo and copy it (faster than `git init` each time)
- Use `git init --template` with a pre-configured template directory
- Cache the initialized repo state and use `cp -r` for each test

### 5. Reduce Child Process Restarts

Currently, each test restarts the Neovim child process. For tests that don't need complete isolation, consider:
- Resetting state without full restart
- Grouping related tests that can share a child process
- Using `child.lua([[require("gitlad.state").reset()]])` instead of `child.restart()`

**Caveat:** This may introduce test interdependence. Only use for truly independent tests.

### 6. Parallel Test Groups

For tests within a single file that are independent, mini.test supports parallel execution. This could be enabled for specific test groups that don't share state.

### 7. Profile Actual Test Time vs Wait Time

Add instrumentation to measure:
- Time spent in fixed waits
- Time spent in git operations
- Time spent in Neovim operations

This would help identify the biggest remaining bottlenecks.

---

## Measurement Commands

```bash
# Run all e2e tests with timing
make test-e2e

# Run a single test file
make test-file FILE=tests/e2e/test_stash.lua

# Count fixed waits in a file
grep -c 'vim\.wait([0-9]*' tests/e2e/test_stash.lua

# Find all fixed waits with durations
grep -o 'vim\.wait([0-9]*' tests/e2e/*.lua | sort | uniq -c | sort -rn
```
