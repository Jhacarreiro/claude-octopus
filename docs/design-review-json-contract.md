# Design review JSON contracts v1

All model-to-model design-review data is JSON. Each review seat returns Design Review Seat v1 (`approach`, `dependencies`, `risks`, `testing`, `integration`). The synthesizer consumes those JSON seat objects and returns Design Review Synthesis v1 (`conflicts`, `gaps`, `resolution`, `risks`, `decisions`). The canonical synthesis object is passed downstream to decomposition.

For migration safety, substantive historical free-text seat/synthesis output is deterministically wrapped into the corresponding JSON object and logged as deprecated. Output that looks like JSON but fails the JSON contract is rejected/retried rather than treated as legacy prose. Human console rendering is derived from synthesis JSON and is not used as machine input.
