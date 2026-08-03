#!/usr/bin/env bash
# Canonical provider identity registry.
# Source-safe and Bash 3.2 compatible: no associative arrays, no shell options.
#
# Columns: id|aliases|command|organization|capabilities
# Capabilities describe which shared interfaces should expose the provider.

octo_provider_registry_rows() {
    cat <<'EOF'
codex|openai,gpt*|codex|openai|model-config,council,health,detect,dispatch,env
commandcode|command-code*|command-code|commandcode|model-config,council,health,detect,dispatch,env
claude|anthropic,sonnet*,opus*|claude|anthropic|model-config,council,health,detect,dispatch,env
claude-sdk|claude-agent*|claude-agent|anthropic|model-config,health,detect,dispatch,env
gemini|gemini-cli*|gemini|google|model-config,council,health,detect,dispatch,env
agy|antigravity*|agy|google|model-config,council,health,detect,dispatch,env
perplexity||perplexity|perplexity|model-config,health,detect,dispatch,env
opencode||opencode|opencode|model-config,council,detect,dispatch,env
openrouter||openrouter|openrouter|model-config,council,health,detect,dispatch,env
atlascloud|atlas,atlas-cloud|atlascloud|atlascloud|model-config,health,detect,dispatch,env
openai-compatible||openai-compatible|openai-compatible|model-config,council,detect,dispatch,env
openai-tools||openai-compatible|openai-compatible|model-config,council,dispatch,env
openai-compatible-agent||openai-compatible|openai-compatible|model-config,dispatch,env
cursor-agent|cursor|cursor-agent|cursor|model-config,health,detect,dispatch,env
grok|xai|grok|xai|model-config,health,detect,dispatch,env
qwen||qwen|alibaba|model-config,council,health,detect,dispatch,env
ollama|local|ollama|local|model-config,health,detect,dispatch,env
copilot|github-copilot|copilot|github|model-config,health,detect,dispatch,env
vibe||vibe|mistral|model-config,health,detect,dispatch,env
EOF
}

octo_provider_normalize() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ' ,'
}

octo_provider_canonical() {
    local requested normalized id aliases command org caps alias alias_base
    local best_id="" best_len=0 id_len old_ifs
    requested="${1:-}"
    normalized="$(octo_provider_normalize "$requested")"
    [[ -n "$normalized" ]] || return 1

    # Exact canonical IDs always win over aliases and prefixes.
    while IFS='|' read -r id aliases command org caps; do
        if [[ "$normalized" == "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    done <<EOF
$(octo_provider_registry_rows)
EOF

    # Aliases are exact unless explicitly suffixed with '*'.
    while IFS='|' read -r id aliases command org caps; do
        old_ifs="$IFS"
        IFS=','
        for alias in $aliases; do
            IFS="$old_ifs"
            [[ -n "$alias" ]] || continue
            case "$alias" in
                *'*')
                    alias_base="${alias%\*}"
                    if [[ "$normalized" == "$alias_base"* ]]; then
                        printf '%s\n' "$id"
                        return 0
                    fi
                    ;;
                *)
                    if [[ "$normalized" == "$alias" ]]; then
                        printf '%s\n' "$id"
                        return 0
                    fi
                    ;;
            esac
            IFS=','
        done
        IFS="$old_ifs"
    done <<EOF
$(octo_provider_registry_rows)
EOF

    # Agent variants such as commandcode-research use canonical-ID prefixes.
    # Choose the longest matching ID so claude-sdk-* cannot collapse to claude.
    while IFS='|' read -r id aliases command org caps; do
        if [[ "$normalized" == "$id-"* ]]; then
            id_len=${#id}
            if (( id_len > best_len )); then
                best_id="$id"
                best_len=$id_len
            fi
        fi
    done <<EOF
$(octo_provider_registry_rows)
EOF
    [[ -n "$best_id" ]] || return 1
    printf '%s\n' "$best_id"
}

octo_provider_valid() {
    octo_provider_canonical "${1:-}" >/dev/null 2>&1
}

octo_provider_field() {
    local requested field canonical id aliases command org caps
    requested="$1"
    field="$2"
    canonical="$(octo_provider_canonical "$requested")" || return 1
    while IFS='|' read -r id aliases command org caps; do
        [[ "$id" == "$canonical" ]] || continue
        case "$field" in
            id) printf '%s\n' "$id" ;;
            aliases) printf '%s\n' "$aliases" ;;
            command) printf '%s\n' "$command" ;;
            organization|org) printf '%s\n' "$org" ;;
            capabilities) printf '%s\n' "$caps" ;;
            *) return 1 ;;
        esac
        return 0
    done <<EOF
$(octo_provider_registry_rows)
EOF
    return 1
}

octo_provider_command() { octo_provider_field "$1" command; }
octo_provider_org() { octo_provider_field "$1" organization; }

octo_provider_has_capability() {
    local provider capability caps
    provider="$1"
    capability="$2"
    caps="$(octo_provider_field "$provider" capabilities)" || return 1
    case ",$caps," in
        *",$capability,"*) return 0 ;;
    esac
    return 1
}

octo_provider_ids() {
    local capability="${1:-}" id aliases command org caps out=""
    while IFS='|' read -r id aliases command org caps; do
        if [[ -n "$capability" ]]; then
            case ",$caps," in
                *",$capability,"*) ;;
                *) continue ;;
            esac
        fi
        out="${out}${out:+ }${id}"
    done <<EOF
$(octo_provider_registry_rows)
EOF
    printf '%s\n' "$out"
}
