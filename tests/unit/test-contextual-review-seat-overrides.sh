#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Contextual review seat overrides"

export PLUGIN_DIR="$PROJECT_ROOT"
export HOME="$TEST_TMP_DIR/contextual-review-seat-overrides"
mkdir -p "$HOME/.claude-octopus/config"
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/review.sh"

log() { :; }
octo_provider_allowed() {
  case "$(octo_agent_spec_provider "$1")" in
    codex|claude|commandcode) return 0 ;;
    *) return 1 ;;
  esac
}

unset OCTOPUS_REVIEW_SINGLE_PROVIDER
export OCTOPUS_REVIEW_LOGIC_AGENT='codex:gpt-5.6-luna'
export OCTOPUS_REVIEW_SECURITY_AGENT='claude:claude-opus-5'
export OCTOPUS_REVIEW_ARCHITECTURE_AGENT='claude:claude-opus-5'
export OCTOPUS_REVIEW_CVE_AGENT='commandcode:tencent/hy3-paid'
export OCTOPUS_REVIEW_DIVERSITY_AGENT='commandcode:qwen/qwen3.8-27b'
export OCTOPUS_REVIEW_VERIFIER_AGENT='codex:gpt-5.6-luna'
export OCTOPUS_REVIEW_DEBATER_AGENT='commandcode:qwen/qwen3.8-27b'
export OCTOPUS_REVIEW_SYNTHESIZER_AGENT='commandcode:thinkingmachines/inkling-small'

test_case "semantic seats return literal provider:model overrides"
if [[ "$(review_agent_for_seat codex implementation-verifier)" == 'codex:gpt-5.6-luna' ]] && \
   [[ "$(review_agent_for_seat codex implementation-debater)" == 'commandcode:qwen/qwen3.8-27b' ]] && \
   [[ "$(review_agent_for_seat claude-sonnet implementation-synthesizer)" == 'commandcode:thinkingmachines/inkling-small' ]]; then
  test_pass
else
  test_fail "semantic seat override mismatch"
fi

test_case "single-provider override keeps global precedence"
OCTOPUS_REVIEW_SINGLE_PROVIDER=codex
if [[ "$(review_agent_for_seat claude-sonnet implementation-synthesizer)" == 'codex' ]]; then
  test_pass
else
  test_fail "single-provider override did not take precedence"
fi
unset OCTOPUS_REVIEW_SINGLE_PROVIDER

test_case "disallowed seat override fails closed"
OCTOPUS_REVIEW_SECURITY_AGENT='agy:gemini-3.1-pro'
rc=0
review_agent_for_seat claude-sonnet implementation-security-reviewer >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  test_pass
else
  test_fail "disallowed seat override was accepted"
fi
OCTOPUS_REVIEW_SECURITY_AGENT='claude:claude-opus-5'

test_case "Round 1 override seats are appended when config fleet lacks their roles"
fleet=$'codex:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions\nclaude-sonnet:implementation-architecture-reviewer:architecture, integration, API contracts, breaking changes\n'
expanded="$(review_fleet_with_override_seats "$fleet")"
if grep -Fq ':implementation-security-reviewer:' <<< "$expanded" && \
   grep -Fq ':implementation-cve-reviewer:' <<< "$expanded" && \
   grep -Fq ':implementation-diversity-reviewer:' <<< "$expanded"; then
  test_pass
else
  test_fail "explicit Round 1 seats were not appended: $(tr '\n' '|' <<< "$expanded")"
fi

test_case "Round 1 dispatch replaces executor placeholder with literal seat identity"
if [[ "$(review_agent_for_seat commandcode implementation-cve-reviewer)" == 'commandcode:tencent/hy3-paid' ]] && \
   [[ "$(review_agent_for_seat commandcode implementation-diversity-reviewer)" == 'commandcode:qwen/qwen3.8-27b' ]]; then
  test_pass
else
  test_fail "Round 1 literal seat identities were not preserved"
fi

test_case "unconfigured roles preserve upstream default executor"
unset OCTOPUS_REVIEW_LOGIC_AGENT
if [[ "$(review_agent_for_seat codex implementation-logic-reviewer)" == 'codex' ]]; then
  test_pass
else
  test_fail "unconfigured seat changed upstream default"
fi

test_case "model-qualified CommandCode seats retain provider telemetry identity"
if [[ "$(review_provider_key_from_agent_type 'commandcode:qwen/qwen3.8-27b')" == 'commandcode' ]]; then
  test_pass
else
  test_fail "CommandCode review seat was not classified as commandcode"
fi

test_summary
