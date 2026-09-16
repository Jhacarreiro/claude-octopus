#!/usr/bin/env bash
# Tests for prompt-size preflight behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Dispatch oversize preflight"

log() { :; }
octo_notice_warn() { printf '%s\n' "$*" > "$TEST_TMP_DIR/oversize-notice"; }
record_oversize_event() { printf '%s\n' "$*" > "$TEST_TMP_DIR/oversize-event.args"; }
write_agent_status() { :; }
validate_agent_type() { return 0; }

source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

# These cases isolate compression mechanics from the separately tested output
# and system/tool context reserves.
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=0
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=0

long_prompt="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

test_case "truncate strategy includes its marker inside the exact resolved boundary"
OCTOPUS_CONTEXT_BUDGET=40
OCTOPUS_OVERSIZE_STRATEGY=truncate
output="$(enforce_context_budget "$long_prompt" "reviewer" "codex" "review")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
notice="$(cat "$TEST_TMP_DIR/oversize-notice")"
if [[ "${#output}" -eq 64 ]] &&
   [[ "$output" == *"truncated to fit context budget"* ]] &&
   [[ "$event_args" == "codex ${#long_prompt} 64 truncated reviewer review 16" ]] &&
   [[ "$notice" == "Context budget: truncated codex role=reviewer phase=review from ${#long_prompt} to 64 chars (budget=16 tokens/64 chars)" ]]; then
    test_pass
else
    test_fail "boundary/accounting mismatch: output_chars=${#output} event='$event_args'"
fi

test_case "fail strategy returns context-budget status"
set +e
OCTOPUS_CONTEXT_BUDGET=40
OCTOPUS_OVERSIZE_STRATEGY=fail
enforce_context_budget "$long_prompt" "reviewer" "codex" "review" >"$TEST_TMP_DIR/oversize-fail.out"
rc=$?
set -e
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ $rc -eq 78 ]] &&
   [[ "$event_args" == "codex ${#long_prompt} ${#long_prompt} failed reviewer review 16" ]]; then
    test_pass
else
    test_fail "expected attributed exit 78, got rc=$rc event='$event_args'"
fi

test_case "summarize strategy dispatches through configured summarizer"
SUMMARIZER_CFG="$TEST_TMP_DIR/providers-summarizer.json"
printf '%s\n' '{"routing":{"features":{"summarizer":["commandcode"]}}}' > "$SUMMARIZER_CFG"
export OCTOPUS_PROVIDERS_CONFIG="$SUMMARIZER_CFG"
octo_fallback_canonical_agent_spec() { printf '%s\n' "$1"; }
octo_fallback_admit_automatic_spec() { return 0; }
run_agent_sync() {
    echo "condensed prompt"
}
OCTOPUS_CONTEXT_BUDGET=40
OCTOPUS_OVERSIZE_STRATEGY=summarize
output="$(enforce_context_budget "$long_prompt" "reviewer" "codex" "review")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
notice="$(cat "$TEST_TMP_DIR/oversize-notice")"
if [[ "$output" == "condensed prompt" ]] &&
   [[ "$event_args" == "codex ${#long_prompt} 16 summarized reviewer review 16" ]] &&
   [[ "$notice" == "Context budget: summarized codex role=reviewer phase=review from ${#long_prompt} to 16 chars (budget=16 tokens/64 chars)" ]]; then
    test_pass
else
    test_fail "expected attributed summarized prompt, got output='$output' event='$event_args'"
fi
unset OCTOPUS_PROVIDERS_CONFIG



test_case "summarize strategy preserves original task verbatim outside auxiliary summary"
run_agent_sync() {
    echo "condensed auxiliary context"
}
protected_task=$'CAPACITY_AUTH_SECURE_PAIRING_TASK_SENTINEL
Objective: preserve this exact task.
Stop condition: do not invent scope.'
protected_prompt="$(printf 'A%.0s' {1..360})${protected_task}$(printf 'B%.0s' {1..120})"
OCTOPUS_CONTEXT_BUDGET=80
OCTOPUS_OVERSIZE_STRATEGY=summarize
output="$(enforce_context_budget "$protected_prompt" "" "codex" "review" "$protected_task")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ "$output" == *"condensed auxiliary context"* ]] &&
   [[ "$output" == *"## ORIGINAL TASK - DO NOT SUMMARIZE"* ]] &&
   [[ "$output" == *"$protected_task"* ]] &&
   [[ "$(octo_estimate_prompt_tokens "$output")" -le 80 ]] &&
   [[ "$event_args" == *"summarized-protected-task"* ]]; then
    test_pass
else
    test_fail "protected task was not preserved by summarize path: event='$event_args' output='$output'"
fi

test_case "summarizer failure truncates only auxiliary context and preserves original task"
run_agent_sync() { return 1; }
OCTOPUS_CONTEXT_BUDGET=80
OCTOPUS_OVERSIZE_STRATEGY=summarize
output="$(enforce_context_budget "$protected_prompt" "" "codex" "review" "$protected_task")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ "$output" == *"## ORIGINAL TASK - DO NOT SUMMARIZE"* ]] &&
   [[ "$output" == *"$protected_task"* ]] &&
   [[ "$(octo_estimate_prompt_tokens "$output")" -le 80 ]] &&
   [[ "$event_args" == *"summarized-protected-task"* ]]; then
    test_pass
else
    test_fail "fallback truncation lost protected task: event='$event_args' output='$output'"
fi

test_case "protected task may exceed soft role budget when it fits provider hard context"
_original_get_provider_context_limit="$(declare -f get_provider_context_limit)"
_original_get_role_budget_proportion="$(declare -f get_role_budget_proportion)"
get_provider_context_limit() { echo 120; }
get_role_budget_proportion() { echo 40; }
soft_task="$(printf 'CAPACITY-TASK-%.0s' {1..18})"
soft_prompt="$(printf 'AUXILIARY-%.0s' {1..120})${soft_task}"
OCTOPUS_CONTEXT_BUDGET=""
OCTOPUS_OVERSIZE_STRATEGY=summarize
output="$(enforce_context_budget "$soft_prompt" "researcher" "codex" "review" "$soft_task")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
eval "$_original_get_provider_context_limit"
eval "$_original_get_role_budget_proportion"
unset _original_get_provider_context_limit _original_get_role_budget_proportion
if [[ "$output" == *"## ORIGINAL TASK - DO NOT SUMMARIZE"* ]] &&
   [[ "$output" == *"$soft_task"* ]] &&
   [[ "$output" != *"AUXILIARY-"* ]] &&
   [[ "$(octo_estimate_prompt_tokens "$output")" -le 120 ]] &&
   [[ "$event_args" == *"protected-task-soft-budget-bypass"* ]]; then
    test_pass
else
    test_fail "soft role budget did not yield auxiliary context while preserving task: event='$event_args' output='$output'"
fi

test_case "protected task larger than budget fails explicitly instead of silently truncating task"
very_large_task="$(printf 'TASK-SENTINEL-%.0s' {1..80})"
very_large_prompt="prefix ${very_large_task} suffix"
OCTOPUS_CONTEXT_BUDGET=30
OCTOPUS_OVERSIZE_STRATEGY=truncate
set +e
enforce_context_budget "$very_large_prompt" "" "codex" "review" "$very_large_task" >"$TEST_TMP_DIR/protected-too-large.out" 2>"$TEST_TMP_DIR/protected-too-large.err"
protected_rc=$?
set -e
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ "$protected_rc" -eq 78 ]] && [[ ! -s "$TEST_TMP_DIR/protected-too-large.out" ]] &&
   [[ "$event_args" == *"protected-task-too-large"* ]]; then
    test_pass
else
    test_fail "oversized protected task did not fail closed: rc=$protected_rc event='$event_args'"
fi

test_case "leading-zero context budget is normalized as decimal before arithmetic"
decimal_prompt="$(printf '%04000d' 0)"
OCTOPUS_CONTEXT_BUDGET=0900
OCTOPUS_OVERSIZE_STRATEGY=truncate
set +e
output="$(enforce_context_budget "$decimal_prompt" "reviewer" "codex" "review" \
    2>"$TEST_TMP_DIR/decimal-budget.err")"
decimal_rc=$?
set -e
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ "$decimal_rc" -eq 0 ]] && [[ "${#output}" -eq 1440 ]] &&
   [[ "$event_args" == "codex 4000 1440 truncated reviewer review 360" ]]; then
    test_pass
else
    test_fail "0900 was not normalized safely: rc=$decimal_rc output_chars=${#output} event='$event_args' error='$(cat "$TEST_TMP_DIR/decimal-budget.err")'"
fi

test_case "invalid and overflowing context budgets fail before compression"
invalid_budget_ok=true
invalid_budget_failures=""
for invalid_budget in 0 -1 18446744073709551616 9223372036854775807; do
    rm -f "$TEST_TMP_DIR/oversize-event.args" "$TEST_TMP_DIR/oversize-notice"
    set +e
    OCTOPUS_CONTEXT_BUDGET="$invalid_budget" OCTOPUS_OVERSIZE_STRATEGY=truncate \
        enforce_context_budget "$long_prompt" "reviewer" "codex" "review" \
        >"$TEST_TMP_DIR/invalid-budget.out" 2>"$TEST_TMP_DIR/invalid-budget.err"
    rc=$?
    set -e
    invalid_output="$(cat "$TEST_TMP_DIR/invalid-budget.out")"
    if [[ "$rc" -ne 2 ]] || [[ -s "$TEST_TMP_DIR/invalid-budget.out" ]] ||
       [[ -e "$TEST_TMP_DIR/oversize-event.args" ]] || [[ -e "$TEST_TMP_DIR/oversize-notice" ]]; then
        invalid_budget_ok=false
        invalid_budget_failures="${invalid_budget_failures}${invalid_budget}:rc=${rc}:chars=${#invalid_output};"
    fi
done
if [[ "$invalid_budget_ok" == true ]]; then
    test_pass
else
    test_fail "invalid budgets reached prompt processing: $invalid_budget_failures"
fi

test_summary
