#!/usr/bin/env bash
# Model-, transport-, and encoding-aware context admission contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "context admission"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

test_case "exact Claude SDK Haiku seat cannot exceed its catalog window"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=1000000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=0
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=0
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 200000 ]]; then
  test_pass
else
  test_fail "exact Haiku seat inherited the generic 1M SDK limit"
fi

test_case "output and system-tool reserves reduce available input"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=10000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1000
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=500
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 8500 ]]; then
  test_pass
else
  test_fail "context reserves were not deducted from the smallest ceiling"
fi

test_case "excessive configured override clamps to the model limit"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=999999999
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 198500 ]]; then
  test_pass
else
  test_fail "oversized override escaped the model catalog ceiling"
fi

test_case "CLI-effective transport limit can be stricter than the model"
OCTOPUS_CLAUDE_SDK_EFFECTIVE_CONTEXT_LIMIT=100000
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 98500 ]]; then
  test_pass
else
  test_fail "transport limit did not constrain available input"
fi
unset OCTOPUS_CLAUDE_SDK_EFFECTIVE_CONTEXT_LIMIT

test_case "reserves that consume the whole context fail closed"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=1000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=900
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=100
if get_provider_context_limit 'claude-sdk:claude-haiku-4.5' >/dev/null 2>&1; then
  test_fail "zero available input was admitted"
else
  test_pass
fi

test_case "non-ASCII prompts use a byte-aware token estimate"
OCTOPUS_CONTEXT_BUDGET=12
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=1
OCTOPUS_OVERSIZE_STRATEGY=fail
emoji_prompt='😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀'
set +e
enforce_context_budget "$emoji_prompt" "" codex review >/dev/null 2>&1
emoji_rc=$?
set -e
if [[ "$emoji_rc" -eq 78 ]]; then
  test_pass
else
  test_fail "byte-dense prompt bypassed token admission (rc=$emoji_rc)"
fi


test_case "preflight synthesizer inherits at least the target effective budget"
OCTOPUS_CONTEXT_BUDGET=12000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1024
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=512
OCTOPUS_PREFLIGHT_CONTEXT_BUDGET=8326
OCTOPUS_OVERSIZE_STRATEGY=fail
preflight_prompt=$(printf "p%.0s" {1..28000})
if enforce_context_budget "$preflight_prompt" "synthesizer" codex preflight >/dev/null 2>&1; then
  test_pass
else
  test_fail "preflight still inherited the 25% synthesizer budget"
fi
unset OCTOPUS_PREFLIGHT_CONTEXT_BUDGET

test_case "small target oversize is admitted without destructive summarization"
OCTOPUS_CONTEXT_BUDGET=12000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1024
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=512
OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO=110
OCTOPUS_OVERSIZE_STRATEGY=summarize
summary_probe="$TEST_TMP_DIR/summary-called"
run_agent_sync() { : > "$summary_probe"; printf "summary\n"; }
small_oversize=$(printf "x%.0s" {1..26000})
if enforce_context_budget "$small_oversize" "researcher" codex tangle >/dev/null 2>&1 && [[ ! -e "$summary_probe" ]]; then
  test_pass
else
  test_fail "prompt only slightly above the role budget invoked summarization"
fi

test_case "preflight budget derives from target budget rather than synthesizer quota"
if [[ "$(octo_preflight_context_budget 6278)" == 8326 ]]; then
  test_pass
else
  test_fail "unexpected preflight target budget: $(octo_preflight_context_budget 6278)"
fi

test_case "preflight budget rejects arithmetic-overflowing configuration"
OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_RATIO=2147483647
if octo_preflight_context_budget 2147483647 >/dev/null 2>&1; then
  test_fail "overflowing preflight ratio was accepted"
else
  test_pass
fi
unset OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_RATIO

test_case "summary trigger rejects arithmetic-overflowing configuration"
OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO=2147483647
if octo_summary_trigger_budget 2147483647 >/dev/null 2>&1; then
  test_fail "overflowing summary trigger ratio was accepted"
else
  test_pass
fi
unset OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO

test_case "preflight summary rejects loss of Tangle structural clauses"
validate_agent_type() { return 0; }
run_agent_sync() { printf '%s\n' "Condensed prose without the machine contract"; }
structural_prompt="1. [CODING] Implement — Reads: plan.md — Files: app.kt — Creates: tests.kt — Task: preserve this contract"
if summarize_then_dispatch "$structural_prompt" researcher commandcode 6278 >/dev/null 2>&1; then
  test_fail "summary that dropped Tangle clauses was accepted"
else
  test_pass
fi

test_case "preflight summary receives expanded budget and preserves contract"
run_agent_sync() {
  printf 'BUDGET=%s\n1. [CODING] Implement — Reads: plan.md — Files: app.kt — Creates: tests.kt — Task: preserve this contract\n' "${OCTOPUS_PREFLIGHT_CONTEXT_BUDGET:-missing}"
}
summary=$(summarize_then_dispatch "$structural_prompt" researcher commandcode 6278)
if [[ "$summary" == *"BUDGET=8326"* && "$summary" == *"Task:"* && "$summary" == *"Files:"* ]]; then
  test_pass
else
  test_fail "preflight did not expose target-sized budget or preserve contract"
fi

test_case "fitted summary cannot drop structural clauses after validation"
run_agent_sync() {
  printf '%s' "$(printf 'x%.0s' {1..30000})"
  printf '%s\n' " Task: summary-tail Files: summary-tail"
}
set +e
fitted_summary=$(enforce_context_budget "$structural_prompt $(printf 'q%.0s' {1..30000})" "" codex tangle 2>/dev/null)
fitted_rc=$?
set -e
if [[ "$fitted_rc" -eq 0 && "$fitted_summary" != *"summary-tail"* ]]; then
  test_pass
else
  test_fail "fitted summary retained anchors only before final fitting"
fi
unset OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO OCTOPUS_OVERSIZE_STRATEGY

test_summary
