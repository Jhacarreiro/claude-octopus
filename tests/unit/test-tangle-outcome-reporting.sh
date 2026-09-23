#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/testing.sh"
test_suite "tangle terminal outcome reporting"
mkdir -p "$TEST_TMP_DIR"

make_result() {
    local name="$1" status="$2" output="${3:-work completed}"
    local path="$TEST_TMP_DIR/$name.md"
    cat > "$path" <<EOF
# Agent: test
# Task ID: $name
## Output
$output
## Status: $status
EOF
    printf '%s\n' "$path"
}

success=$(make_result success 'SUCCESS')
timeout=$(make_result timeout 'TIMEOUT - PARTIAL RESULTS (exit code: 124)')
persistence=$(make_result persistence 'FAILED (Execution contract persistence failed)')
failed=$(make_result failed 'FAILED (provider error)')
blocked=$(make_result blocked 'SUCCESS' 'Cannot complete: sandbox is blocking filesystem access.')

for spec in \
    "$success:success" \
    "$timeout:timeout" \
    "$persistence:persistence_failed" \
    "$failed:failed" \
    "$blocked:blocked"; do
    file="${spec%:*}"
    expected="${spec##*:}"
    test_case "classifies $(basename "$file") as $expected"
    if [[ "$(tangle_result_terminal_outcome "$file")" == "$expected" ]]; then
        test_pass
    else
        test_fail "unexpected terminal outcome"
    fi
done

test_case "summarizes mixed terminal outcomes"
summary=$(tangle_result_paths_outcome_summary "$success
$timeout
$persistence
$failed
$blocked")
if [[ "$summary" == "1 succeeded, 1 timed out, 1 persistence failed, 1 blocked, 1 failed" ]]; then
    test_pass
else
    test_fail "unexpected summary: $summary"
fi

test_case "accepts result: retry candidate prefixes"
summary=$(tangle_result_paths_outcome_summary "result:$timeout
result:$persistence")
if [[ "$summary" == "1 timed out, 1 persistence failed" ]]; then
    test_pass
else
    test_fail "unexpected retry summary: $summary"
fi

test_case "counts missing dispatched results as unknown"
summary=$(tangle_result_paths_outcome_summary "$success" $'success\nmissing')
if [[ "$summary" == "1 succeeded, 1 unknown" ]]; then
    test_pass
else
    test_fail "missing dispatched result was not reported as unknown: $summary"
fi

test_case "watcher reports finished rather than complete"
if grep -q 'subtasks finished' "$PROJECT_ROOT/scripts/lib/workflows.sh" \
   && ! grep -q 'subtasks complete' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
    test_pass
else
    test_fail "watcher still labels terminal tasks as complete"
fi

test_case "retry branch reports candidate terminal outcomes"
if grep -q 'Retrying failed subtasks:' "$PROJECT_ROOT/scripts/lib/testing.sh" \
   && grep -q 'candidate terminal outcomes:' "$PROJECT_ROOT/scripts/lib/testing.sh"; then
    test_pass
else
    test_fail "retry branch is missing terminal outcome reporting"
fi

test_summary
