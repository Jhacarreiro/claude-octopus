#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/workflows.sh"
log() { :; }

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
PASS=0
FAIL=0

test_case() { printf '  %-72s' "$1"; }
test_pass() { echo 'PASS'; PASS=$((PASS+1)); }
test_fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

case_dir="$TEST_ROOT/exact"
mkdir -p "$case_dir/results" "$case_dir/out"
cat > "$case_dir/results/tangle-auth.md" <<'MD'
## Worktree Changes
- None yet.

## Human Intervention Required
Question: Choose Firebase beta project A or B?
Context: Both are valid but the operator must select the real external project.
Options: Project A | Project B
Recommended: Project A

## Verification
- Paused before external configuration.
MD
export RESULTS_DIR="$case_dir/results"
export OCTOPUS_HUMAN_INTERVENTION_PATH="$case_dir/out/intervention.json"

test_case "exact structured block writes intervention.json"
if tangle_detect_human_intervention && jq -e '.schemaVersion == 1 and .kind == "human_decision" and .question == "Choose Firebase beta project A or B?" and (.options == ["Project A","Project B"]) and .recommendedOption == "Project A"' "$OCTOPUS_HUMAN_INTERVENTION_PATH" >/dev/null; then
  test_pass
else
  test_fail "structured intervention was not materialized correctly"
fi

test_case "intervention artifact is private and records source result"
mode=$(ls -ld "$OCTOPUS_HUMAN_INTERVENTION_PATH" | awk '{print $1}')
if [[ "$mode" == "-rw-------" ]] && jq -e '.sourceResult | endswith("tangle-auth.md")' "$OCTOPUS_HUMAN_INTERVENTION_PATH" >/dev/null; then
  test_pass
else
  test_fail "artifact permissions/source evidence invalid"
fi

case_dir="$TEST_ROOT/free-text"
mkdir -p "$case_dir/results" "$case_dir/out"
cat > "$case_dir/results/tangle-normal.md" <<'MD'
## Worktree Changes
- None.

## Verification
- Blocker: missing generated file; report a blocker and continue normal failure handling.
MD
export RESULTS_DIR="$case_dir/results"
export OCTOPUS_HUMAN_INTERVENTION_PATH="$case_dir/out/intervention.json"

test_case "free-text blocker does not trigger human intervention"
if ! tangle_detect_human_intervention && [[ ! -e "$OCTOPUS_HUMAN_INTERVENTION_PATH" ]]; then
  test_pass
else
  test_fail "ordinary blocker text incorrectly triggered intervention"
fi

case_dir="$TEST_ROOT/malformed"
mkdir -p "$case_dir/results" "$case_dir/out"
cat > "$case_dir/results/tangle-malformed.md" <<'MD'
## Human Intervention Required
Context: Missing mandatory Question field.
Options: A | B
MD
export RESULTS_DIR="$case_dir/results"
export OCTOPUS_HUMAN_INTERVENTION_PATH="$case_dir/out/intervention.json"

test_case "malformed intervention block without Question is ignored"
if ! tangle_detect_human_intervention && [[ ! -e "$OCTOPUS_HUMAN_INTERVENTION_PATH" ]]; then
  test_pass
else
  test_fail "malformed block should not create an intervention artifact"
fi

printf '\nPassed: %s  Failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
