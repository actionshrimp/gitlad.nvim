#!/usr/bin/env bash
# Parallel test runner for gitlad.nvim
# Runs e2e tests in parallel while preserving mini.test output format
#
# Features:
# - Runs each test file in parallel
# - Auto-splits large test files into batches for better parallelism
# - Configurable via JOBS, MAX_TESTS_PER_BATCH environment variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
# Default to number of CPUs, override with JOBS=N
if [[ -z "$JOBS" ]]; then
    if command -v nproc > /dev/null 2>&1; then
        JOBS=$(nproc)
    elif command -v sysctl > /dev/null 2>&1; then
        JOBS=$(sysctl -n hw.ncpu)
    else
        JOBS=4
    fi
fi

# Max tests per batch before splitting a file
# Files with more tests than this will be split into multiple parallel batches
MAX_TESTS_PER_BATCH=${MAX_TESTS_PER_BATCH:-10}

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Parse arguments
RUN_UNIT=true
RUN_E2E=true
while [[ $# -gt 0 ]]; do
    case $1 in
        --unit-only) RUN_E2E=false; shift ;;
        --e2e-only) RUN_UNIT=false; shift ;;
        --jobs=*) JOBS="${1#*=}"; shift ;;
        -j) JOBS="$2"; shift; shift ;;
        --max-batch=*) MAX_TESTS_PER_BATCH="${1#*=}"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Count tests in a file by looking for T["..."] = function() patterns
# Handles both T["name"] = function() and T["group"]["name"] = function()
count_tests() {
    local file="$1"
    local count
    count=$(grep -cE '^T\["[^"]*"\](\["[^"]*"\])?\s*=\s*function' "$file" 2>/dev/null) || count=0
    # Ensure we return a clean integer
    echo "${count:-0}" | tr -d '\n'
}

export PROJECT_ROOT
export SCRIPT_DIR

echo -e "${BOLD}Running tests with $JOBS parallel jobs${NC}"
echo ""

TOTAL_FAILED=0
TOTAL_PASSED=0

# Run unit tests (fast, run in single process)
if $RUN_UNIT; then
    echo -e "${BOLD}=== Unit Tests ===${NC}"
    UNIT_OUTPUT="$TEMP_DIR/unit_output.txt"

    cd "$PROJECT_ROOT"
    if nvim --headless -u tests/minimal_init.lua \
        -c "lua require('mini.test').setup(); MiniTest.run({collect = {find_files = function() return vim.fn.glob('tests/unit/*.lua', false, true) end}})" \
        -c "qa!" 2>&1 | tee "$UNIT_OUTPUT"; then
        UNIT_EXIT=0
    else
        UNIT_EXIT=1
    fi

    if [ $UNIT_EXIT -ne 0 ]; then
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    else
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    fi
    echo ""
fi

# Run e2e tests in parallel
if $RUN_E2E; then
    echo -e "${BOLD}=== E2E Tests (parallel, $JOBS jobs, max $MAX_TESTS_PER_BATCH tests/batch) ===${NC}"

    cd "$PROJECT_ROOT"
    E2E_FILES=(tests/e2e/*.lua)

    # Create output directory
    E2E_OUTPUT_DIR="$TEMP_DIR/e2e"
    mkdir -p "$E2E_OUTPUT_DIR"

    # Build list of work items (file or file+batch)
    # Format: "file:batch" where batch is empty for whole file, or "1,2,3" for specific tests
    WORK_ITEMS_FILE="$TEMP_DIR/work_items.txt"
    > "$WORK_ITEMS_FILE"

    SPLIT_COUNT=0
    for test_file in "${E2E_FILES[@]}"; do
        test_count=$(count_tests "$test_file")

        if [ "$test_count" -gt "$MAX_TESTS_PER_BATCH" ]; then
            # Split this file into batches
            batch_num=0
            for ((i=1; i<=test_count; i+=MAX_TESTS_PER_BATCH)); do
                batch_num=$((batch_num + 1))
                # Build comma-separated list of test indices for this batch
                batch_indices=""
                for ((j=i; j<i+MAX_TESTS_PER_BATCH && j<=test_count; j++)); do
                    if [ -n "$batch_indices" ]; then
                        batch_indices="$batch_indices,$j"
                    else
                        batch_indices="$j"
                    fi
                done
                echo "$test_file:$batch_indices" >> "$WORK_ITEMS_FILE"
            done
            SPLIT_COUNT=$((SPLIT_COUNT + 1))
        else
            # Run whole file as single work item
            echo "$test_file:" >> "$WORK_ITEMS_FILE"
        fi
    done

    WORK_COUNT=$(wc -l < "$WORK_ITEMS_FILE" | tr -d ' ')
    if [ "$SPLIT_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}Split $SPLIT_COUNT large file(s) into batches (${#E2E_FILES[@]} files → $WORK_COUNT work items)${NC}"
    fi

    # Create a runner script for parallel to execute
    RUNNER_SCRIPT="$TEMP_DIR/run_work_item.sh"
    cat > "$RUNNER_SCRIPT" << 'RUNNER_EOF'
#!/usr/bin/env bash
work_item="$1"
script_dir="$2"
output_dir="$3"

test_file="${work_item%%:*}"
batch="${work_item#*:}"
basename=$(basename "$test_file")

if [ -n "$batch" ]; then
    outfile="${output_dir}/${basename}.batch_${batch//,/_}.out"
else
    outfile="${output_dir}/${basename}.out"
fi

# Run test - output includes timing from Lua
# Colorize: SLOW tests red, WARN tests yellow, FAIL status red
TEST_FILE="$test_file" TEST_BATCH="$batch" TEST_OUTPUT_MODE="streaming" \
    nvim --headless -u tests/minimal_init.lua \
    -c "luafile ${script_dir}/test_batch.lua" \
    -c "qa!" 2>&1 | tee "$outfile" | while IFS= read -r line; do
    case "$line" in
        SLOW*) printf '\033[0;31m%s\033[0m\n' "$line" ;;
        WARN*) printf '\033[1;33m%s\033[0m\n' "$line" ;;
        *FAIL*) printf '\033[0;31m%s\033[0m\n' "$line" ;;
        *) printf '%s\n' "$line" ;;
    esac
done
exit_code=${PIPESTATUS[0]}

# Store exit code for later
echo $exit_code > "${outfile}.exit"
RUNNER_EOF
    chmod +x "$RUNNER_SCRIPT"

    # Run work items in parallel, streaming output as tests complete
    cat "$WORK_ITEMS_FILE" | \
        parallel -j "$JOBS" --will-cite --line-buffer \
        "$RUNNER_SCRIPT" {} "$SCRIPT_DIR" "$E2E_OUTPUT_DIR"

    echo ""

    # Count passes and failures
    E2E_PASSED=0
    E2E_FAILED=0
    FAILED_ITEMS=()

    for exit_file in "$E2E_OUTPUT_DIR"/*.exit; do
        [ -f "$exit_file" ] || continue
        exit_code=$(cat "$exit_file")
        if [ "$exit_code" -eq 0 ]; then
            E2E_PASSED=$((E2E_PASSED + 1))
        else
            E2E_FAILED=$((E2E_FAILED + 1))
            FAILED_ITEMS+=("${exit_file%.exit}")
        fi
    done

    # Show failures in detail
    if [ ${#FAILED_ITEMS[@]} -gt 0 ]; then
        echo -e "${RED}${BOLD}=== Failed Test Details ===${NC}"
        for output_file in "${FAILED_ITEMS[@]}"; do
            echo -e "\n${RED}--- $output_file ---${NC}"
            cat "$output_file"
        done
        echo ""
    fi

    TOTAL_PASSED=$((TOTAL_PASSED + E2E_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + E2E_FAILED))
fi

# Summary
echo -e "${BOLD}=== Summary ===${NC}"
if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "${GREEN}All test files passed!${NC}"
    exit 0
else
    echo -e "${RED}$TOTAL_FAILED test file(s) failed${NC}"
    exit 1
fi
