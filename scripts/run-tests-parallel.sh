#!/usr/bin/env bash
# Parallel test runner for gitlad.nvim
# Runs e2e test files in parallel using GNU parallel
#
# Each test file runs in its own Neovim instance using mini.test natively.
# Outputs per-file timing to help identify slow test files that may need splitting.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration - default to min(4, nproc)
# Higher parallelism causes contention when spawning child Neovim processes
# (each test case spawns a child via mini.test, and the connection polling
# loop slows down significantly under load)
if [[ -z "$JOBS" ]]; then
    if command -v nproc > /dev/null 2>&1; then
        CPU_COUNT=$(nproc)
    elif command -v sysctl > /dev/null 2>&1; then
        CPU_COUNT=$(sysctl -n hw.ncpu)
    else
        CPU_COUNT=4
    fi
    # Cap at 4 - tests are I/O bound, not CPU bound
    JOBS=$((CPU_COUNT < 4 ? CPU_COUNT : 4))
fi

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
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

export PROJECT_ROOT

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

# Run e2e tests in parallel (one file per job)
if $RUN_E2E; then
    echo -e "${BOLD}=== E2E Tests (parallel, $JOBS jobs) ===${NC}"

    cd "$PROJECT_ROOT"

    # Create output directory
    OUTPUT_DIR="$TEMP_DIR/e2e"
    mkdir -p "$OUTPUT_DIR"

    # Create runner script that runs a single test file and tracks timing
    RUNNER_SCRIPT="$TEMP_DIR/run_test_file.sh"
    cat > "$RUNNER_SCRIPT" << 'EOF'
#!/usr/bin/env bash
test_file="$1"
output_dir="$2"
basename=$(basename "$test_file" .lua)
outfile="$output_dir/${basename}.out"
timefile="$output_dir/${basename}.time"

# Record start time
start_time=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')

# Run mini.test natively on this single file
nvim --headless -u tests/minimal_init.lua \
    -c "lua require('mini.test').setup(); local ok, err = pcall(MiniTest.run, {collect = {find_files = function() return {'$test_file'} end}}); if not ok then print('Error: ' .. err); vim.cmd('cq!') end; local has_fail = false; for _, c in ipairs(MiniTest.current.all_cases or {}) do if c.exec and c.exec.state == 'Fail' then has_fail = true; break end end; if has_fail then vim.cmd('cq!') end" \
    -c "qa!" > "$outfile" 2>&1
exit_code=$?

# Record end time and calculate duration
end_time=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
duration=$((end_time - start_time))

# Write timing info
echo "$duration" > "$timefile"

# Store exit code
echo "$exit_code" > "${outfile}.exit"

# Print status line with timing
if [ $exit_code -eq 0 ]; then
    printf "[%5dms] %-40s %s\n" "$duration" "$basename" "PASS"
else
    printf "[%5dms] %-40s %s\n" "$duration" "$basename" "FAIL"
fi

exit $exit_code
EOF
    chmod +x "$RUNNER_SCRIPT"

    # Get list of e2e test files
    E2E_FILES=(tests/e2e/*.lua)
    echo "Running ${#E2E_FILES[@]} test files..."
    echo ""

    # Run files in parallel
    # Use --halt soon,fail=1 to continue running but track failures
    # Use --line-buffer to stream output as tests complete
    printf '%s\n' "${E2E_FILES[@]}" | \
        parallel -j "$JOBS" --will-cite --line-buffer --halt soon,fail=1 \
        "$RUNNER_SCRIPT" {} "$OUTPUT_DIR" || true

    echo ""

    # Count passes and failures, collect timing data
    E2E_PASSED=0
    E2E_FAILED=0
    FAILED_FILES=()
    declare -a TIMING_DATA

    for exit_file in "$OUTPUT_DIR"/*.exit; do
        [ -f "$exit_file" ] || continue
        basename=$(basename "$exit_file" .out.exit)
        exit_code=$(cat "$exit_file")
        timefile="$OUTPUT_DIR/${basename}.time"
        duration=0
        [ -f "$timefile" ] && duration=$(cat "$timefile")

        TIMING_DATA+=("$duration $basename")

        if [ "$exit_code" -eq 0 ]; then
            E2E_PASSED=$((E2E_PASSED + 1))
        else
            E2E_FAILED=$((E2E_FAILED + 1))
            FAILED_FILES+=("$OUTPUT_DIR/${basename}.out")
        fi
    done

    # Show failures in detail
    if [ ${#FAILED_FILES[@]} -gt 0 ]; then
        echo -e "${RED}${BOLD}=== Failed Test Output ===${NC}"
        for output_file in "${FAILED_FILES[@]}"; do
            echo -e "\n${RED}--- $(basename "$output_file" .out) ---${NC}"
            cat "$output_file"
        done
        echo ""
    fi

    # Show timing report (sorted by duration, slowest first)
    echo -e "${BOLD}=== Timing Report (slowest first) ===${NC}"
    printf '%s\n' "${TIMING_DATA[@]}" | sort -rn | head -10 | while read duration name; do
        if [ "$duration" -ge 5000 ]; then
            printf "${RED}[%5dms] %s${NC}\n" "$duration" "$name"
        elif [ "$duration" -ge 3000 ]; then
            printf "${YELLOW}[%5dms] %s${NC}\n" "$duration" "$name"
        else
            printf "[%5dms] %s\n" "$duration" "$name"
        fi
    done
    echo ""

    TOTAL_PASSED=$((TOTAL_PASSED + E2E_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + E2E_FAILED))
fi

# Summary
echo -e "${BOLD}=== Summary ===${NC}"
if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL_PASSED test files passed!${NC}"
    exit 0
else
    echo -e "${RED}$TOTAL_FAILED test file(s) failed, $TOTAL_PASSED passed${NC}"
    exit 1
fi
