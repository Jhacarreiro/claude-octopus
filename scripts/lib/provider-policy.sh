#!/usr/bin/env bash
# Shared provider-selection policy defaults.
# Identity and capabilities live in provider-registry.sh; these ordered lists
# are workflow policy and remain independently configurable.

OCTOPUS_COUNCIL_DEFAULT_PROVIDERS_DEFAULT="claude,codex,agy,gemini,qwen,opencode,openrouter,openai-compatible,openai-tools"
OCTOPUS_SMOKE_ROUTING_PROVIDERS_DEFAULT="codex gemini agy claude opencode openrouter"

octo_council_default_providers() {
    printf '%s\n' "${OCTOPUS_COUNCIL_DEFAULT_PROVIDERS:-$OCTOPUS_COUNCIL_DEFAULT_PROVIDERS_DEFAULT}"
}

octo_smoke_routing_providers() {
    printf '%s\n' "${OCTOPUS_SMOKE_ROUTING_PROVIDERS:-$OCTOPUS_SMOKE_ROUTING_PROVIDERS_DEFAULT}"
}
