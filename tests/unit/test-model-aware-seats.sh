#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "PASS: $1"; }
bad(){ FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

source scripts/lib/agent-spec.sh
[[ "$(octo_agent_spec_executor 'commandcode:stealth/ox-alpha')" == commandcode ]] && ok executor || bad executor
[[ "$(octo_agent_spec_explicit_model 'commandcode:stealth/ox-alpha')" == stealth/ox-alpha ]] && ok model || bad model
[[ "$(octo_agent_spec_slug 'commandcode:stealth/ox-alpha')" == commandcode_stealth_ox-alpha ]] && ok slug || bad slug
[[ "$(octo_model_family 'commandcode:minimaxai/minimax-m3')" == minimax ]] && ok minimax-family || bad minimax-family
[[ "$(octo_model_family 'codex:gpt-5.6-luna')" == openai ]] && ok openai-family || bad openai-family

log(){ :; }
PLUGIN_DIR="$ROOT"
source scripts/lib/validation.sh
source scripts/lib/model-resolver.sh
source scripts/lib/dispatch.sh
[[ "$(get_agent_model 'commandcode:stealth/ox-alpha' ceremony code-reviewer)" == stealth/ox-alpha ]] && ok commandcode-model-pin || bad commandcode-model-pin
[[ "$(get_agent_model 'codex:gpt-5.6-luna' ceremony code-reviewer)" == gpt-5.6-luna ]] && ok codex-model-pin || bad codex-model-pin
get_agent_command 'commandcode:stealth/ox-alpha' ceremony code-reviewer | grep -q 'commandcode-exec.sh stealth/ox-alpha' && ok commandcode-dispatch || bad commandcode-dispatch
get_agent_command 'codex:gpt-5.6-luna' ceremony code-reviewer | grep -q -- '--model gpt-5.6-luna' && ok codex-dispatch || bad codex-dispatch

fake=$(mktemp)
cat > "$fake" <<'CHECK'
#!/usr/bin/env bash
echo commandcode:available
echo codex:available
echo claude:available
CHECK
chmod +x "$fake"
order="$(OCTOPUS_PROVIDER_CHECKER="$fake" OCTOPUS_COUNCIL_DEFAULT_PROVIDERS='commandcode:stealth/ox-alpha,commandcode:minimaxai/minimax-m3,commandcode:deepseek/deepseek-v4-flash,codex:gpt-5.6-luna,codex:gpt-5.6-sol' bash scripts/helpers/build-fleet.sh review-order standard test)"
ox_line="$(printf '%s\n' "$order" | grep -n -F 'commandcode:stealth/ox-alpha' | head -1 | cut -d: -f1)"
luna_line="$(printf '%s\n' "$order" | grep -n -F 'codex:gpt-5.6-luna' | head -1 | cut -d: -f1)"
all_present=true
for spec in \
  'commandcode:stealth/ox-alpha' \
  'commandcode:minimaxai/minimax-m3' \
  'commandcode:deepseek/deepseek-v4-flash' \
  'codex:gpt-5.6-luna' \
  'codex:gpt-5.6-sol'; do
  printf '%s\n' "$order" | grep -Fxq "$spec" || all_present=false
done
[[ "$all_present" == true && -n "$ox_line" && -n "$luna_line" && "$ox_line" -lt "$luna_line" ]] && ok review-order || bad review-order
rm -f "$fake"

source scripts/lib/council.sh
council_prompt_for_member(){ echo prompt; }
council_persona_should_fail(){ return 1; }
run_quorum_case(){
  local roster="$1" d
  d=$(mktemp -d); mkdir -p "$d/responses"
  COUNCIL_RUN_DIR="$d" COUNCIL_DEPTH=standard COUNCIL_FIXTURE=full-success COUNCIL_EXECUTION_MODE="" \
  COUNCIL_TASK=x COUNCIL_GOAL=advice COUNCIL_DOMAIN=auto COUNCIL_STYLE=balanced COUNCIL_ROSTER_JSON="$roster"
  council_run_advice_phase >/dev/null 2>&1 || true
  rm -rf "$d"
}
case_a='[{"persona":"strategy-analyst","seat":"chair","agent_spec":"claude-sonnet","provider":"claude-sonnet","provider_org":"anthropic","model":"claude-sonnet-5","model_family":"anthropic"},{"persona":"code-reviewer","seat":"member","agent_spec":"commandcode:minimaxai/minimax-m3","provider":"commandcode","provider_org":"commandcode","model":"minimaxai/minimax-m3","model_family":"minimax"},{"persona":"backend-architect","seat":"member","agent_spec":"commandcode:deepseek/deepseek-v4-flash","provider":"commandcode","provider_org":"commandcode","model":"deepseek/deepseek-v4-flash","model_family":"deepseek"}]'
run_quorum_case "$case_a"
[[ "$COUNCIL_QUORUM_MET" == true && "$COUNCIL_DISTINCT_APPROVING_MODEL_FAMILIES" == 2 && "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" == 1 ]] && ok same-provider-different-families || bad same-provider-different-families
case_b='[{"persona":"strategy-analyst","seat":"chair","agent_spec":"claude-sonnet","provider":"claude-sonnet","provider_org":"anthropic","model":"claude-sonnet-5","model_family":"anthropic"},{"persona":"code-reviewer","seat":"member","agent_spec":"commandcode:openai/gpt-5","provider":"commandcode","provider_org":"commandcode","model":"openai/gpt-5","model_family":"openai"},{"persona":"backend-architect","seat":"member","agent_spec":"codex:gpt-5.6-luna","provider":"codex","provider_org":"openai","model":"gpt-5.6-luna","model_family":"openai"}]'
run_quorum_case "$case_b"
[[ "$COUNCIL_QUORUM_MET" == false && "$COUNCIL_DISTINCT_APPROVING_MODEL_FAMILIES" == 1 && "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" == 2 ]] && ok different-provider-same-family || bad different-provider-same-family

echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
