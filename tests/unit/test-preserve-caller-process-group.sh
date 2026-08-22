#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite "Caller process-group preservation"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"

test_case "run_with_timeout preserves caller process group when requested"
if command -v timeout >/dev/null 2>&1; then
    parent_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
    child_pgid="$(OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true run_with_timeout 5 sh -c 'ps -o pgid= -p $$ | tr -d " "')"
    if [[ "$child_pgid" == "$parent_pgid" ]]; then
        test_pass
    else
        test_fail "expected child PGID $parent_pgid, got $child_pgid"
    fi
else
    test_skip "GNU timeout not available on this platform"
fi

test_case "heartbeat uses --foreground only for opt-in process-group preservation"
if grep -q 'OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP' "$PROJECT_ROOT/scripts/lib/heartbeat.sh" \
   && grep -q 'timeout --foreground -k 10' "$PROJECT_ROOT/scripts/lib/heartbeat.sh"; then
    test_pass
else
    test_fail "missing opt-in --foreground timeout path"
fi

test_summary
