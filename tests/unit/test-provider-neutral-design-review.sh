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
export OCTO_ALLOWED_PROVIDERS="codex commandcode claude"
export PLUGIN_DIR="$PROJECT_ROOT"
export WORKSPACE_DIR="$TMP_HOME/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/quality.sh"

test_case "design review defaults use the provider-neutral council pool"
defaults="$(design_review_default_agents test)"
if [[ "$defaults" == $'claude-sonnet\ncodex\ncommandcode\nclaude-sonnet' ]]; then
  test_pass
else
  test_fail "expected exact admitted provider sequence, got: $(tr '\n' '|' <<< "$defaults")"
fi

test_case "design review defaults fail closed when the allowlist admits no available provider"
defaults=""
if defaults="$(OCTO_ALLOWED_PROVIDERS=agy design_review_default_agents test)"; then
  test_fail "provider discovery unexpectedly succeeded with no admitted provider: $defaults"
elif [[ -z "$defaults" ]]; then
  test_pass
else
  test_fail "failed discovery emitted an unadmitted fallback: $defaults"
fi

test_case "invalid council provider policy prevents design review defaults"
defaults=""
if defaults="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=codex,codex design_review_default_agents test)"; then
  test_fail "invalid duplicate provider policy unexpectedly succeeded: $defaults"
elif [[ -z "$defaults" ]]; then
  test_pass
else
  test_fail "invalid policy emitted fallback providers: $defaults"
fi

test_case "design review assigns providers independently from semantic roles"
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
  printf '%s\n' '- Architecture: keep boundaries explicit and preserve existing contracts.' '- Risks: validate edge cases, dependency failures, and integration behavior.' '- Testing: run focused unit coverage plus end-to-end verification before delivery.'
}
design_review_ceremony "test" >/dev/null
roles="$(cut -d'|' -f2 "$CAPTURE" | tr '\n' '|')"
providers="$(cut -d'|' -f1 "$CAPTURE" | tr '\n' '|')"
expected_calls=$'claude-sonnet|implementer|ceremony\ncodex|researcher|ceremony\ncommandcode|code-reviewer|ceremony\nclaude-sonnet|synthesizer|ceremony'
if [[ "$(<"$CAPTURE")" == "$expected_calls" ]]; then
  test_pass
else
  test_fail "expected exact provider/role ceremony sequence; roles=$roles providers=$providers calls=$(tr '\n' ';' < "$CAPTURE")"
fi

test_case "explicit design-review override cannot bypass the provider allowlist"
: > "$CAPTURE"
override_rc=0
OCTO_ALLOWED_PROVIDERS=codex \
OCTOPUS_DESIGN_REVIEW_RESEARCHER_AGENT=agy \
  design_review_ceremony "test" >/dev/null 2>&1 || override_rc=$?
if [[ "$override_rc" -ne 0 && ! -s "$CAPTURE" ]]; then
  test_pass
else
  test_fail "disallowed override was dispatched or ceremony did not fail closed: rc=$override_rc calls=$(tr '\n' ';' < "$CAPTURE")"
fi

test_case "provider-local model keeps provider identity separate from role model"
log() { :; }
export OCTOPUS_PLATFORM=Linux
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
model="$(resolve_octopus_model commandcode commandcode ceremony researcher)"
if [[ "$model" == "minimaxai/minimax-m3" ]]; then
  test_pass
else
  test_fail "expected provider-local MiniMax researcher model, got '$model'"
fi

test_case "build-fleet keeps multiline prompts in one record per provider"
multiline_prompt=$'line one\r\nPROJECT_DOCUMENTATION_PATH:\r/data/example\nline four'
fleet_output="$(bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" review standard "$multiline_prompt" 2>/dev/null)"
record_count="$(printf '%s\n' "$fleet_output" | grep -c '|')"
line_count="$(printf '%s\n' "$fleet_output" | wc -l | tr -d ' ')"
if [[ "$record_count" -eq 4 && "$line_count" -eq 4 ]] && ! printf '%s\n' "$fleet_output" | grep -q '^PROJECT_DOCUMENTATION_PATH:$' && ! printf '%s' "$fleet_output" | grep -q $'\r'; then
  test_pass
else
  test_fail "multiline prompt escaped fleet record boundaries: records=$record_count lines=$line_count"
test_case "design review retries the same model before falling back"
CALLS="$TMP_HOME/retry.calls"
: > "$CALLS"
log() { :; }
design_review_candidate_agents() { printf '%s\n' 'commandcode:stealth/ox-alpha' 'codex:gpt-5.6-luna'; }
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  if [[ "$(wc -l < "$CALLS" | tr -d ' ')" == "1" ]]; then
    printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo'
  else
    printf '%s\n' '- Architecture: preserve current contracts and isolate the change behind a narrow interface.' '- Risks: validate provider failures and malformed outputs without reducing review coverage.' '- Testing: exercise retry, fallback, and successful synthesis paths with deterministic fixtures.'
  fi
}
retry_out=""; retry_agent=""
design_review_run_seat_with_recovery 'commandcode:minimaxai/minimax-m3' 'code-reviewer' 'prompt' 0   'commandcode:minimaxai/minimax-m3 codex:gpt-5.6-luna' retry_out retry_agent
if [[ "$retry_agent" == 'commandcode:minimaxai/minimax-m3' ]] && [[ "$(wc -l < "$CALLS" | tr -d ' ')" == "2" ]]; then
  test_pass
else
  test_fail "same-seat retry did not recover: agent=$retry_agent calls=$(tr '\n' '|' < "$CALLS")"
fi

test_case "design review falls back through the shared council order after retry exhaustion"
CALLS="$TMP_HOME/fallback.calls"
: > "$CALLS"
design_review_candidate_agents() {
  printf '%s\n'     'commandcode:minimaxai/minimax-m3'     'commandcode:stealth/ox-alpha'     'codex:gpt-5.6-luna'
}
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  case "$1" in
    commandcode:minimaxai/minimax-m3) printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo' ;;
    commandcode:stealth/ox-alpha)
      printf '%s\n' '- Architecture: use the existing orchestration path and preserve seat semantics.' '- Risks: recover invalid provider output without silently dropping an independent perspective.' '- Testing: verify model-qualified fallback order and best-effort degradation behavior.' ;;
    *) printf '%s\n' 'unexpected fallback' ;;
  esac
}
fallback_out=""; fallback_agent=""
design_review_run_seat_with_recovery 'commandcode:minimaxai/minimax-m3' 'code-reviewer' 'prompt' 0   'commandcode:minimaxai/minimax-m3 codex:gpt-5.6-luna' fallback_out fallback_agent
if [[ "$fallback_agent" == 'commandcode:stealth/ox-alpha' ]] &&    [[ "$(sed -n '3p' "$CALLS")" == 'commandcode:stealth/ox-alpha' ]]; then
  test_pass
else
  test_fail "fallback order wrong: agent=$fallback_agent calls=$(tr '\n' '|' < "$CALLS")"
fi

test_case "review order supports multiple models from one provider with Ox Alpha before Luna"
order="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS='commandcode:stealth/ox-alpha,commandcode:minimaxai/minimax-m3,commandcode:deepseek/deepseek-v4-flash,codex:gpt-5.6-luna,codex:gpt-5.6-sol' bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" review-order standard test 2>/dev/null)"
first_four="$(printf '%s\n' "$order" | sed -n '1,4p')"
if [[ "$first_four" == $'commandcode:stealth/ox-alpha\ncommandcode:minimaxai/minimax-m3\ncommandcode:deepseek/deepseek-v4-flash\ncodex:gpt-5.6-luna' ]]; then
  test_pass
else
  test_fail "model-qualified council order mismatch: $(tr '\n' '|' <<< "$order")"
fi

test_summary
