#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"

test_suite "Provider registry consumer contracts"

test_case "health capability matches implemented health cases"
expected="codex commandcode claude claude-sdk gemini agy perplexity openrouter atlascloud cursor-agent grok qwen ollama copilot vibe"
actual="$(octo_provider_ids health)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "health set drift: $actual"; fi

test_case "Council capability preserves current providers and adds commandcode"
expected="codex commandcode claude gemini agy opencode openrouter openai-compatible openai-tools qwen"
actual="$(octo_provider_ids council)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "Council set drift: $actual"; fi

test_case "model-config capability unifies both former allowlists"
for provider in codex commandcode claude claude-sdk gemini agy perplexity opencode openrouter atlascloud openai-compatible openai-tools openai-compatible-agent cursor-agent grok qwen ollama copilot vibe; do
    if ! octo_provider_has_capability "$provider" model-config; then
        test_fail "model-config missing $provider"
        exit 0
    fi
done
test_pass

test_case "every health provider has an explicit check_provider_health case"
body=$(sed -n '/^check_provider_health() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/providers.sh")
for provider in $(octo_provider_ids health); do
    case "$provider" in agy) pattern='agy|antigravity)' ;; *) pattern="${provider})" ;; esac
    if ! grep -Fq "$pattern" <<< "$body"; then
        test_fail "health capability lacks implementation: $provider"
        exit 0
    fi
done
test_pass

test_case "commandcode is exposed by provider detection"
if grep -q 'octo_provider_allowed commandcode' "$PROJECT_ROOT/scripts/lib/providers.sh" && grep -q 'result=.*commandcode:' "$PROJECT_ROOT/scripts/lib/providers.sh"; then test_pass; else test_fail "commandcode detection missing"; fi

test_case "public help reflects configurable Council default policy"
if grep -q 'octo_council_default_providers' "$PROJECT_ROOT/scripts/lib/usage-help.sh" &&    grep -q 'OCTOPUS_COUNCIL_DEFAULT_PROVIDERS' "$PROJECT_ROOT/scripts/lib/provider-policy.sh" &&    grep -q 'COMMAND_CODE_API_KEY' "$PROJECT_ROOT/scripts/lib/usage-help.sh"; then
    test_pass
else
    test_fail "Council help does not use shared configurable policy or expose Command Code auth"
fi

test_case "preflight exposes and caches commandcode"
if grep -q 'COMMANDCODE_STATUS=ok' "$PROJECT_ROOT/scripts/lib/preflight.sh" &&    grep -q 'COMMANDCODE_AUTH=' "$PROJECT_ROOT/scripts/lib/preflight.sh" &&    grep -q 'local commandcode_status=' "$PROJECT_ROOT/scripts/lib/preflight.sh"; then
    test_pass
else
    test_fail "preflight commandcode contract missing"
fi


test_case "every detect-capable provider has a detection path"
detect_body=$(sed -n '/^detect_providers() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/providers.sh")
for provider in $(octo_provider_ids detect); do
    if ! grep -Fq "octo_provider_allowed $provider" <<< "$detect_body" && ! grep -Fq "${provider}:" <<< "$detect_body"; then
        test_fail "detect capability lacks implementation: $provider"
        exit 0
    fi
done
test_pass

test_case "every dispatch-capable provider is represented by dispatch or helper routing"
for provider in $(octo_provider_ids dispatch); do
    if ! grep -Rqi --exclude=provider-registry.sh "$provider" \
        "$PROJECT_ROOT/scripts/lib/dispatch.sh" \
        "$PROJECT_ROOT/scripts/lib/provider-routing.sh" \
        "$PROJECT_ROOT/scripts/helpers"; then
        test_fail "dispatch capability lacks implementation: $provider"
        exit 0
    fi
done
test_pass

test_case "environment builder has a safe generic fallback"
env_body=$(sed -n '/^_octo_build_provider_env_impl() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/provider-routing.sh")
if grep -q 'Other providers: no isolation needed' <<< "$env_body" && grep -A2 'Other providers: no isolation needed' <<< "$env_body" | grep -q 'return 0'; then
    test_pass
else
    test_fail "generic provider environment fallback missing"
fi


test_case "detect capability matches the complete implemented detection inventory"
expected="codex commandcode claude claude-sdk gemini agy perplexity opencode openrouter atlascloud openai-compatible cursor-agent grok qwen ollama copilot vibe"
actual="$(octo_provider_ids detect)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "detect set drift: $actual"; fi

test_case "canonical provider inventory is explicit and complete"
expected="codex commandcode claude claude-sdk gemini agy perplexity opencode openrouter atlascloud openai-compatible openai-tools openai-compatible-agent cursor-agent grok qwen ollama copilot vibe"
actual="$(octo_provider_ids)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "canonical provider inventory drift: $actual"; fi

test_case "registry self-validation enforces baseline and documented omissions"
if octo_provider_validate_contracts; then test_pass; else test_fail "registry governance contract failed"; fi

test_summary
