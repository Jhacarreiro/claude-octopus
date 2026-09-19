# Tangle adequacy review JSON v1

Tangle adequacy review uses a schema-versioned JSON contract. Providers return only `schema_version`, `verdict`, `reasons`, and `scope_review`. The runtime validates and renders this JSON into the historical textual review consumed by planner reconsideration.

The historical `VERDICT:/REASONS:/SCOPE_REVIEW:` response remains a deprecated compatibility fallback during migration.

Adequacy review also receives a phase-scoped architect context proportion. `OCTOPUS_TANGLE_ADEQUACY_CONTEXT_BUDGET_RATIO` defaults to `80` (accepted range 40-100), overriding the normal architect 40% quota only for this supervised adequacy call. Ordinary architect dispatches are unchanged.
