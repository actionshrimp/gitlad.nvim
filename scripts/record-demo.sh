#!/usr/bin/env bash
# Record asciinema demos of gitlad.nvim
# Uses tmux to create a terminal of the correct dimensions
#
# Dependencies (lazy.nvim, kanagawa, treesitter) are bootstrapped by
# demo-init.lua and cached in /tmp/gitlad-demo-deps/ across runs.
#
# Usage:
#   ./record-demo.sh           # Record all demos
#   ./record-demo.sh basics    # Record only basics demo
#   ./record-demo.sh advanced  # Record only advanced diff demo
#   ./record-demo.sh forge     # Record only forge/GitHub demo
#
# Output: docs/demo-{basics,advanced,forge}.cast + v2 variants
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COLS=130
ROWS=42
SESSION="gitlad-demo"

DEMO="${1:-all}"

# ---------------------------------------------------------------------------
# Enter nix-shell if not already inside one
# ---------------------------------------------------------------------------
if [ -z "$IN_NIX_SHELL" ]; then
  exec nix-shell -p asciinema_3 asciinema-agg tmux --run "IN_NIX_SHELL=1 $0 $*"
fi

# Check prerequisites not provided by nix
for cmd in tree-sitter nvim; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not found on PATH"
    exit 1
  fi
done

# gh is needed for forge demo
if [[ "$DEMO" == "all" || "$DEMO" == "forge" ]]; then
  if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required for forge demo. Install with: brew install gh"
    exit 1
  fi
  if ! gh auth token &>/dev/null; then
    echo "Error: gh is not authenticated. Run: gh auth login"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Pre-cache plugins (shared by all demos)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Helper: record a single demo
# ---------------------------------------------------------------------------
record_demo() {
  local name="$1"       # e.g. "basics"
  local driver="$2"     # e.g. "demo-basics-driver.lua"
  local repo_dir="$3"   # working directory for the recording
  local gen_gif="$4"    # "yes" to generate GIF

  local output="${PROJECT_ROOT}/docs/demo-${name}.cast"
  local output_v2="${PROJECT_ROOT}/docs/demo-${name}-v2.cast"

  echo ""
  echo "==> Recording '$name' demo..."

  # Warmup: compile treesitter parsers
  echo "  Warming up (treesitter parsers)..."
  cd "$repo_dir"
  GITLAD_DEMO_WARMUP=1 nvim \
    -u "${PROJECT_ROOT}/scripts/demo-init.lua" \
    --headless \
    -S "${PROJECT_ROOT}/scripts/demo-warmup.lua" \
    2>&1 | grep -E '^\[|^All|^Timeout|^Error' || true

  # Kill any existing demo session
  tmux kill-session -t "$SESSION" 2>/dev/null || true

  echo "  Recording at ${COLS}x${ROWS}..."

  # Create a detached tmux session with the exact dimensions
  tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"

  # Run the recording inside tmux
  tmux send-keys -t "$SESSION" \
    "cd '$repo_dir' && GITLAD_DEMO_DRIVER='$driver' asciinema rec '$output' --overwrite --command \"nvim -u '${PROJECT_ROOT}/scripts/demo-init.lua'\" ; tmux wait-for -S demo-done" Enter

  # Wait for the recording to finish
  tmux wait-for demo-done

  # Clean up tmux
  tmux kill-session -t "$SESSION" 2>/dev/null || true

  # Convert to v2 format for the web player
  echo "  Converting to v2 format..."
  asciinema convert -f asciicast-v2 "$output" "$output_v2" --overwrite

  # Generate GIF if requested (for README)
  if [[ "$gen_gif" == "yes" ]]; then
    local output_gif="${PROJECT_ROOT}/docs/demo-${name}-preview.gif"
    echo "  Generating GIF..."
    agg "$output_v2" "$output_gif" --font-size 14
    echo "  Output: $output, $output_v2, $output_gif"
    ls -lh "$output" "$output_v2" "$output_gif"
  else
    echo "  Output: $output, $output_v2"
    ls -lh "$output" "$output_v2"
  fi
}

# ---------------------------------------------------------------------------
# Record requested demos
# ---------------------------------------------------------------------------

if [[ "$DEMO" == "all" || "$DEMO" == "basics" ]]; then
  REPO_DIR="/tmp/gitlad-demo-repo"
  echo "==> Creating test repo for basics demo..."
  "$SCRIPT_DIR/create-test-repo.sh" "$REPO_DIR" > /dev/null 2>&1
  record_demo "basics" "demo-basics-driver.lua" "$REPO_DIR" "yes"
fi

if [[ "$DEMO" == "all" || "$DEMO" == "advanced" ]]; then
  REPO_DIR="/tmp/gitlad-demo-repo"
  echo "==> Creating test repo for advanced demo..."
  "$SCRIPT_DIR/create-test-repo.sh" "$REPO_DIR" > /dev/null 2>&1
  record_demo "advanced" "demo-advanced-driver.lua" "$REPO_DIR" "yes"
fi

if [[ "$DEMO" == "all" || "$DEMO" == "forge" ]]; then
  FORGE_REPO_DIR="/tmp/gitlad-forge-demo-repo"
  echo "==> Creating forge test repo (requires GitHub API)..."
  "$SCRIPT_DIR/create-forge-test-repo.sh" "$FORGE_REPO_DIR"
  record_demo "forge" "demo-forge-driver.lua" "$FORGE_REPO_DIR" "yes"
fi

echo ""
echo "==> Done!"
echo ""
echo "Preview locally:"
if [[ "$DEMO" == "all" || "$DEMO" == "basics" ]]; then
  echo "  asciinema play ${PROJECT_ROOT}/docs/demo-basics.cast"
fi
if [[ "$DEMO" == "all" || "$DEMO" == "advanced" ]]; then
  echo "  asciinema play ${PROJECT_ROOT}/docs/demo-advanced.cast"
fi
if [[ "$DEMO" == "all" || "$DEMO" == "forge" ]]; then
  echo "  asciinema play ${PROJECT_ROOT}/docs/demo-forge.cast"
fi
