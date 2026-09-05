#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
log() { :; }

test_suite "tangle execution boundary"

BOUNDARY_ROOT="$TEST_TMP_DIR/tangle-boundary"
BOUNDARY_WORKTREE="$BOUNDARY_ROOT/worktree"
BOUNDARY_RESULTS="$BOUNDARY_ROOT/results"
BOUNDARY_OUTSIDE="$BOUNDARY_ROOT/outside.txt"
mkdir -p "$BOUNDARY_WORKTREE" "$BOUNDARY_RESULTS"

phase="tangle"
role="implementer"
OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true
OCTOPUS_TANGLE_WORKTREE="$BOUNDARY_WORKTREE"
OCTOPUS_TANGLE_RESULTS_DIR="$BOUNDARY_RESULTS"
export OCTOPUS_TANGLE_EXECUTION_BOUNDARY OCTOPUS_TANGLE_WORKTREE OCTOPUS_TANGLE_RESULTS_DIR

test_case "coding dispatch has no unconfined fallback"
cmd_array=(bash -c ':')
if octopus_tangle_execution_boundary_probe; then
    test_pass
else
    if octopus_tangle_apply_execution_boundary; then
        test_fail "boundary wrapper accepted a host without an enforceable sandbox"
    else
        test_pass
    fi
fi

test_case "parent-owned result channel cannot overlap the worktree"
if ! octopus_tangle_boundary_paths_are_disjoint \
    "$BOUNDARY_WORKTREE" "$BOUNDARY_WORKTREE/results" && \
   ! octopus_tangle_boundary_paths_are_disjoint \
    "$BOUNDARY_WORKTREE" "$BOUNDARY_ROOT" && \
   octopus_tangle_boundary_paths_are_disjoint \
    "$BOUNDARY_WORKTREE" "$BOUNDARY_RESULTS"; then
    test_pass
else
    test_fail "overlapping worktree/result authority paths were accepted"
fi

if octopus_tangle_execution_boundary_probe; then
    test_case "boundary leaves only the worktree writable"
    cmd_array=(bash -c 'touch "$1" 2>/dev/null || true; touch "$2/inside.txt"; touch "$3/forged.txt" 2>/dev/null || true' _ "$BOUNDARY_OUTSIDE" "$BOUNDARY_WORKTREE" "$BOUNDARY_RESULTS")
    if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" &&
       [[ ! -e "$BOUNDARY_OUTSIDE" ]] &&
       [[ -e "$BOUNDARY_WORKTREE/inside.txt" ]] &&
       [[ ! -e "$BOUNDARY_RESULTS/forged.txt" ]]; then
        test_pass
    else
        test_fail "provider could write outside the worktree or forge the result channel"
    fi
fi

test_summary
