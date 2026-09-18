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

# Use a configured seat so budget tests do not depend on host routing state.
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
printf '%s\n' '{"routing":{"features":{"summarizer":["agy"]}}}' > "$OCTOPUS_PROVIDERS_CONFIG"

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

test_case "preflight ratio override changes the derived input budget"
if [[ "$(OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_RATIO=150 octo_preflight_context_budget 12000)" == 18000 ]]; then
  test_pass
else
  test_fail "preflight ratio override did not change the derived budget"
fi

test_case "preflight additive override changes the floor and accepts zero"
if [[ "$(OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_ADDITIVE=4096 octo_preflight_context_budget 6278)" == 10374 ]] &&
   [[ "$(OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_ADDITIVE=0 octo_preflight_context_budget 6278)" == 7848 ]]; then
  test_pass
else
  test_fail "preflight additive override did not control the budget floor"
fi

test_case "summary trigger override changes the admission threshold"
if [[ "$(OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO=120 octo_summary_trigger_budget 1000)" == 1200 ]]; then
  test_pass
else
  test_fail "summary trigger override did not change the threshold"
fi

test_case "preflight override cannot exceed the provider input ceiling"
ceiling_prompt=$(printf '%041856d' 0)
if OCTOPUS_PREFLIGHT_CONTEXT_BUDGET=2147483647 OCTOPUS_OVERSIZE_STRATEGY=fail \
     enforce_context_budget "$ceiling_prompt" synthesizer codex preflight >/dev/null 2>&1; then
  ceiling_rc=0
  OCTOPUS_PREFLIGHT_CONTEXT_BUDGET=2147483647 OCTOPUS_OVERSIZE_STRATEGY=fail \
    enforce_context_budget "${ceiling_prompt}x" synthesizer codex preflight >/dev/null 2>&1 || ceiling_rc=$?
  if [[ "$ceiling_rc" == 78 ]]; then
    test_pass
  else
    test_fail "preflight admitted input above the 10464-token provider ceiling"
  fi
else
  test_fail "preflight rejected input at the provider ceiling"
fi

test_case "summary trigger grace cannot admit input above the provider ceiling"
ceiling_summary=$(enforce_context_budget "${ceiling_prompt}x" "" codex tangle)
if [[ "$ceiling_summary" == summary && -e "$summary_probe" ]]; then
  test_pass
else
  test_fail "summary trigger admitted a prompt above the provider ceiling"
fi

test_case "preflight budget saturates maximum-target configuration"
OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_RATIO=2147483647
if [[ "$(octo_preflight_context_budget 2147483647)" == 2147483647 ]]; then
  test_pass
else
  test_fail "preflight ratio did not saturate at the maximum budget"
fi
unset OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_RATIO

test_case "summary trigger saturates maximum-target configuration"
OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO=2147483647
if [[ "$(octo_summary_trigger_budget 2147483647)" == 2147483647 ]]; then
  test_pass
else
  test_fail "summary trigger ratio did not saturate at the maximum budget"
fi
unset OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO

test_case "derived budget helpers reject arithmetic-overflow inputs"
if ! octo_saturating_context_add 2147483648 1 >/dev/null 2>&1 &&
   ! octo_saturating_context_percent 2147483647 2147483648 >/dev/null 2>&1; then
  test_pass
else
  test_fail "derived budget helpers accepted values above the bounded arithmetic range"
fi

test_case "unused summary trigger configuration does not block truncation"
OCTOPUS_CONTEXT_BUDGET=12000
OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO=invalid
OCTOPUS_OVERSIZE_STRATEGY=truncate
if enforce_context_budget "$(printf 'z%.0s' {1..60000})" "researcher" codex tangle >/dev/null 2>&1; then
  test_pass
else
  test_fail "truncate strategy unexpectedly evaluated an unused summary trigger"
fi
unset OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO OCTOPUS_OVERSIZE_STRATEGY

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

test_case "summarizer overrides stay scoped to the candidate dispatch"
OCTOPUS_PREFLIGHT_CONTEXT_BUDGET=4321
OCTOPUS_OVERSIZE_STRATEGY=caller-strategy
OCTOPUS_DEBUG=caller-debug
run_agent_sync() { printf '%s\n' "Condensed prose without the machine contract"; }
if summarize_then_dispatch "$structural_prompt" researcher commandcode 6278 >/dev/null 2>&1; then
  test_fail "invalid summary unexpectedly passed"
elif [[ "${OCTOPUS_PREFLIGHT_CONTEXT_BUDGET:-}" == "4321" &&
        "${OCTOPUS_OVERSIZE_STRATEGY:-}" == "caller-strategy" &&
        "${OCTOPUS_DEBUG:-}" == "caller-debug" ]]; then
  test_pass
else
  test_fail "summarizer overrides leaked after rejected summary"
fi

test_case "fitted summary cannot drop structural clauses after validation"
run_agent_sync() {
  printf '%s' "$(printf 'x%.0s' {1..30000})"
  printf '%s\n' " [CODING] Reads: summary-tail Creates: summary-tail Files: summary-tail Task: summary-tail"
}
if summarize_then_dispatch "$structural_prompt" researcher commandcode 4000 >/dev/null 2>&1; then
  test_fail "summarize_then_dispatch accepted a fitted summary after losing structural clauses"
else
  test_pass
fi

test_case "validated fitted summaries remain inside the target token budget"
bounded_summary="[CODING] Reads: plan.md Creates: tests.kt Files: app.kt Task: preserve this contract $(printf 'x%.0s' {1..30000})"
bounded_result="$(octo_fit_and_validate_summary "$structural_prompt" "$bounded_summary" 4000)"
if [[ "$(octo_estimate_prompt_tokens "$bounded_result")" -le 4000 ]] &&
   [[ "$bounded_result" == *"[CODING]"* ]] &&
   [[ "$bounded_result" == *"Task:"* ]] &&
   [[ "$bounded_result" == *"Files:"* ]]; then
  test_pass
else
  test_fail "validated summary exceeded the target budget or lost required anchors"
fi

test_case "enforcement falls back after rejecting a fitted summary"
OCTOPUS_CONTEXT_BUDGET=4000
OCTOPUS_OVERSIZE_STRATEGY=summarize
run_agent_sync() {
  printf '%s' "$(printf 'x%.0s' {1..30000})"
  printf '%s\n' " [CODING] Reads: summary-tail Creates: summary-tail Files: summary-tail Task: summary-tail"
}
fallback_prompt="$structural_prompt $(printf 'q%.0s' {1..30000})"
fallback=$(enforce_context_budget "$fallback_prompt" "" codex tangle 2>/dev/null)
if [[ "$fallback" != *"summary-tail"* && "$fallback" == *"[CODING]"* ]]; then
  test_pass
else
  test_fail "invalid fitted summary was returned instead of the original-prompt fallback"
fi
unset OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO OCTOPUS_OVERSIZE_STRATEGY

test_summary
