#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle decomposition adequacy"
export OCTOPUS_TANGLE_CODE_REVIEW=false
source "$WORKFLOWS"

CYAN=""; GREEN=""; MAGENTA=""; NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$(mktemp -d)"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
mkdir -p "$WORKSPACE_DIR/.octo/agents"
trap 'rm -rf "$RESULTS_DIR"' EXIT

SCENARIO_FILE="$RESULTS_DIR/scenario"
ADEQUACY_COUNT_FILE="$RESULTS_DIR/adequacy-count"
REDECOMPOSE_COUNT_FILE="$RESULTS_DIR/redecompose-count"
SPAWN_FILE="$RESULTS_DIR/spawns"
DECOMPOSE_PROMPT_FILE="$RESULTS_DIR/decompose-prompt"
REDECOMPOSE_PROMPT_FILE="$RESULTS_DIR/redecompose-prompt"
LOG_FILE="$RESULTS_DIR/tangle.log"

log() { printf '%s %s\n' "${1:-}" "${2:-}" >> "$LOG_FILE"; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
design_review_ceremony() {
    local out_var="${3:-}"
    if [[ -n "$out_var" ]]; then
        printf -v "$out_var" '%s' 'DESIGN_RESOLUTION_MARKER: create the externally observable deliverable, preserving reversible boundaries.'
    fi
}
validate_tangle_results() { return 0; }
tangle_contextual_review_gate() { return 0; }

counter_next() {
    local file="$1" n=0
    [[ -f "$file" ]] && n=$(cat "$file")
    n=$((n + 1))
    printf '%s' "$n" > "$file"
    printf '%s\n' "$n"
}

run_agent_sync() {
    local supervised="${OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED:-}"
    local prompt="$2"
    local scenario
    scenario=$(cat "$SCENARIO_FILE")
    case "$supervised" in
        tangle-dispatch-watcher)
            printf '%s' "$prompt" > "$DECOMPOSE_PROMPT_FILE"
            if [[ "$scenario" == "no-parseable" ]]; then
                printf '%s\n' "I'll explore the repository structure first."
            else
                printf '%s\n' '1. [CODING] Build requested application — Files: scripts/lib/workflows.sh — Task: Build the requested externally observable application.'
            fi
            ;;
        tangle-redecompose-validation)
            counter_next "$REDECOMPOSE_COUNT_FILE" >/dev/null
            printf '%s' "$prompt" > "$REDECOMPOSE_PROMPT_FILE"
            printf '%s\n' '1. [CODING] Create requested application — Creates: web/package.json, web/src/main.tsx — Task: Materialize the requested externally observable application.'
            ;;
        tangle-decomposition-adequacy)
            local n
            n=$(counter_next "$ADEQUACY_COUNT_FILE")
            case "$scenario" in
                second-fail)
                    printf '%s\n' 'VERDICT: FAIL' 'REASONS: scopes still cannot materialize the requested deliverable'
                    ;;
                adequacy-repair)
                    if [[ "$n" -eq 1 ]]; then
                        printf '%s\n' 'VERDICT: FAIL' 'REASONS: task promises an application but Files only permits an unrelated existing workflow file'
                    else
                        printf '%s\n' 'VERDICT: PASS' 'REASONS: Creates explicitly permits the missing application artifacts'
                    fi
                    ;;
                *)
                    printf '%s\n' 'VERDICT: PASS' 'REASONS: decomposition is adequate'
                    ;;
            esac
            ;;
        *)
            printf '%s\n' 'unexpected run_agent_sync call' >&2
            return 1
            ;;
    esac
}

spawn_agent_capture_pid() {
    local task_id="$3"
    printf '%s\n' "$task_id" >> "$SPAWN_FILE"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    printf '%s\n' "$$"
}

reset_scenario() {
    printf '%s' "$1" > "$SCENARIO_FILE"
    printf '0' > "$ADEQUACY_COUNT_FILE"
    printf '0' > "$REDECOMPOSE_COUNT_FILE"
    : > "$SPAWN_FILE"
    : > "$DECOMPOSE_PROMPT_FILE"
    : > "$REDECOMPOSE_PROMPT_FILE"
    : > "$LOG_FILE"
}

run_case() {
    local scenario="$1"
    reset_scenario "$scenario"
    tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/${scenario}.out" 2>&1
}

test_case "adequacy verdict parser accepts only explicit PASS"
if tangle_decomposition_adequacy_verdict $'VERDICT: PASS\nREASONS: ok' && ! tangle_decomposition_adequacy_verdict $'VERDICT: FAIL\nREASONS: no' && ! tangle_decomposition_adequacy_verdict 'looks good'; then
    test_pass
else
    test_fail "adequacy verdict parser did not fail closed"
fi

test_case "adequacy reasons parser preserves multiline reviewer guidance"
multiline=$'VERDICT: FAIL\n\nREASONS:\n- missing requested artifact\n- scope cannot contain deliverable'
reasons=$(tangle_decomposition_adequacy_reasons "$multiline")
if [[ "$reasons" == *"missing requested artifact"* ]] && [[ "$reasons" == *"scope cannot contain deliverable"* ]]; then
    test_pass
else
    test_fail "multiline adequacy reasons were lost: $reasons"
fi

test_case "initial decomposer receives design-review synthesis"
reset_scenario "adequacy-repair"
run_case "adequacy-repair"
if grep -q 'DESIGN_RESOLUTION_MARKER' "$DECOMPOSE_PROMPT_FILE"; then
    test_pass
else
    test_fail "design-review synthesis was not present in decomposition prompt"
fi

test_case "non-decomposition output triggers redecompose rather than repair"
run_case "no-parseable"
if [[ "$(cat "$REDECOMPOSE_COUNT_FILE")" -eq 1 ]] && grep -q "Previous non-usable output:" "$REDECOMPOSE_PROMPT_FILE" && ! grep -q "Reformatted subtasks:" "$RESULTS_DIR/no-parseable.out"; then
    test_pass
else
    test_fail "unparseable output was not routed through first-principles redecomposition"
fi

test_case "semantic FAIL triggers exactly one redecomposition and then spawns"
run_case "adequacy-repair"
if [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$REDECOMPOSE_COUNT_FILE")" -eq 1 ]] && [[ -s "$SPAWN_FILE" ]] && grep -q 'semantic adequacy:' "$REDECOMPOSE_PROMPT_FILE"; then
    test_pass
else
    test_fail "adequacy FAIL did not perform one bounded redecomposition before spawn"
fi

test_case "second semantic FAIL aborts before implementation spawn"
reset_scenario "second-fail"
status=0
tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/second-fail.out" 2>&1 || status=$?
if [[ "$status" -ne 0 ]] && [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$REDECOMPOSE_COUNT_FILE")" -eq 1 ]] && [[ ! -s "$SPAWN_FILE" ]] && grep -q 'remains semantically inadequate' "$LOG_FILE"; then
    test_pass
else
    test_fail "second adequacy FAIL did not fail closed before spawn"
fi

test_summary
