#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/execution-profile.sh"
source "$PROJECT_ROOT/scripts/lib/fallback-chain.sh"

test_suite "configurable fallback chains"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
CFG="$TMP_ROOT/providers.json"
export OCTOPUS_PROVIDERS_CONFIG="$CFG"

write_config() {
    cat > "$CFG" <<'JSON'
{
  "routing": {
    "roles": {
      "code-reviewer": {"provider":"codex","model":"gpt-luna-test"},
      "implementer-heavy": {"provider":"codex","model":"gpt-sol-test"},
      "architect": {"provider":"claude","model":"claude-opus-test"}
    }
  }
}
JSON
}
write_config

test_case "built-in default chain is code-reviewer -> implementer-heavy -> architect"
chain=$(octo_fallback_builtin_chain_json default | jq -r '[.[].role] | join(",")')
if [[ "$chain" == "code-reviewer,implementer-heavy,architect" ]]; then test_pass; else test_fail "unexpected default: $chain"; fi

test_case "default roles resolve through routing.roles provider and model"
specs=$(octo_fallback_chain_agent_specs default)
expected=$'codex:gpt-luna-test\ncodex:gpt-sol-test\nclaude:claude-opus-test'
if [[ "$specs" == "$expected" ]]; then test_pass; else test_fail "unexpected specs: [$specs]"; fi

test_case "providers.json may replace the fallback chain"
jq '.routing.fallbackChains.default=[{"role":"architect"},{"provider":"commandcode","model":"custom/model"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
expected=$'claude:claude-opus-test\ncommandcode:custom/model'
if [[ "$specs" == "$expected" ]]; then test_pass; else test_fail "override not honored: [$specs]"; fi

write_config
is_agent_available() { [[ "$1" == "claude" ]]; }
test_case "technical availability uses the same configured/default chain"
chosen=$(octo_fallback_first_available default commandcode)
if [[ "$chosen" == "claude:claude-opus-test" ]]; then test_pass; else test_fail "expected qualified claude spec, got $chosen"; fi

test_case "technical fallback preserves explicit provider:model candidates"
jq '.routing.fallbackChains.default=[{"provider":"claude","model":"claude-pinned-test"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
chosen=$(octo_fallback_first_available default commandcode)
if [[ "$chosen" == "claude:claude-pinned-test" ]]; then test_pass; else test_fail "explicit model was lost: $chosen"; fi
write_config

ATTEMPTS="$TMP_ROOT/attempts.log"
: > "$ATTEMPTS"
validate_protocol() {
    [[ "$1" == *"DECISIONS:"* && "$1" == *"DECOMPOSITION:"* ]]
}
run_agent_sync() {
    local spec="$1" role="$4" phase="$5"
    printf '%s|%s|%s\n' "$spec" "$role" "$phase" >> "$ATTEMPTS"
    case "$spec" in
        commandcode:primary) printf '   \n'; return 0 ;;
        codex:gpt-luna-test) printf 'I will inspect this first.\n'; return 0 ;;
        codex:gpt-sol-test) printf 'DECISIONS:\n- ACCEPT fix\nDECOMPOSITION:\n1. [CODING] valid\n'; return 0 ;;
        claude:claude-opus-test) printf 'DECISIONS:\n- ACCEPT last\nDECOMPOSITION:\n1. [CODING] last\n'; return 0 ;;
        commandcode:technical-fail) return 42 ;;
        *) return 7 ;;
    esac
}
log() { :; }

test_case "empty and semantically invalid success both advance the same chain"
: > "$ATTEMPTS"
out=$(run_agent_sync_fallback_chain commandcode:primary 'plan it' 30 researcher tangle validate_protocol default)
count=$(wc -l < "$ATTEMPTS" | tr -d ' ')
roles=$(cut -d'|' -f2 "$ATTEMPTS" | sort -u)
phases=$(cut -d'|' -f3 "$ATTEMPTS" | sort -u)
if [[ "$out" == *"DECOMPOSITION:"* && "$count" -eq 3 && "$roles" == "researcher" && "$phases" == "tangle" ]]; then
    test_pass
else
    test_fail "semantic fallback failed: count=$count roles=$roles phases=$phases out=[$out]"
fi

test_case "process failure advances through the same chain"
: > "$ATTEMPTS"
out=$(run_agent_sync_fallback_chain commandcode:technical-fail 'plan it' 30 researcher tangle validate_protocol default)
first=$(sed -n '1p' "$ATTEMPTS" | cut -d'|' -f1)
second=$(sed -n '2p' "$ATTEMPTS" | cut -d'|' -f1)
if [[ "$first" == "commandcode:technical-fail" && "$second" == "codex:gpt-luna-test" && "$out" == *"DECOMPOSITION:"* ]]; then
    # Luna is semantically invalid, so Sol should ultimately satisfy the validator.
    [[ $(wc -l < "$ATTEMPTS") -eq 3 ]] && test_pass || test_fail "expected three attempts"
else
    test_fail "technical fallback did not use common chain"
fi

test_case "chain exhausts and fails closed when every candidate is unusable"
run_agent_sync() {
    printf '%s\n' "$1" >> "$ATTEMPTS"
    printf 'not-valid\n'
    return 0
}
: > "$ATTEMPTS"
rc=0
run_agent_sync_fallback_chain commandcode:primary 'plan it' 30 researcher tangle validate_protocol default >/dev/null || rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'claude:claude-opus-test' "$ATTEMPTS"; then test_pass; else test_fail "chain did not exhaust safely"; fi

test_summary
