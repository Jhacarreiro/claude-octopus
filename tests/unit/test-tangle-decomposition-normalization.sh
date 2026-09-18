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

test_case "normalizer derives task prose without acceptance boilerplate"
if [[ "$normalized" == *"Task: Implement and verify:"* && "$normalized" == *"Replace anonymous startup"* && "$normalized" != *"Acceptance evidence"* ]]; then test_pass; else test_fail "task prose normalization is wrong"; fi

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

test_case "already-valid wire format remains unchanged"
wire='1. [CODING] Edit — Files: src/app.ts — Task: implement it'
if [[ "$(tangle_materialize_decomposition_output "$wire")" == "$wire" ]]; then test_pass; else test_fail "wire format was rewritten"; fi

test_summary
