#!/usr/bin/env bash
# Parallel test runner for gitlad.nvim
# Runs e2e tests in parallel while preserving mini.test output format

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

run_single_test_file() {
    local test_file="$1"
    local output_file="$2"
    local basename=$(basename "$test_file")

    # Run test and capture output + exit code
    nvim --headless -u tests/minimal_init.lua \
        -c "lua require('mini.test').setup(); MiniTest.run({collect = {find_files = function() return {'$test_file'} end}})" \
        -c "qa!" 2>&1 > "$output_file"
    echo $? > "${output_file}.exit"
}

export -f run_single_test_file
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

# Run e2e tests in parallel
if $RUN_E2E; then
    echo -e "${BOLD}=== E2E Tests (parallel, $JOBS jobs) ===${NC}"

    cd "$PROJECT_ROOT"
    E2E_FILES=(tests/e2e/*.lua)
    E2E_COUNT=${#E2E_FILES[@]}

    # Create output directory
    E2E_OUTPUT_DIR="$TEMP_DIR/e2e"
    mkdir -p "$E2E_OUTPUT_DIR"

    # Run tests in parallel using GNU parallel
    printf '%s\n' "${E2E_FILES[@]}" | \
        parallel -j "$JOBS" --will-cite \
        "nvim --headless -u tests/minimal_init.lua \
            -c \"lua require('mini.test').setup(); MiniTest.run({collect = {find_files = function() return {'{}'} end}})\" \
            -c 'qa!' > '$E2E_OUTPUT_DIR/{/}.out' 2>&1; echo \$? > '$E2E_OUTPUT_DIR/{/}.exit'"

    # Process and display results
    E2E_PASSED=0
    E2E_FAILED=0
    FAILED_FILES=()

    for test_file in "${E2E_FILES[@]}"; do
        basename=$(basename "$test_file")
        output_file="$E2E_OUTPUT_DIR/${basename}.out"
        exit_file="$E2E_OUTPUT_DIR/${basename}.exit"

        exit_code=$(cat "$exit_file" 2>/dev/null || echo "1")

        if [ "$exit_code" -eq 0 ]; then
            # Extract just the test result line (the one with dots)
            result_line=$(grep "^$test_file:" "$output_file" 2>/dev/null || echo "$test_file: ?")
            echo "$result_line"
            E2E_PASSED=$((E2E_PASSED + 1))
        else
            echo -e "${RED}$test_file: FAILED${NC}"
            E2E_FAILED=$((E2E_FAILED + 1))
            FAILED_FILES+=("$test_file")
        fi
    done

    echo ""

    # Show failures in detail
    if [ ${#FAILED_FILES[@]} -gt 0 ]; then
        echo -e "${RED}${BOLD}=== Failed Test Details ===${NC}"
        for failed_file in "${FAILED_FILES[@]}"; do
            basename=$(basename "$failed_file")
            output_file="$E2E_OUTPUT_DIR/${basename}.out"
            echo -e "\n${RED}--- $failed_file ---${NC}"
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
