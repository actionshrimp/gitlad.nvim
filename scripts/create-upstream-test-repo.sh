#!/usr/bin/env bash
# Creates a test git repository with upstream tracking configured
# This is used for testing the Merge/Push display in the status view
set -e

REPO_DIR="${1:-/tmp/gitlad-upstream-test-repo}"
REMOTE_DIR="${2:-/tmp/gitlad-upstream-test-remote}"

# Clean up existing repos
rm -rf "$REPO_DIR" "$REMOTE_DIR"

# Create the bare remote repository
mkdir -p "$REMOTE_DIR"
git -C "$REMOTE_DIR" init --bare

# Create the local repository
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

git init
git config user.email "test@example.com"
git config user.name "Test User"

# Create initial commit
cat > README.md << 'EOF'
# Test Project

A test project with upstream tracking.
EOF

git add .
git commit -m "Initial commit"

# Add remote and push with tracking
git remote add origin "$REMOTE_DIR"

# Get the default branch name
DEFAULT_BRANCH=$(git branch --show-current)

# Push and set up tracking
git push -u origin "$DEFAULT_BRANCH"

# Create a local commit ahead of upstream
echo "Local change" >> README.md
git add README.md
git commit -m "Local commit ahead of upstream"

echo ""
echo "=========================================="
echo "Test repository created at: $REPO_DIR"
echo "Remote repository at: $REMOTE_DIR"
echo "=========================================="
echo ""
echo "Branch: $DEFAULT_BRANCH"
echo "Upstream: origin/$DEFAULT_BRANCH"
echo ""
echo "Status:"
git status --short
echo ""
echo "Ahead/Behind:"
git rev-list --left-right --count origin/$DEFAULT_BRANCH...HEAD
