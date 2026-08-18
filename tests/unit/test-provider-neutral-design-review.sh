#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider-neutral design review ceremony"

TMP_HOME="$TEST_TMP_DIR/provider-neutral-design-review"
CHECKER="$TMP_HOME/check-providers.sh"
mkdir -p "$TMP_HOME/.claude-octopus/config"
cat >"$CHECKER" <<'EOF'
#!/bin/sh
cat <<'STATUS'
PROVIDER_CHECK_START
codex:available
commandcode:available
agy:missing
perplexity:missing
openrouter:missing
PROVIDER_CHECK_END
STATUS
EOF
chmod +x "$CHECKER"
cat >"$TMP_HOME/.claude-octopus/config/providers.json" <<'EOF'
{
  "version":"3.0",
  "providers": {
    "codex": {"default":"gpt-5.6-sol"},
    "commandcode": {
      "default":"deepseek/deepseek-v4-flash",
      "roles": {
        "researcher":"minimaxai/minimax-m3",
        "code-reviewer":"minimaxai/minimax-m3",
        "synthesizer":"minimaxai/minimax-m3"
      }
    },
    "claude": {"default":"claude-sonnet-5"}
  },
  "routing":{"phases":{},"roles":{}},
  "tiers":{},
  "overrides":{}
}
EOF

export HOME="$TMP_HOME"
export OCTOPUS_PROVIDER_CHECKER="$CHECKER"
export OCTOPUS_ALLOWED_PROVIDERS="codex commandcode claude"
export PLUGIN_DIR="$PROJECT_ROOT"
export WORKSPACE_DIR="$TMP_HOME/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/quality.sh"

test_case "design review preserves role-specific provider policy"
CAPTURE="$TMP_HOME/design-review.calls"
: > "$CAPTURE"
DRY_RUN=false
OCTOPUS_CEREMONIES=true
CYAN="" GREEN="" NC="" _BOX_TOP="" _BOX_BOT=""
log() { :; }
octo_provider_identity_label() { printf '%s / fixture\n' "$1"; }
write_structured_decision() { :; }
run_agent_sync_consultative() {
  printf '%s|%s|%s\n' "$1" "$4" "$5" >> "$CAPTURE"
  printf '%s\n' 'planning output'
}
design_review_ceremony "test" >/dev/null
expected="$(printf '%s\n' \
  'commandcode|implementer|ceremony' \
  'commandcode|researcher|ceremony' \
  'claude-sonnet|code-reviewer|ceremony' \
  'claude-opus|synthesizer|ceremony')"
actual="$(cat "$CAPTURE")"
if [[ "$actual" == "$expected" ]]; then
  test_pass
else
  test_fail "unexpected design-review provider/role mapping: $actual"
fi

test_case "provider-local model keeps provider identity separate from role model"
log() { :; }
export OCTOPUS_PLATFORM=Linux
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
implementer_model="$(resolve_octopus_model commandcode commandcode ceremony implementer)"
researcher_model="$(resolve_octopus_model commandcode commandcode ceremony researcher)"
if [[ "$implementer_model" != "deepseek/deepseek-v4-flash" ]]; then
  test_fail "expected DeepSeek implementer model, got '$implementer_model'"
elif [[ "$researcher_model" != "minimaxai/minimax-m3" ]]; then
  test_fail "expected provider-local MiniMax researcher model, got '$researcher_model'"
else
  test_pass
fi

test_summary
