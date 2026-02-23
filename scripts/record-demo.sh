#!/usr/bin/env bash
# Record an asciinema demo of gitlad.nvim
# Uses tmux to create a terminal of the correct dimensions
#
# Prerequisites: brew install asciinema tmux agg; npm install -g tree-sitter-cli
#
# Dependencies (lazy.nvim, kanagawa, treesitter) are bootstrapped by
# demo-init.lua and cached in /tmp/gitlad-demo-deps/ across runs.
#
# Output: docs/demo.cast
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_DIR="/tmp/gitlad-demo-repo"
OUTPUT="${PROJECT_ROOT}/docs/demo.cast"
OUTPUT_V2="${PROJECT_ROOT}/docs/demo-v2.cast"
OUTPUT_GIF="${PROJECT_ROOT}/docs/demo-preview.gif"
COLS=130
ROWS=42
SESSION="gitlad-demo"

# Check prerequisites
for cmd in asciinema tmux tree-sitter nvim agg; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required. Install with: brew install $cmd"
    exit 1
  fi
done

echo "==> Creating test repo..."
"$SCRIPT_DIR/create-test-repo.sh" "$REPO_DIR" > /dev/null 2>&1

# Pre-clone plugins so lazy.nvim finds them on disk (lazy's headless install
# is unreliable). Subsequent runs skip already-cached plugins.
DEPS_DIR="/tmp/gitlad-demo-deps"
PLUGIN_DIR="$DEPS_DIR/plugins"
LAZY_PATH="$DEPS_DIR/lazy.nvim"
mkdir -p "$PLUGIN_DIR"

if [ ! -d "$LAZY_PATH/.git" ]; then
  echo "  Installing lazy.nvim..."
  rm -rf "$LAZY_PATH"
  git clone --filter=blob:none --branch=stable \
    https://github.com/folke/lazy.nvim.git "$LAZY_PATH" 2>/dev/null
fi

for plugin in rebelot/kanagawa.nvim nvim-treesitter/nvim-treesitter; do
  name="${plugin##*/}"
  if [ ! -d "$PLUGIN_DIR/$name" ]; then
    echo "  Installing $name..."
    git clone --depth=1 "https://github.com/$plugin" "$PLUGIN_DIR/$name" 2>/dev/null
  fi
done

# Warmup: compile treesitter parsers (plugins are already on disk).
echo "==> Installing demo dependencies (cached after first run)..."
cd "$REPO_DIR"
GITLAD_DEMO_WARMUP=1 nvim \
  -u "${PROJECT_ROOT}/scripts/demo-init.lua" \
  --headless \
  -S "${PROJECT_ROOT}/scripts/demo-warmup.lua" \
  2>&1 | grep -E '^\[|^All|^Timeout|^Error' || true

# Kill any existing demo session
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo "==> Recording demo at ${COLS}x${ROWS}..."

# Create a detached tmux session with the exact dimensions we want
tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"

# Run the recording inside tmux (cd to repo, then record)
tmux send-keys -t "$SESSION" \
  "cd '$REPO_DIR' && asciinema rec '$OUTPUT' --overwrite --command \"nvim -u '${PROJECT_ROOT}/scripts/demo-init.lua'\" ; tmux wait-for -S demo-done" Enter

# Wait for the recording to finish
tmux wait-for demo-done

# Clean up
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Convert to v2 format for the web player (asciinema-player 3.x)
echo "==> Converting to v2 format for web player..."
asciinema convert -f asciicast-v2 "$OUTPUT" "$OUTPUT_V2" --overwrite

# Generate GIF for README (renders pixel-perfect on GitHub, unlike SVG)
echo "==> Generating GIF for README..."
agg "$OUTPUT_V2" "$OUTPUT_GIF" --font-size 14

echo ""
echo "==> Demo recorded to:"
echo "  v3: $OUTPUT"
echo "  v2: $OUTPUT_V2"
echo "  gif: $OUTPUT_GIF"
echo ""
echo "Preview locally:"
echo "  asciinema play $OUTPUT"
echo ""
ls -lh "$OUTPUT" "$OUTPUT_V2" "$OUTPUT_GIF"
