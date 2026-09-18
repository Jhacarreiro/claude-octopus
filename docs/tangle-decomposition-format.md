# Deprecated compatibility format

> JSON v1 is the primary decomposition protocol. This Markdown normalizer is a temporary backwards-compatibility fallback and should not be extended for new presentation variants.

# Tangle decomposition input normalization

Tangle keeps a compact one-line wire format for internal scope validation, but provider output may use equivalent structured Markdown. Before moving to another provider, Tangle deterministically normalizes Markdown headings such as `### N. [CODING]` or `### N. [REASONING]`, plus `Reads:`, `Files:`, `Creates:` blocks and task prose, into the existing wire format.

The normalizer does not invent write scopes. A coding item with no concrete `Files:` or `Creates:` paths fails closed and the configured provider fallback chain continues. Existing valid wire-format output is returned unchanged. Acceptance-evidence, input/output metadata and blocking notes are not promoted into `Task:` authority.

This local repair is intentionally syntax-only: semantic/scope adequacy review, contextual-read validation, overlap handling and adaptive/strict write policy still run afterwards.
