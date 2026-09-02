#!/usr/bin/env bash
# Agent spec helpers. A spec may be a legacy executor alias (e.g. codex-review)
# or a model-qualified seat (e.g. commandcode:minimaxai/minimax-m3).
# Source-safe: defines functions only.

# Provider routing ceilings are byte-based. Bash's ${#value} counts characters
# in UTF-8 locales, so measure under the C locale before evaluating a provider.
octo_prompt_byte_length() {
    local prompt="${1:-}" bytes
    bytes="$(LC_ALL=C printf '%s' "$prompt" | wc -c | tr -d '[:space:]')" || return 1
    [[ "$bytes" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$bytes"
}

octo_agent_spec_executor() {
    local spec="${1:-}"
    printf '%s\n' "${spec%%:*}"
}

octo_agent_spec_provider() {
    local executor
    executor="$(octo_agent_spec_executor "${1:-}")"
    if declare -f octo_provider_canonical >/dev/null 2>&1; then
        octo_provider_canonical "$executor" 2>/dev/null && return 0
    fi
    case "$executor" in
        codex|codex-*) echo codex ;;
        commandcode|commandcode-*) echo commandcode ;;
        claude-sdk|claude-sdk-*) echo claude-sdk ;;
        claude|claude-*) echo claude ;;
        gemini|gemini-*) echo gemini ;;
        agy|agy-*|antigravity) echo agy ;;
        perplexity|perplexity-*) echo perplexity ;;
        openrouter|openrouter-*) echo openrouter ;;
        opencode|opencode-*) echo opencode ;;
        openai-compatible|openai-compatible-*) echo openai-compatible ;;
        atlascloud|atlascloud-*) echo atlascloud ;;
        qwen|qwen-*) echo qwen ;;
        grok|grok-*) echo grok ;;
        cursor-agent|cursor-agent-*) echo cursor-agent ;;
        copilot|copilot-*) echo copilot ;;
        vibe|vibe-*) echo vibe ;;
        ollama|ollama-*) echo ollama ;;
        *) echo "$executor" ;;
    esac
}

octo_agent_spec_explicit_model() {
    local spec="${1:-}"
    [[ "$spec" == *:* ]] || return 1
    local model="${spec#*:}"
    [[ -n "$model" ]] || return 1
    printf '%s\n' "$model"
}

# Normalize a model-qualified seat to the executable name consumed by
# dispatch.sh. Provider aliases belong at the configuration boundary; runtime
# agent specs must use dispatchable executors.
octo_agent_spec_canonicalize_exact() {
    local spec="${1-}" executor model provider canonical_executor
    [[ -n "$spec" && "$spec" == *:* ]] || return 1
    [[ "$spec" != *[[:space:]]* && "$spec" != *\\* ]] || return 1

    executor="${spec%%:*}"
    model="${spec#*:}"
    [[ -n "$executor" && -n "$model" ]] || return 1
    provider="$(octo_provider_canonical "$executor" 2>/dev/null)" || return 1

    case "$provider" in
        atlascloud) canonical_executor="atlascloud-agent" ;;
        *) canonical_executor="$provider" ;;
    esac

    octo_provider_has_capability "$provider" dispatch || return 1

    # Exact contextual seats are serialized into a shell command string and
    # later split into argv. Keep the accepted model grammar to one safe token.
    case "$model" in
        /*|*[[:space:]]*|*\\*|*\**|*";"*|*"|"*|*"&"*|*'$'*|*'`'*|*"'"*|*'"'*|*"("*|*")"*|*"<"*|*">"*|*"!"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*) return 1 ;;
    esac

    printf '%s:%s\n' "$canonical_executor" "$model"
}

octo_agent_spec_slug() {
    local spec="${1:-unknown}"
    # Keep the full seat identity while making it safe for filenames and
    # colon-delimited ledgers. Repeated separators collapse deterministically.
    printf '%s' "$spec" | sed -E 's/[^A-Za-z0-9._-]+/_/g; s/^_+//; s/_+$//'
}

octo_model_family() {
    local spec="${1:-}" effective_model="${2:-}"
    local executor model prefix
    executor="$(octo_agent_spec_executor "$spec")"
    model="$effective_model"
    if [[ -z "$model" ]]; then
        model="$(octo_agent_spec_explicit_model "$spec" 2>/dev/null || true)"
    fi

    case "$model" in
        anthropic/*|*claude*) echo anthropic; return ;;
        minimaxai/*|minimax/*|*minimax*) echo minimax; return ;;
        deepseek/*|*deepseek*) echo deepseek; return ;;
        openai/*|gpt-*|o[0-9]*|*chatgpt*) echo openai; return ;;
        google/*|*gemini*) echo google; return ;;
        qwen/*|alibaba/*|*qwen*) echo alibaba; return ;;
        x-ai/*|xai/*|*grok*) echo xai; return ;;
        mistralai/*|*mistral*) echo mistral; return ;;
        stealth/*) echo stealth; return ;;
        */*)
            prefix="${model%%/*}"
            [[ -n "$prefix" ]] && { printf '%s\n' "$prefix"; return; }
            ;;
    esac

    case "$executor" in
        codex|codex-*) echo openai ;;
        claude|claude-*) echo anthropic ;;
        gemini|gemini-*|agy|agy-*|antigravity) echo google ;;
        qwen|qwen-*) echo alibaba ;;
        grok|grok-*|cursor-agent|cursor-agent-*) echo xai ;;
        vibe|vibe-*) echo mistral ;;
        perplexity|perplexity-*) echo perplexity ;;
        copilot|copilot-*) echo microsoft ;;
        commandcode|commandcode-*|openrouter|openrouter-*|opencode|opencode-*|openai-compatible|openai-compatible-*|atlascloud|atlascloud-*) echo multi ;;
        ollama|ollama-*) echo local ;;
        *) echo unknown ;;
    esac
}
