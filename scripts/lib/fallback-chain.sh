#!/usr/bin/env bash
# Unified configurable fallback-chain helpers.
# Source-safe: defines functions only and resolves providers/models lazily.

_octo_fallback_config_file() {
    if declare -f _octopus_profile_config_file >/dev/null 2>&1; then
        _octopus_profile_config_file
    else
        printf '%s\n' "${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    fi
}

octo_fallback_builtin_chain_json() {
    local name="${1:-default}"
    case "$name" in
        default)
            printf '%s\n' '[{"role":"code-reviewer"},{"role":"implementer-heavy"},{"role":"architect"}]'
            ;;
        *)
            printf '%s\n' '[]'
            ;;
    esac
}

octo_fallback_chain_json() {
    local name="${1:-default}" cfg configured=""
    cfg="$(_octo_fallback_config_file)"

    if [[ -f "$cfg" ]]; then
        configured="$(jq -c --arg name "$name" '
            (.routing.fallbackChains[$name] //
             (if $name != "default" then .routing.fallbackChains.default else null end) //
             null) as $chain
            | if $chain == null then empty
              elif ($chain | type) == "array" then $chain
              elif (($chain | type) == "object" and (($chain.attempts // null) | type) == "array") then $chain.attempts
              else empty end
        ' "$cfg" 2>/dev/null || true)"
    fi

    if [[ -n "$configured" ]]; then
        printf '%s\n' "$configured"
    else
        octo_fallback_builtin_chain_json "$name"
    fi
}

_octo_fallback_ensure_role_resolver() {
    declare -f get_role_agent >/dev/null 2>&1 && declare -f get_role_model >/dev/null 2>&1 && return 0
    local lib_dir nounset_was_on="false"
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ "$-" == *u* ]] && nounset_was_on="true" && set +u
    source "${lib_dir}/agent-utils.sh" 2>/dev/null || true
    [[ "$nounset_was_on" == "true" ]] && set -u
    declare -f get_role_agent >/dev/null 2>&1 && declare -f get_role_model >/dev/null 2>&1
}

octo_fallback_role_agent_spec() {
    local role="$1" phase="${2:-}" provider="" model="" routed_provider=""

    _octo_fallback_ensure_role_resolver || return 1
    routed_provider="$(get_role_agent "$role" 2>/dev/null || true)"
    model="$(get_role_model "$role" 2>/dev/null || true)"
    [[ -n "$routed_provider" ]] || return 1

    if declare -f octopus_profile_provider >/dev/null 2>&1; then
        provider="$(octopus_profile_provider "$phase" "$role" "$routed_provider" 2>/dev/null || true)"
    fi
    provider="${provider:-$routed_provider}"

    if declare -f octopus_profile_model >/dev/null 2>&1; then
        local configured_model
        configured_model="$(octopus_profile_model "$phase" "$role" 2>/dev/null || true)"
        [[ -n "$configured_model" ]] && model="$configured_model"
    fi

    if [[ -n "$model" ]]; then
        printf '%s:%s\n' "$provider" "$model"
    else
        printf '%s\n' "$provider"
    fi
}

octo_fallback_candidate_agent_spec() {
    local candidate="$1" phase="${2:-}" type role provider model agent
    type="$(jq -r 'type' <<<"$candidate" 2>/dev/null || true)"

    if [[ "$type" == "string" ]]; then
        role="$(jq -r '.' <<<"$candidate")"
        octo_fallback_role_agent_spec "$role" "$phase"
        return
    fi
    [[ "$type" == "object" ]] || return 1

    role="$(jq -r '.role // empty' <<<"$candidate")"
    if [[ -n "$role" ]]; then
        octo_fallback_role_agent_spec "$role" "$phase"
        return
    fi

    agent="$(jq -r '.agent // empty' <<<"$candidate")"
    if [[ -n "$agent" ]]; then
        printf '%s\n' "$agent"
        return
    fi

    provider="$(jq -r '.provider // empty' <<<"$candidate")"
    model="$(jq -r '.model // empty' <<<"$candidate")"
    [[ -n "$provider" ]] || return 1
    if [[ -n "$model" ]]; then
        printf '%s:%s\n' "$provider" "$model"
    else
        printf '%s\n' "$provider"
    fi
}

octo_fallback_chain_agent_specs() {
    local name="${1:-default}" phase="${2:-}" chain candidate spec
    chain="$(octo_fallback_chain_json "$name")"
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        spec="$(octo_fallback_candidate_agent_spec "$candidate" "$phase" 2>/dev/null || true)"
        [[ -n "$spec" ]] && printf '%s\n' "$spec"
    done < <(jq -c '.[]' <<<"$chain" 2>/dev/null)
}

_octo_fallback_provider_identity() {
    local spec="${1:-}" executor=""
    executor="${spec%%:*}"
    if declare -f octo_agent_spec_provider >/dev/null 2>&1; then
        octo_agent_spec_provider "$spec" 2>/dev/null && return 0
    fi
    case "$executor" in
        codex|codex-*) echo codex ;;
        claude|claude-*) echo claude ;;
        agy|agy-*|antigravity|gemini|gemini-*) echo agy ;;
        commandcode|commandcode-*) echo commandcode ;;
        openrouter|openrouter-*) echo openrouter ;;
        *) echo "$executor" ;;
    esac
}

octo_fallback_first_available() {
    local name="${1:-default}" preferred="${2:-}" phase="${3:-}" spec executor
    local preferred_provider="" candidate_provider=""
    preferred_provider="$(_octo_fallback_provider_identity "$preferred")"
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        executor="${spec%%:*}"
        candidate_provider="$(_octo_fallback_provider_identity "$spec")"
        [[ -n "$preferred_provider" && "$candidate_provider" == "$preferred_provider" ]] && continue
        if declare -f is_agent_available >/dev/null 2>&1 && is_agent_available "$executor"; then
            printf '%s\n' "$spec"
            return 0
        fi
    done < <(octo_fallback_chain_agent_specs "$name" "$phase")
    return 1
}

octo_fallback_output_usable() {
    local output="${1:-}" validator="${2:-}"
    [[ -n "${output//[[:space:]]/}" ]] || return 1
    if [[ -n "$validator" ]]; then
        declare -F "$validator" >/dev/null 2>&1 || return 2
        "$validator" "$output" >/dev/null
        return $?
    fi
    return 0
}

run_agent_sync_fallback_chain() {
    local primary_agent="$1" prompt="$2" timeout_secs="${3:-120}" semantic_role="${4:-}" phase="${5:-}"
    local validator="${6:-}" chain_name="${7:-default}"
    local spec output="" rc=0 reason="" attempted="|"

    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        [[ "$attempted" == *"|$spec|"* ]] && continue
        attempted+="$spec|"

        output=""
        rc=0
        if output=$(run_agent_sync "$spec" "$prompt" "$timeout_secs" "$semantic_role" "$phase"); then
            if octo_fallback_output_usable "$output" "$validator"; then
                printf '%s\n' "$output"
                return 0
            fi
            reason="semantic-invalid"
        else
            rc=$?
            reason="process-error:$rc"
        fi
        if declare -f log >/dev/null 2>&1; then
            log WARN "Fallback chain '$chain_name': $spec failed ($reason); trying next candidate"
        fi
    done < <(
        printf '%s\n' "$primary_agent"
        octo_fallback_chain_agent_specs "$chain_name" "$phase"
    )

    if declare -f log >/dev/null 2>&1; then
        log ERROR "Fallback chain '$chain_name' exhausted without a usable result"
    fi
    return 1
}
