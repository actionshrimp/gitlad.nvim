# gitlad.nvim Development Plan

## Context

gitlad.nvim has a mature core git workflow (staging, commits, branches, rebasing, etc.) with 970+ tests. The next major evolution is **GitHub forge integration** and a **native diff viewer** that replaces our diffview.nvim dependency, creating a seamless experience where PR review is just "diff viewing with annotations."

See TODOS.md for unfinished items from earlier phases (tag popup, run command popup, etc.).

## Architecture Decisions

- **`N` keybinding** for forge popup (evil-collection-magit convention)
- **GitHub GraphQL/REST API** called directly from Lua via `curl` + `vim.fn.jobstart` (async, same pattern as `git/cli.lua`)
- **`gh auth token`** to obtain auth token — no custom OAuth flow, user just needs `gh` installed and authenticated
- **`gh` CLI** used only for auth management and a few convenience operations (PR checkout, create, merge)
- **GitHub-first** but provider-agnostic interface for future GitLab/Gitea support
- **Native diff viewer** built into gitlad, replacing diffview.nvim for all diff viewing
- **Dedicated buffer** for PR list (not inline in status buffer, though status gets a summary line)

### Why Direct API Instead of `gh` CLI for Everything?

- **GraphQL** lets us fetch exactly the data we need in a single request (e.g., PR + comments + reviews + files in one query)
- **Fewer subprocess spawns** — one `curl` call instead of multiple `gh` invocations
- **Full control** over pagination, batching, and error handling
- **Simpler mocking** in tests — mock HTTP responses instead of a shell script
- `gh` CLI is still used for: `gh auth token` (auth), `gh pr checkout` (convenience), `gh pr create` (interactive), `gh pr merge` (convenience)

## Directory Structure

```
lua/gitlad/
├── forge/
│   ├── init.lua              # Provider detection from remote URL, auth check
│   ├── http.lua              # Async HTTP client (curl + jobstart)
│   ├── types.lua             # Shared forge types (PR, Review, Comment)
│   └── github/
│       ├── init.lua          # GitHub provider implementation
│       ├── graphql.lua       # GraphQL queries and response parsing
│       ├── pr.lua            # PR operations (list, view, create, merge)
│       └── review.lua        # Review/comment operations
├── popups/
│   └── forge.lua             # N keybinding forge popup
├── ui/
│   ├── views/
│   │   ├── pr_list.lua       # PR list buffer
│   │   ├── pr_detail.lua     # PR detail/discussion buffer
│   │   └── diff/
│   │       ├── init.lua      # DiffView coordinator (layout, lifecycle)
│   │       ├── panel.lua     # File panel sidebar
│   │       ├── buffer.lua    # Diff buffer pair management
│   │       ├── hunk.lua      # Hunk parsing, side-by-side alignment
│   │       └── review.lua    # Review comment overlay
│   └── components/
│       ├── pr_list.lua       # PR list rendering component
│       └── comment.lua       # Comment/thread rendering component
```

## Dependency Graph

```
Milestone 1 (Forge Foundation)     Milestone 3 (CI Checks)    Milestone 4 (Native Diff Viewer)
         │                                    │                          │
         ▼                                    │                          │
Milestone 2 (PR Management) ─────────────────►│                          │
                                              │                          │
                                              └──────────┬───────────────┘
                                                         ▼
                                              Milestone 5 (PR Review)
                                                         │
                                                         ▼
                                              Milestone 6 (Polish & Advanced)
```

Milestones 1-2 and Milestone 4 are **independent** and can proceed in parallel.
Milestone 3 (CI Checks) depends on Milestone 2 (PR views).

---

## Milestone 1: Forge Foundation

**Goal**: HTTP client, auth detection, GitHub provider, forge popup, basic PR listing.

### 1.1 Async HTTP Client

**Create**: `lua/gitlad/forge/http.lua`, `tests/unit/test_forge_http.lua`

Async HTTP via `curl` + `vim.fn.jobstart` (mirrors `git/cli.lua` pattern):

```lua
---@class HttpRequest
---@field url string
---@field method "GET"|"POST"|"PATCH"|"DELETE"
---@field headers table<string, string>
---@field body string|nil                    -- JSON string for POST/PATCH
---@field timeout number|nil                 -- Default 15s

---@class HttpResponse
---@field status number
---@field headers table<string, string>
---@field body string
---@field json any|nil                       -- Parsed JSON

--- Make async HTTP request
---@param request HttpRequest
---@param callback fun(response: HttpResponse|nil, err: string|nil)
function M.request(request, callback)
```

curl command construction:
```
curl -s -w "\n%{http_code}" -X <method> -H "Authorization: bearer <token>" -H "Content-Type: application/json" -d '<body>' <url>
```

### 1.2 Provider Detection & Auth

**Create**: `lua/gitlad/forge/init.lua`, `tests/unit/test_forge_init.lua`

- Parse `git remote get-url origin` → detect provider from URL patterns
- Handle: HTTPS (`https://github.com/owner/repo.git`), SSH (`git@github.com:owner/repo.git`), SSH with path (`ssh://git@github.com/owner/repo`)
- Get auth token: shell out to `gh auth token` (fast, cached per session)
- If `gh` not installed or not authenticated: notify with instructions
- Return provider-agnostic interface:

```lua
---@class ForgeProvider
---@field name string           -- "github"
---@field owner string
---@field repo string
---@field api_url string        -- "https://api.github.com"
---@field token string          -- From gh auth token
---@field list_prs fun(opts, callback)
---@field get_pr fun(number, callback)
---@field pr_comments fun(number, callback)
```

### 1.3 Forge Types

**Create**: `lua/gitlad/forge/types.lua`

Core types with LuaCATS annotations: `ForgePullRequest`, `ForgeUser`, `ForgeComment`, `ForgeReview`, `ForgeReviewComment`, `ForgeFile`.

### 1.4 GitHub Provider & GraphQL

**Create**: `lua/gitlad/forge/github/init.lua`, `lua/gitlad/forge/github/graphql.lua`, `lua/gitlad/forge/github/pr.lua`
**Create**: `tests/unit/test_forge_github.lua`, `tests/unit/test_github_graphql.lua`

GraphQL queries for efficient data fetching:

```graphql
# PR list — single query for all data needed
query($owner: String!, $repo: String!, $states: [PullRequestState!]) {
  repository(owner: $owner, name: $repo) {
    pullRequests(first: 50, states: $states, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number, title, state, isDraft, additions, deletions, changedFiles
        author { login }
        headRefName, baseRefName
        reviewDecision
        labels(first: 10) { nodes { name } }
        createdAt, updatedAt, url
      }
    }
  }
}
```

`gh` CLI still used for convenience operations:
- `gh pr checkout <n>` (handles remote fetching, tracking branch setup)
- `gh pr create --title "..." --body "..." --base main` (interactive workflow)
- `gh pr merge <n> [--squash|--rebase|--merge]`

### 1.5 Forge Popup

**Create**: `lua/gitlad/popups/forge.lua`, `tests/unit/test_forge_popup.lua`, `tests/e2e/test_forge_popup.lua`
**Modify**: `lua/gitlad/ui/views/status_keymaps.lua` (add `N`), `lua/gitlad/popups/help.lua`

Initial popup:
```
Forge (GitHub: owner/repo)

Pull Requests
 l  List pull requests
 v  View current branch PR
 c  Checkout PR branch
```

### 1.6 PR List View

**Create**: `lua/gitlad/ui/views/pr_list.lua`, `lua/gitlad/ui/components/pr_list.lua`
**Create**: `tests/unit/test_pr_list_component.lua`, `tests/e2e/test_pr_list.lua`
**Modify**: `lua/gitlad/ui/hl.lua` (add forge highlight groups)

Follow `log.lua` singleton buffer pattern. Reusable `pr_list` component (like `log_list`).

Display: `#123 Fix auth bug  @author  +10 -3  APPROVED`

Keybindings: `gj`/`gk` navigate, `<CR>` view detail, `y` yank PR number, `gr` refresh, `q` close.

Filtering: "My PRs" / "Review Requested" / "All Open"

### E2E Testing Strategy

For HTTP-based tests, mock at the HTTP layer — intercept `curl` calls by prepending a mock script to PATH, or mock `vim.fn.jobstart` in unit tests. Canned JSON responses in `tests/fixtures/github/`.

---

## Milestone 2: PR Management

**Goal**: Full PR detail view, discussion thread, comment CRUD, PR actions.
**Depends on**: Milestone 1.

### 2.1 PR Detail View

**Create**: `lua/gitlad/ui/views/pr_detail.lua`, `lua/gitlad/ui/components/comment.lua`
**Create**: `tests/unit/test_comment_component.lua`, `tests/e2e/test_pr_detail.lua`

Layout:
```
#123 Fix authentication bug in login flow
Author: @dave  State: OPEN  Reviews: APPROVED
Base: main <- feature/fix-auth  +10 -3  2 files changed
Labels: bug, priority:high
---
This PR fixes the authentication bug that was causing...
---
Comments (3)

@reviewer  2 days ago
Looks good but I have a question about error handling.

  @dave  1 day ago  (reply)
  Good point, I've updated the error handling.
```

Keybindings: `gj`/`gk` between comments, `c` add comment, `e` edit own comment, `d` open diff, `o` open in browser, `gr` refresh, `q` close.

### 2.2 Comment CRUD

**Create**: `lua/gitlad/forge/github/review.lua`, `tests/unit/test_forge_review.lua`

- Add comment: GraphQL `addComment` mutation or REST `POST /repos/{owner}/{repo}/issues/{n}/comments`
- Edit comment: REST `PATCH /repos/{owner}/{repo}/issues/comments/{id}`
- Comment editor: scratch buffer with markdown filetype, `C-c C-c` submit, `C-c C-k` abort (same pattern as commit_editor)

### 2.3 PR Actions

**Modify**: `lua/gitlad/popups/forge.lua`

Expand popup with: `n` create PR, `m` merge, `C` close, `R` reopen, `o` open in browser.

Merge/close/reopen use `gh pr` CLI commands (simpler than raw API for these).

### 2.4 Status Buffer PR Summary

**Modify**: `lua/gitlad/ui/views/status_render.lua`, `lua/gitlad/config.lua`

Optional header line when current branch has a PR:
```
Pull Request: #123 Fix auth bug (APPROVED, +10 -3)
```

Config: `forge.show_pr_in_status = true` (default). Fetched lazily via GraphQL, cached until refresh.

---

## Milestone 3: CI Checks Viewer (DONE)

**Goal**: Show CI/CD check status in PR list, PR detail, and status buffer.
**Depends on**: Milestones 1-2 (forge foundation + PR views).
**Status**: Complete.

### What was built:
- `ForgeCheck` / `ForgeChecksSummary` types normalized from GitHub's CheckRun + StatusContext
- GraphQL queries fetch `statusCheckRollup` for both PR list and PR detail
- Compact check indicators `[3/3]`, `[1/3]`, `[~1/3]` in PR list and status buffer
- Collapsible checks section in PR detail view with per-check status icons, app names, durations
- `gj`/`gk` navigate to check lines, `<CR>` opens check URL, `<Tab>` toggles collapsed
- Highlight groups: `GitladForgeCheckSuccess`, `GitladForgeCheckFailure`, `GitladForgeCheckPending`, `GitladForgeCheckNeutral`

---

## Milestone 4: Native Diff Viewer (DONE)

**Goal**: Replace diffview.nvim with built-in side-by-side diff viewer.
**Depends on**: Nothing (independent, but required before Milestone 5).
**Status**: Complete.

### What was built:

- **Hunk parsing** (`diff/hunk.lua`): Transforms unified diff output into side-by-side `DiffSideBySideHunk` structures with paired context/add/delete/change lines
- **DiffSpec producers** (`diff/source.lua`): Generates `DiffSpec` for staged, unstaged, worktree, commit, range, stash, and PR diffs
- **File content + alignment** (`diff/content.lua`): Retrieves file content via `git show`, aligns left/right sides with filler lines for synchronized display
- **Side-by-side buffer pair** (`diff/buffer.lua`): Two `buftype=nofile` buffers with `scrollbind`/`cursorbind`, treesitter highlighting via filetype detection, diff extmarks for add/delete/change lines
- **File panel sidebar** (`diff/panel.lua`): 35-char sidebar listing changed files with status indicators, diff stats, selection highlighting; PR commit selector with "All changes" and per-commit entries
- **DiffView coordinator** (`diff/init.lua`): Tab-page layout `[panel | left | right]`, file selection, hunk navigation (`]c`/`[c`), file navigation (`gj`/`gk`), refresh, close/cleanup lifecycle
- **Word-level inline diff** (`diff/inline.lua`): LCS-based word diff highlighting within changed lines, `GitladDiffAddInline`/`GitladDiffDeleteInline` highlight groups
- **Diff popup wired to native viewer** (`popups/diff.lua`): All diff actions (staged, unstaged, worktree, commit, range, stash) route to native viewer
- **PR commit navigation**: `<C-n>`/`<C-p>` cycle through individual PR commits or "All changes" view
- **PR diff entry points**: `d` from PR detail view and `N d` from forge popup open native diff viewer with PR context
- **Type definitions** (`diff/types.lua`): `DiffSpec`, `DiffSource`, `DiffPRInfo`, `DiffPRCommit` types

---

## Milestone 5: PR Review

**Goal**: Inline review comments in the native diff viewer.
**Depends on**: Milestones 1-2 + Milestone 4.

### 5.1 PR Diff in Native Viewer

**Modify**: `lua/gitlad/ui/views/diff/init.lua`, `lua/gitlad/forge/github/pr.lua`

PR diff source: fetch unified diff via `git diff <base>...<head>`, full file content via `git show <ref>:<path>`.

### 5.2 Display Existing Review Comments

**Create**: `lua/gitlad/ui/views/diff/review.lua`, `tests/unit/test_diff_review.lua`

Fetch comments via GraphQL (single query for all review threads on a PR).

Rendering: sign column indicator on commented lines, `virt_lines` below showing comment author + body. `<CR>` on comment line expands/collapses full thread.

```
 42 | function login(user, pass)     [2 comments]
    | > @reviewer: Should we add rate limiting here?
    |   > @dave: Good idea, I'll add that in a follow-up
 43 | if not validate(user) then
```

### 5.3 Add New Inline Comments

**Modify**: `lua/gitlad/ui/views/diff/review.lua`, `lua/gitlad/forge/github/review.lua`

`c` in review mode opens comment editor at cursor line. Determine path/line/side from buffer's line_map. Submit via GraphQL mutation. `r` on existing comment replies to thread.

### 5.4 Submit Review

Add review actions to forge popup (available in diff view):
- `a` approve, `r` request changes, `c` comment (via GraphQL `submitPullRequestReview` mutation)

### 5.5 Pending Review (Batch Comments)

Track pending comments in-memory, show with distinct highlight. Submit all as single review via GitHub API: create pending review → add comments → submit with event.

---

## Milestone 6: Polish & Advanced

**Goal**: 3-way merge, PR creation workflow, remaining polish.
**Depends on**: Milestones 1-5.

### 6.1 3-Way Merge View
Extend native diff viewer to 3-pane: BASE | LOCAL | REMOTE. Replaces `d 3` diffview delegation.

### 6.2 PR Creation Workflow
`n` in forge popup: prompt title (default: last commit), open body editor, select base branch, `gh pr create`.

### 6.3 Notification Awareness
Badge on forge popup or status buffer section for unread GitHub notifications.

### 6.4 Issue Management (basic)
List/view issues, create issues. Lower priority than PR workflow.

---

## Key Patterns to Follow

| Pattern | Reference File | Usage |
|---------|---------------|-------|
| Async CLI/HTTP | `git/cli.lua` | `forge/http.lua` |
| PopupBuilder | `ui/popup/init.lua` | `popups/forge.lua` |
| Singleton buffer view | `ui/views/log.lua` | `pr_list.lua`, `pr_detail.lua` |
| Reusable component | `ui/components/log_list.lua` | `components/pr_list.lua`, `components/comment.lua` |
| Two-buffer side-by-side | `ui/views/blame.lua` | `diff/buffer.lua` |
| Elm commands/reducer | `state/commands.lua` | Forge state if needed |
| Picker fallback | `utils/prompt.lua` | PR/branch selection |
| Config extension | `config.lua` | `forge` and `diff` config sections |

## Verification

After each milestone, verify:
1. `make test` passes (all existing + new tests)
2. `make lint` passes
3. New popup/keybinding documented in help popup
4. Manual smoke test with a real GitHub repo
