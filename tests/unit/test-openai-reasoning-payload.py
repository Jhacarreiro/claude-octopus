#!/usr/bin/env python3
import importlib.util
import io
import json
import urllib.error
from pathlib import Path
from unittest.mock import patch

path = Path(__file__).resolve().parents[2] / "scripts/helpers/openai-compatible-agent.py"
spec = importlib.util.spec_from_file_location("agent", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class Resp:
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return b'{"choices":[{"message":{"content":"ok"}}]}'


seen = []


def fake(req, timeout=None):
    del timeout
    seen.append(json.loads(req.data.decode()))
    return Resp()


with patch.object(mod.urllib.request, "urlopen", side_effect=fake):
    mod.api_call(
        "https://example.test",
        "k",
        "m",
        {},
        [{"role": "user", "content": "x"}],
        reasoning_effort="medium",
    )
    mod.api_call(
        "https://example.test",
        "k",
        "m",
        {},
        [{"role": "user", "content": "x"}],
    )

assert seen[0]["reasoning_effort"] == "medium", seen
assert "reasoning_effort" not in seen[1], seen
assert mod.normalize_reasoning_effort("xhigh") == "high"
assert mod.normalize_reasoning_effort("max") == "high"
assert mod.normalize_reasoning_effort("medium") == "medium"

# A generic reasoning validation error must not be mistaken for rejection of
# the reasoning_effort field and retried without that field.
error = urllib.error.HTTPError(
    "https://example.test/chat/completions",
    400,
    "bad request",
    {},
    io.BytesIO(b'{"error":"reasoning trace is invalid"}'),
)
with patch.object(mod.urllib.request, "urlopen", side_effect=error) as mocked:
    try:
        mod.api_call(
            "https://example.test",
            "k",
            "m",
            {},
            [{"role": "user", "content": "x"}],
            reasoning_effort="medium",
            reasoning_policy="best_effort",
        )
    except RuntimeError:
        pass
    else:
        raise AssertionError("generic reasoning error unexpectedly triggered fallback")
assert mocked.call_count == 1, mocked.call_count

print("PASS test-openai-reasoning-payload")
