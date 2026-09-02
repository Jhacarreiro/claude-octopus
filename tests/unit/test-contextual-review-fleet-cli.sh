#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Contextual review fleet CLI"

checker="$TEST_TMP_DIR/provider-checker.sh"
cat > "$checker" <<'CHECKER'
#!/usr/bin/env bash
printf '%s\n' \
  'codex:available' \
  'commandcode:available' \
  'claude:available' \
  'agy:available' \
  'openrouter:available' \
  'orcarouter:available' \
  'vibe:available' \
  'atlascloud:available'
CHECKER
chmod +x "$checker"

run_fleet() {
  env \
    "HOME=$TEST_TMP_DIR/home" \
    "OCTOPUS_PROVIDER_CHECKER=$checker" \
    "OCTO_ALLOWED_PROVIDERS=codex commandcode claude agy openrouter orcarouter vibe atlascloud" \
    "$@" \
    "$PROJECT_ROOT/bin/octopus" fleet review standard target
}

test_case "fleet review shows all eight effective model-qualified seat overrides"
fleet="$(run_fleet \
  OCTOPUS_REVIEW_LOGIC_AGENT='openai:gpt-5.6-luna' \
  OCTOPUS_REVIEW_SECURITY_AGENT='agy:gemini-exact' \
  OCTOPUS_REVIEW_ARCHITECTURE_AGENT='anthropic:claude-opus-5' \
  OCTOPUS_REVIEW_CVE_AGENT='command-code:tencent/hy3-paid' \
  OCTOPUS_REVIEW_DIVERSITY_AGENT='openrouter:deepseek/deepseek-v4' \
  OCTOPUS_REVIEW_VERIFIER_AGENT='orcarouter:anthropic/claude-sonnet-4.6' \
  OCTOPUS_REVIEW_DEBATER_AGENT='vibe:mistral-large-latest' \
  OCTOPUS_REVIEW_SYNTHESIZER_AGENT='atlas-cloud:qwen/qwen3.5')"
expected_specs=$'codex:gpt-5.6-luna\nagy:gemini-exact\nclaude:claude-opus-5\ncommandcode:tencent/hy3-paid\nopenrouter:deepseek/deepseek-v4\norcarouter:anthropic/claude-sonnet-4.6\nvibe:mistral-large-latest\natlascloud-agent:qwen/qwen3.5'
actual_specs="$(printf '%s\n' "$fleet" | cut -d'|' -f1)"
if [[ "$(printf '%s\n' "$fleet" | grep -c .)" -eq 8 && "$actual_specs" == "$expected_specs" ]]; then
  test_pass
else
  test_fail "fleet review did not render all effective overrides: $(tr '\n' ';' <<< "$fleet")"
fi

test_case "single-provider override takes precedence over all seat overrides in fleet review"
fleet="$(run_fleet \
  OCTOPUS_REVIEW_SINGLE_PROVIDER=codex \
  OCTOPUS_REVIEW_LOGIC_AGENT='commandcode:model-a' \
  OCTOPUS_REVIEW_SYNTHESIZER_AGENT='vibe:model-b')"
if [[ "$(printf '%s\n' "$fleet" | grep -c .)" -eq 8 ]] && \
   [[ "$(printf '%s\n' "$fleet" | cut -d'|' -f1 | grep -vc '^codex$' || true)" -eq 0 ]]; then
  test_pass
else
  test_fail "single-provider precedence was not reflected in fleet review: $(tr '\n' ';' <<< "$fleet")"
fi

test_case "fleet review rejects an exact model outside the dispatch allowlist"
restricted_rc=0
restricted_fleet="$(run_fleet \
  OCTOPUS_CODEX_ALLOWED_MODELS='gpt-allowed' \
  OCTOPUS_REVIEW_LOGIC_AGENT='codex:gpt-blocked' 2>/dev/null)" || restricted_rc=$?
if [[ "$restricted_rc" -ne 0 && "$restricted_fleet" != *'codex:gpt-blocked'* ]]; then
  test_pass
else
  test_fail "fleet review called a dispatch-rejected model effective: rc=$restricted_rc fleet=[$restricted_fleet]"
fi

test_case "fleet review rejects an exact Fable security seat"
fable_rc=0
fable_fleet="$(run_fleet \
  OCTOPUS_REVIEW_SECURITY_AGENT='anthropic:claude-fable-5' 2>/dev/null)" || fable_rc=$?
if [[ "$fable_rc" -ne 0 && "$fable_fleet" != *'claude:claude-fable-5'* ]]; then
  test_pass
else
  test_fail "fleet review called an unsafe Fable security seat effective: rc=$fable_rc fleet=[$fable_fleet]"
fi

test_summary
