#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$ROOT/scripts/lib/workflows.sh"
log() { :; }
test_suite "tangle deterministic decomposition normalization"
fixture="$ROOT/tests/fixtures/tangle-markdown-decomposition.md"
raw="$(cat "$fixture")"

test_case "wire parser rejects rich markdown directly"
if tangle_decomposition_wire_output_usable "$raw"; then test_fail "rich markdown unexpectedly matched wire format"; else test_pass; fi

test_case "semantic validator accepts deterministically normalizable markdown"
if tangle_decomposition_output_usable "$raw"; then test_pass; else test_fail "normalizable markdown was rejected"; fi

test_case "normalizer emits one parseable line per subtask"
normalized="$(tangle_materialize_decomposition_output "$raw")"
if [[ "$(tangle_parseable_subtask_count "$normalized")" == 3 && "$(tangle_parseable_coding_subtask_count "$normalized")" == 2 ]]; then test_pass; else test_fail "unexpected normalized counts"; fi

test_case "normalizer preserves read, write and create scopes"
if [[ "$normalized" == *"Reads: /context/approved-plan.md"* && "$normalized" == *"Files: app/build.gradle.kts, app/src/main/App.kt"* && "$normalized" == *"Creates: app/src/main/AuthScreen.kt"* ]]; then test_pass; else test_fail "scope clauses were not preserved"; fi

test_case "normalizer preserves bare root-level scopes"
root_scope=$'### 1. [CODING] Root-level maintenance\n\n**Files:**\n- Makefile\n- scripts\n\nTask: Update the root-level build and scripts.'
root_normalized="$(tangle_materialize_decomposition_output "$root_scope")"
if [[ "$root_normalized" == *"Files: Makefile, scripts"* ]]; then test_pass; else test_fail "bare root-level scopes were dropped: $root_normalized"; fi

test_case "normalizer derives task prose without acceptance boilerplate"
if [[ "$normalized" == *"Task: Implement and verify:"* && "$normalized" == *"Replace anonymous startup"* && "$normalized" != *"Acceptance evidence"* ]]; then test_pass; else test_fail "task prose normalization is wrong"; fi

test_case "normalizer protects title and task separators"
separator_input=$'### 1. [CODING] Preserve parser - error details\n\nFiles: scripts\n\nTask: Keep em dash — and hyphen - text intact.'
separator_normalized="$(tangle_materialize_decomposition_output "$separator_input")"
separator_task="$(tangle_extract_structured_clause "$separator_normalized" Task || true)"
if [[ "$separator_normalized" == *"Preserve parser | error details"* && "$separator_task" == *"Keep em dash | and hyphen | text intact."* ]]; then test_pass; else test_fail "wire separators truncated normalized prose: $separator_normalized"; fi

test_case "coding markdown without write scope fails closed"
bad=$'### 1. [CODING] Missing scope\n\nImplement the feature.'
if tangle_decomposition_output_usable "$bad"; then test_fail "coding task without write authority was accepted"; else test_pass; fi

test_case "reasoning-only markdown remains unusable for implementation decomposition"
reason=$'### 1. [REASONING] Inspect\n\nTask: inspect only.'
if tangle_decomposition_output_usable "$reason"; then test_fail "reasoning-only decomposition was accepted"; else test_pass; fi

test_case "fallback chain stops at first provider when local normalization succeeds"
marker="$TEST_TMP_DIR/second-provider-called"
is_agent_available_v2() { return 0; }
octopus_explicit_provider_override() { return 0; }
octo_fallback_canonical_agent_spec() { printf '%s\n' "$1"; }
run_agent_sync_fallback_chain() {
  local validator="${6:-}"
  if "$validator" "$raw"; then
    printf '%s\n' "$raw"
    return 0
  fi
  : > "$marker"
  return 1
}
out="$(tangle_run_decomposition_fallbacks primary fallback prompt 0)"
if [[ ! -e "$marker" ]] && tangle_decomposition_wire_output_usable "$out"; then test_pass; else test_fail "local repair did not prevent provider fallback"; fi

test_case "fallback chain returns its failure status"
run_agent_sync_fallback_chain() {
  return 37
}
if tangle_run_decomposition_fallbacks primary fallback prompt 0; then
  test_fail "fallback helper masked fallback-chain failure"
else
  fallback_rc=$?
  if [[ "$fallback_rc" == 37 ]]; then test_pass; else test_fail "unexpected fallback status: $fallback_rc"; fi
fi

test_case "legacy fallback materializes output and retries after normalization failure"
unset -f is_agent_available_v2 2>/dev/null || true
run_agent_sync() {
  if [[ "$1" == "primary" ]]; then
    printf '%s\n' 'provider returned prose without subtasks'
  else
    printf '%s\n' "$raw"
  fi
}
legacy_out="$(tangle_run_decomposition_fallbacks primary fallback prompt 0)"
if tangle_decomposition_wire_output_usable "$legacy_out"; then test_pass; else test_fail "legacy fallback did not materialize and retry: output=$legacy_out"; fi

test_case "redecomposition materializes accepted structured Markdown before returning"
is_agent_available_v2() { return 0; }
run_agent_sync_fallback_chain() {
  printf '%s\n' "$raw"
  return 0
}
redecomposed_out="$(tangle_redecompose original-task previous-output validation-reason)"
if tangle_decomposition_wire_output_usable "$redecomposed_out" && \
   [[ "$redecomposed_out" == *"Files: app/build.gradle.kts, app/src/main/App.kt"* ]]; then
  test_pass
else
  test_fail "redecomposition returned unmaterialized output: $redecomposed_out"
fi

test_case "redecomposition returns fallback-chain failure status"
run_agent_sync_fallback_chain() {
  return 37
}
if tangle_redecompose original-task previous-output validation-reason; then
  test_fail "redecomposition masked fallback-chain failure"
else
  redecompose_rc=$?
  if [[ "$redecompose_rc" == 37 ]]; then test_pass; else test_fail "unexpected redecomposition status: $redecompose_rc"; fi
fi

test_case "already-valid wire format remains unchanged"
wire='1. [CODING] Edit — Files: src/app.ts — Task: implement it'
if [[ "$(tangle_materialize_decomposition_output "$wire")" == "$wire" ]]; then test_pass; else test_fail "wire format was rewritten"; fi

test_summary
