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
if [[ "$(review_agent_for_seat codex implementation-logic-reviewer)" == "$OCTOPUS_REVIEW_LOGIC_AGENT" ]] && \
   [[ "$(review_agent_for_seat claude-sonnet implementation-security-reviewer)" == "$OCTOPUS_REVIEW_SECURITY_AGENT" ]] && \
   [[ "$(review_agent_for_seat claude-sonnet implementation-architecture-reviewer)" == "$OCTOPUS_REVIEW_ARCHITECTURE_AGENT" ]] && \
   [[ "$(review_agent_for_seat codex implementation-verifier)" == "$OCTOPUS_REVIEW_VERIFIER_AGENT" ]] && \
   [[ "$(review_agent_for_seat codex implementation-debater)" == "$OCTOPUS_REVIEW_DEBATER_AGENT" ]] && \
   [[ "$(review_agent_for_seat claude-sonnet implementation-synthesizer)" == "$OCTOPUS_REVIEW_SYNTHESIZER_AGENT" ]]; then
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

test_case "Round 1 override seats are emitted exactly once with configured providers"
fleet=$'codex:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions\nclaude-sonnet:implementation-architecture-reviewer:architecture, integration, API contracts, breaking changes\n'
expanded="$(review_fleet_with_override_seats "$fleet")"
logic_provider="${OCTOPUS_REVIEW_LOGIC_AGENT%%:*}"
security_provider="${OCTOPUS_REVIEW_SECURITY_AGENT%%:*}"
cve_provider="${OCTOPUS_REVIEW_CVE_AGENT%%:*}"
diversity_provider="${OCTOPUS_REVIEW_DIVERSITY_AGENT%%:*}"
if [[ "$(grep -Fc ':implementation-logic-reviewer:' <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc ':implementation-architecture-reviewer:' <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc ':implementation-security-reviewer:' <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc ':implementation-cve-reviewer:' <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc ':implementation-diversity-reviewer:' <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc "${logic_provider}:implementation-logic-reviewer:" <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc "${security_provider}:implementation-security-reviewer:" <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc "${cve_provider}:implementation-cve-reviewer:" <<< "$expanded")" -eq 1 ]] && \
   [[ "$(grep -Fc "${diversity_provider}:implementation-diversity-reviewer:" <<< "$expanded")" -eq 1 ]]; then
  test_pass
else
  test_fail "Round 1 generated fleet did not preserve unique configured-provider seats: $(tr '\n' '|' <<< "$expanded")"
fi

test_case "unconfigured roles preserve upstream default executor"
unset OCTOPUS_REVIEW_LOGIC_AGENT
if [[ "$(review_agent_for_seat codex implementation-logic-reviewer)" == 'codex' ]]; then
  test_pass
else
  test_fail "unconfigured seat changed upstream default"
fi

test_case "model-qualified CommandCode seats retain provider telemetry identity"
if [[ "$(review_provider_key_from_agent_type "$OCTOPUS_REVIEW_DIVERSITY_AGENT")" == 'commandcode' ]]; then
  test_pass
else
  test_fail "CommandCode review seat was not classified as commandcode"
fi

test_summary
