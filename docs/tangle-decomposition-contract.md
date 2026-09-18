# Tangle decomposition JSON contract v1

Tangle decomposition uses a versioned JSON contract as the primary provider protocol. The schema is published at `schemas/tangle-decomposition-v1.schema.json`.

A valid response is a JSON object with `schema_version: 1` and 1-6 ordered subtasks, including at least one coding subtask. Each subtask contains `id`, `kind`, `title`, `reads`, `files`, `creates`, and `task`. Coding subtasks require at least one write scope; reasoning subtasks cannot declare write scopes.

Validated JSON is rendered into the existing one-line wire format so the executor and downstream scope/adequacy validators remain unchanged during migration.

## Compatibility

The historical one-line wire format remains accepted temporarily. Structured Markdown normalization is a **deprecated compatibility fallback** only. Do not extend it for new presentation variants unless needed for a critical regression. Deprecation usage is logged so it can be removed once providers reliably emit JSON v1.

Native provider structured-output / JSON-schema enforcement can be layered on top where supported; other providers are instructed to return JSON only and are validated locally.
