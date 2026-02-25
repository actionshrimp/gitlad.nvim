#!/usr/bin/env bash
# Creates a real GitHub repository for the forge/GitHub demo.
# Sets up a PR with comments, code reviews, and inline diff comments.
#
# Prerequisites: gh CLI authenticated (gh auth token must succeed)
#
# Usage: ./create-forge-test-repo.sh [clone-dir]
set -e

CLONE_DIR="${1:-/tmp/gitlad-forge-demo-repo}"
REPO_NAME="actionshrimp/gitlad-demo-repo"

# Check prerequisites
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is required. Install with: brew install gh"
  exit 1
fi

if ! gh auth token &>/dev/null; then
  echo "Error: gh is not authenticated. Run: gh auth login"
  exit 1
fi

echo "==> Setting up forge demo repo: $REPO_NAME"

# ---------------------------------------------------------------------------
# Check if repo + PR already exist — skip setup if so
# ---------------------------------------------------------------------------
NEED_SETUP=true
if gh repo view "$REPO_NAME" &>/dev/null; then
  EXISTING_PR=$(gh pr list --repo "$REPO_NAME" --head feature/add-validation --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$EXISTING_PR" ]; then
    echo "  Repo exists with open PR #$EXISTING_PR, skipping setup."
    NEED_SETUP=false
  fi
else
  echo "  Creating private repo..."
  gh repo create "$REPO_NAME" --private --description "Demo repo for gitlad.nvim forge features"
fi

if [ "$NEED_SETUP" = true ]; then
  # Close any stale PRs and delete feature branch
  if gh repo view "$REPO_NAME" &>/dev/null; then
    for pr in $(gh pr list --repo "$REPO_NAME" --state open --json number --jq '.[].number'); do
      gh pr close "$pr" --repo "$REPO_NAME" 2>/dev/null || true
    done
    gh api "repos/$REPO_NAME/git/refs/heads/feature/add-validation" -X DELETE 2>/dev/null || true
  fi

  # ---------------------------------------------------------------------------
  # Create local repo and push initial content
  # ---------------------------------------------------------------------------
  WORK_DIR=$(mktemp -d)
  cd "$WORK_DIR"
  git init
  git config user.email "demo@gitlad.nvim"
  git config user.name "gitlad demo"

  # Initial commit: simple project structure
  mkdir -p src tests
  cat > src/main.lua << 'EOF'
-- Main application entry point
local M = {}

function M.setup(opts)
  opts = opts or {}
  M.config = {
    debug = opts.debug or false,
    log_level = opts.log_level or "info",
    max_retries = opts.max_retries or 3,
  }
end

function M.run()
  if M.config.debug then
    print("Running in debug mode")
  end
  return M.process()
end

function M.process()
  local results = {}
  for i = 1, 10 do
    table.insert(results, i * 2)
  end
  return results
end

return M
EOF

  cat > src/utils.lua << 'EOF'
-- Utility functions
local M = {}

function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

function M.split(s, sep)
  local parts = {}
  for part in s:gmatch("([^" .. sep .. "]+)") do
    table.insert(parts, part)
  end
  return parts
end

function M.contains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then return true end
  end
  return false
end

return M
EOF

  cat > tests/main_test.lua << 'EOF'
-- Tests for main module
local main = require("src.main")

main.setup()
assert(main.config.debug == false)
assert(main.config.log_level == "info")

main.setup({ debug = true })
assert(main.config.debug == true)

local results = main.run()
assert(#results == 10)
assert(results[1] == 2)

print("All tests passed!")
EOF

  cat > README.md << 'EOF'
# Demo Project

A sample project for demonstrating gitlad.nvim forge features.
EOF

  git add .
  git commit -m "Initial project structure"

  # Second commit
  cat > src/config.lua << 'EOF'
-- Configuration module
local M = {}

M.defaults = {
  timeout = 5000,
  retries = 3,
  verbose = false,
}

function M.merge(user_opts)
  local config = {}
  for k, v in pairs(M.defaults) do
    config[k] = v
  end
  if user_opts then
    for k, v in pairs(user_opts) do
      config[k] = v
    end
  end
  return config
end

return M
EOF

  git add .
  git commit -m "Add configuration module"

  # Push main branch
  git remote add origin "git@github.com:$REPO_NAME.git"
  git branch -M main
  git push -u origin main --force

  # ---------------------------------------------------------------------------
  # Create feature branch with meaningful changes
  # ---------------------------------------------------------------------------
  git checkout -b feature/add-validation

  # Commit 1: Add validation module
  cat > src/validate.lua << 'EOF'
-- Input validation utilities
local M = {}

function M.is_string(value)
  return type(value) == "string"
end

function M.is_number(value)
  return type(value) == "number"
end

function M.is_positive(value)
  return type(value) == "number" and value > 0
end

function M.in_range(value, min, max)
  return type(value) == "number" and value >= min and value <= max
end

function M.matches_pattern(value, pattern)
  if type(value) ~= "string" then return false end
  return value:match(pattern) ~= nil
end

function M.validate_config(config)
  local errors = {}
  if not M.is_positive(config.timeout) then
    table.insert(errors, "timeout must be a positive number")
  end
  if not M.in_range(config.retries, 0, 10) then
    table.insert(errors, "retries must be between 0 and 10")
  end
  return #errors == 0, errors
end

return M
EOF

  # Commit 1: Also modify main.lua to use validation
  cat > src/main.lua << 'EOF'
-- Main application entry point
local validate = require("src.validate")
local M = {}

function M.setup(opts)
  opts = opts or {}
  M.config = {
    debug = opts.debug or false,
    log_level = opts.log_level or "info",
    max_retries = opts.max_retries or 3,
    timeout = opts.timeout or 5000,
  }

  local ok, errors = validate.validate_config(M.config)
  if not ok then
    error("Invalid config: " .. table.concat(errors, ", "))
  end
end

function M.run()
  if M.config.debug then
    print("Running in debug mode")
  end
  return M.process()
end

function M.process()
  local results = {}
  for i = 1, M.config.max_retries do
    local value = i * 2
    if validate.is_positive(value) then
      table.insert(results, value)
    end
  end
  return results
end

return M
EOF

  git add .
  git commit -m "Add input validation module

Introduces a validation library for type checking and config validation.
Updated main.lua to validate configuration on setup."

  # Commit 2: Add tests for validation
  cat > tests/validate_test.lua << 'EOF'
-- Tests for validation module
local validate = require("src.validate")

-- Type checks
assert(validate.is_string("hello") == true)
assert(validate.is_string(42) == false)
assert(validate.is_number(42) == true)
assert(validate.is_number("42") == false)

-- Range checks
assert(validate.is_positive(5) == true)
assert(validate.is_positive(-1) == false)
assert(validate.in_range(5, 1, 10) == true)
assert(validate.in_range(15, 1, 10) == false)

-- Pattern matching
assert(validate.matches_pattern("hello@world.com", "%w+@%w+%.%w+") == true)
assert(validate.matches_pattern("not-an-email", "%w+@%w+%.%w+") == false)

-- Config validation
local ok, errors = validate.validate_config({ timeout = 5000, retries = 3 })
assert(ok == true)
assert(#errors == 0)

local ok2, errors2 = validate.validate_config({ timeout = -1, retries = 3 })
assert(ok2 == false)
assert(#errors2 == 1)

print("All validation tests passed!")
EOF

  # Also update utils with a new function
  cat > src/utils.lua << 'EOF'
-- Utility functions
local M = {}

function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

function M.split(s, sep)
  local parts = {}
  for part in s:gmatch("([^" .. sep .. "]+)") do
    table.insert(parts, part)
  end
  return parts
end

function M.contains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then return true end
  end
  return false
end

function M.map(tbl, fn)
  local result = {}
  for i, v in ipairs(tbl) do
    result[i] = fn(v, i)
  end
  return result
end

function M.filter(tbl, fn)
  local result = {}
  for _, v in ipairs(tbl) do
    if fn(v) then
      table.insert(result, v)
    end
  end
  return result
end

return M
EOF

  git add .
  git commit -m "Add validation tests and extend utils

Comprehensive tests for the validation module.
Added map() and filter() utility functions."

  # Push the feature branch
  git push -u origin feature/add-validation --force

  # ---------------------------------------------------------------------------
  # Create PR
  # ---------------------------------------------------------------------------
  echo "  Creating pull request..."
  PR_URL=$(gh pr create \
    --title "Add input validation module" \
    --body "$(cat <<'PRBODY'
## Summary

This PR adds a validation module for input type checking and configuration validation.

### Changes
- New `src/validate.lua` with type checks, range validation, and pattern matching
- Updated `src/main.lua` to validate config on setup
- Extended `src/utils.lua` with `map()` and `filter()` functions
- Comprehensive tests in `tests/validate_test.lua`

## Test plan
- [x] Unit tests for all validation functions
- [x] Config validation integration test
- [ ] Manual testing with edge cases
PRBODY
)" \
    --head feature/add-validation \
    --base main)

  PR_NUMBER=$(echo "$PR_URL" | grep -o '[0-9]*$')
  echo "  Created PR #$PR_NUMBER: $PR_URL"

  # ---------------------------------------------------------------------------
  # Add PR comments and reviews via API
  # ---------------------------------------------------------------------------
  echo "  Adding PR comments..."

  # General PR comment
  gh api "repos/$REPO_NAME/issues/$PR_NUMBER/comments" \
    -f body="Looks like a solid foundation for validation! A couple of thoughts:

1. The \`validate_config\` function is clean — love that it returns both a boolean and the error list.
2. Have you considered adding a \`validate_schema\` function for more complex nested configs?

Nice work overall." > /dev/null

  # Code review with inline comments
  echo "  Adding code review with inline comments..."

  # Get the latest commit SHA for the PR
  HEAD_SHA=$(gh api "repos/$REPO_NAME/pulls/$PR_NUMBER" --jq '.head.sha')

  # Create a review with inline comments
  gh api "repos/$REPO_NAME/pulls/$PR_NUMBER/reviews" \
    -f event="COMMENT" \
    -f body="Good progress! Left a few inline suggestions." \
    -f commit_id="$HEAD_SHA" \
    --jq '.id' \
    -F "comments[][path]=src/validate.lua" \
    -F "comments[][line]=26" \
    -F "comments[][body]=Consider using \`tonumber()\` here as a fallback — some callers might pass string representations of numbers." \
    -F "comments[][path]=src/main.lua" \
    -F "comments[][line]=18" \
    -F "comments[][body]=This error message could be more descriptive. Maybe include which config keys failed validation?" \
    -F "comments[][path]=src/utils.lua" \
    -F "comments[][line]=38" \
    -F "comments[][body]=Nice addition! But the \`map\` function signature should probably document that \`fn\` receives \`(value, index)\` — it's not obvious from the name alone." > /dev/null

  # Add another general comment as a follow-up
  gh api "repos/$REPO_NAME/issues/$PR_NUMBER/comments" \
    -f body="One more thing — the \`matches_pattern\` function uses Lua patterns, not regex. Might be worth adding a note in the docstring so users don't get confused by the difference." > /dev/null

  # Clean up temp dir
  rm -rf "$WORK_DIR"
fi

# ---------------------------------------------------------------------------
# Clone to target directory
# ---------------------------------------------------------------------------
echo "  Cloning to $CLONE_DIR..."
rm -rf "$CLONE_DIR"
gh repo clone "$REPO_NAME" "$CLONE_DIR" -- --quiet
cd "$CLONE_DIR"
git config user.email "demo@gitlad.nvim"
git config user.name "gitlad demo"

echo ""
echo "=========================================="
echo "Forge demo repo ready: $CLONE_DIR"
echo "=========================================="
