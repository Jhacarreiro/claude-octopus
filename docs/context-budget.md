# Context budget and preflight summarization

Octopus applies provider input ceilings, output/overhead reserves, then role proportions. Oversized prompts may be summarized before dispatch.

Preflight summarization has two safeguards:

- `OCTOPUS_CONTEXT_SUMMARY_TRIGGER_RATIO` defaults to `110` percent, so small policy-budget overruns do not invoke destructive summarization.
- the preflight summarizer receives at least `max(target_budget * 1.25, target_budget + 2048)` input tokens, capped by its own provider input ceiling. The defaults can be tuned with `OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_RATIO` (default `125`) and `OCTOPUS_PREFLIGHT_CONTEXT_BUDGET_ADDITIVE` (default `2048`).

These values affect preflight only; ordinary `synthesizer` calls retain their normal role quota. Summaries are rejected when they drop Tangle machine-consumed anchors (`[CODING]`, `Reads:`, `Files:`, `Creates:`, `Task:`) that were present in the original prompt.
