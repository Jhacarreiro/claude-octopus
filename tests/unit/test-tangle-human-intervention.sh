#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle human intervention"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
log() { :; }

case_dir="$TEST_TMP_DIR/exact"
mkdir -p "$case_dir/results" "$case_dir/out"
cat > "$case_dir/results/codex-tangle-current-task-1.md" <<'MD'
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
TASK_GROUP="current-task"

test_case "exact structured block writes intervention.json"
if tangle_detect_human_intervention "$TASK_GROUP" && jq -e '.schemaVersion == 1 and .kind == "human_decision" and .question == "Choose Firebase beta project A or B?" and (.options == ["Project A","Project B"]) and .recommendedOption == "Project A"' "$OCTOPUS_HUMAN_INTERVENTION_PATH" >/dev/null; then
  test_pass
else
  test_fail "structured intervention was not materialized correctly"
fi

test_case "intervention artifact is private and records source result"
mode=$(ls -ld "$OCTOPUS_HUMAN_INTERVENTION_PATH" | awk '{print $1}')
if [[ "$mode" == "-rw-------" ]] && jq -e '.sourceResult | endswith("codex-tangle-current-task-1.md")' "$OCTOPUS_HUMAN_INTERVENTION_PATH" >/dev/null; then
  test_pass
else
  test_fail "artifact permissions/source evidence invalid"
fi

case_dir="$TEST_TMP_DIR/free-text"
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
if ! tangle_detect_human_intervention "$TASK_GROUP" && [[ ! -e "$OCTOPUS_HUMAN_INTERVENTION_PATH" ]]; then
  test_pass
else
  test_fail "ordinary blocker text incorrectly triggered intervention"
fi

case_dir="$TEST_TMP_DIR/malformed"
mkdir -p "$case_dir/results" "$case_dir/out"
cat > "$case_dir/results/tangle-malformed.md" <<'MD'
## Human Intervention Required
Context: Missing mandatory Question field.
Options: A | B
MD
export RESULTS_DIR="$case_dir/results"
export OCTOPUS_HUMAN_INTERVENTION_PATH="$case_dir/out/intervention.json"

test_case "malformed intervention block without Question is ignored"
if ! tangle_detect_human_intervention "$TASK_GROUP" && [[ ! -e "$OCTOPUS_HUMAN_INTERVENTION_PATH" ]]; then
  test_pass
else
  test_fail "malformed block should not create an intervention artifact"
fi

test_case "intervention detection ignores results from another task group"
case_dir="$TEST_TMP_DIR/task-group"
mkdir -p "$case_dir/results" "$case_dir/out"
cat > "$case_dir/results/agy-tangle-older-task-1.md" <<'MD'
## Human Intervention Required
Question: Stale task must not pause this run.
MD
export RESULTS_DIR="$case_dir/results"
export OCTOPUS_HUMAN_INTERVENTION_PATH="$case_dir/out/intervention.json"
if ! tangle_detect_human_intervention "current-task" && [[ ! -e "$OCTOPUS_HUMAN_INTERVENTION_PATH" ]]; then
  test_pass
else
  test_fail "an earlier task group incorrectly triggered intervention"
fi

test_summary
