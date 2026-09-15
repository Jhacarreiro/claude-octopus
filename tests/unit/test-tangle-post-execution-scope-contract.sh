#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT_SRC/scripts/lib/testing.sh"
source "$PROJECT_ROOT_SRC/scripts/lib/workflows.sh"

test_suite "tangle post-execution write scope contract"

TMP_ROOT="$TEST_TMP_DIR"
TMP_REPO="$TMP_ROOT/repo"
TMP_RESULTS="$TMP_ROOT/results"
mkdir -p "$TMP_REPO/src" "$TMP_RESULTS"
git -C "$TMP_REPO" init -q
git -C "$TMP_REPO" config user.email test@example.com
git -C "$TMP_REPO" config user.name Test
printf '%s\n' 'export const baseline = true;' > "$TMP_REPO/src/existing.ts"
printf '%s\n' '{"name":"fixture"}' > "$TMP_REPO/package.json"
git -C "$TMP_REPO" add src/existing.ts package.json
git -C "$TMP_REPO" commit -qm baseline

PROJECT_ROOT="$TMP_REPO"
RESULTS_DIR="$TMP_RESULTS"
export PROJECT_ROOT RESULTS_DIR
BEFORE="$RESULTS_DIR/before.txt"
snapshot_tangle_worktree_paths > "$BEFORE" || true
BEFORE_STATE="$RESULTS_DIR/before-state.txt"
snapshot_tangle_worktree_state > "$BEFORE_STATE" || true

SUBTASKS='1. [CODING] Build UI — Reads: src/existing.ts — Files: package.json — Creates: web/ — Task: build the new UI without modifying the read-only source module.'

mkdir -p "$TMP_REPO/web/js"
printf '%s\n' 'console.log("ok")' > "$TMP_REPO/web/js/app.js"
printf '%s\n' '{"name":"fixture","scripts":{"build":"true"}}' > "$TMP_REPO/package.json"
printf '%s\n' 'export const baseline = false;' > "$TMP_REPO/src/existing.ts"

test_case "Reads paths are excluded from authorized write scopes"
write_scopes=$(tangle_authorized_write_scopes "$SUBTASKS")
read_scopes=$(tangle_authorized_read_scopes "$SUBTASKS")
if [[ "$write_scopes" == *"package.json"* ]] && [[ "$write_scopes" == *"web"* ]] && [[ "$write_scopes" != *"src/existing.ts"* ]] && [[ "$read_scopes" == "src/existing.ts" ]]; then
    test_pass
else
    test_fail "unexpected scope extraction: writes=[$write_scopes] reads=[$read_scopes]"
fi

test_case "Task prose labels do not override declared scope clauses"
SUBTASKS_WITH_LABEL_PROSE='1. [CODING] Build UI — Files: package.json — Creates: web/ — Reads: src/existing.ts — Task: explain why Files: src/decoy.ts, Creates: tmp/decoy/, and Reads: secrets.txt are not scope declarations.'
actual_files=$(tangle_raw_scope_clause "$SUBTASKS_WITH_LABEL_PROSE" "Files")
actual_creates=$(tangle_raw_scope_clause "$SUBTASKS_WITH_LABEL_PROSE" "Creates")
actual_reads=$(tangle_raw_scope_clause "$SUBTASKS_WITH_LABEL_PROSE" "Reads")
if [[ "$actual_files" == "package.json" ]] && \
   [[ "$actual_creates" == "web/" ]] && \
   [[ "$actual_reads" == "src/existing.ts" ]]; then
    test_pass
else
    test_fail "Task prose overrode declared scope: Files=[$actual_files] Creates=[$actual_creates] Reads=[$actual_reads]"
fi

test_case "Task-only scope labels do not grant write authorization"
TASK_ONLY_LABEL='1. [CODING] Explain scope — Reads: src/existing.ts — Task: document why Files: src/decoy.ts must remain untouched.'
if [[ -z "$(tangle_raw_scope_clause "$TASK_ONLY_LABEL" "Files")" ]]; then
    test_pass
else
    test_fail "Task prose was parsed as a Files declaration"
fi

test_case "post-execution scope check flags writes to Reads paths"
violations=$(tangle_changed_paths_outside_write_scopes "$SUBTASKS" "$BEFORE")
if [[ "$violations" == "src/existing.ts" ]]; then
    test_pass
else
    test_fail "expected only src/existing.ts violation; got: $violations"
fi

test_case "nested Creates and exact Files paths remain authorized"
if [[ "$violations" != *"web/js/app.js"* ]] && [[ "$violations" != *"package.json"* ]]; then
    test_pass
else
    test_fail "authorized paths were incorrectly reported: $violations"
fi

# Isolate the wrapper from the existing quality gate; this suite specifically
# verifies the deterministic scope contract and whether the base gate is invoked.
VALIDATE_CALLS=0
validate_tangle_results() {
    local task_group="$1"
    VALIDATE_CALLS=$((VALIDATE_CALLS + 1))
    printf '%s\n' '# baseline validation' > "$RESULTS_DIR/tangle-validation-${task_group}.md"
    return 0
}
log() { :; }

test_case "validation wrapper fails and records out-of-scope changed paths"
status=0
tangle_validate_results_with_scope_contract fixture 'Build UI' "$BEFORE" "$SUBTASKS" || status=$?
report="$RESULTS_DIR/tangle-validation-fixture.md"
if [[ "$status" -ne 0 ]] && [[ "$VALIDATE_CALLS" -eq 0 ]] && grep -q 'deterministic write-scope pre-gate' "$report" && grep -q 'FAILED: Out-of-Scope Worktree Changes' "$report" && grep -q -- '- src/existing.ts' "$report" && grep -q 'Reads: never grants write permission' "$report"; then
    test_pass
else
    test_fail "scope violation did not fail before base validation/retries; calls=$VALIDATE_CALLS"
fi

test_case "adaptive mode records out-of-scope changes as evidence and still runs base validation"
VALIDATE_CALLS=0
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
export TANGLE_WORKTREE_BEFORE_STATE_DIGEST
TANGLE_WORKTREE_BEFORE_STATE_DIGEST=$(tangle_file_digest "$BEFORE_STATE")
adaptive_status=0
tangle_validate_results_with_scope_contract adaptive 'Build UI' "$BEFORE" "$SUBTASKS" "" "" "$BEFORE_STATE" || adaptive_status=$?
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
adaptive_report="$RESULTS_DIR/tangle-validation-adaptive.md"
if [[ "$adaptive_status" -eq 0 ]] && [[ "$VALIDATE_CALLS" -eq 1 ]] && grep -q 'Adaptive Write Scope Expansions' "$adaptive_report" && grep -q -- '- src/existing.ts' "$adaptive_report" && grep -q 'PASS: adaptive scope expansion paths passed safety checks.' "$adaptive_report" && ! grep -q 'parent-owned snapshot and scope-manifest integrity checks passed.' "$adaptive_report" && [[ "${TANGLE_SCOPE_EXPANSION_EVIDENCE:-}" == *"src/existing.ts"* ]] && [[ -z "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" ]]; then
    test_pass
else
    test_fail "adaptive scope expansion remained fatal or lost evidence; status=$adaptive_status calls=$VALIDATE_CALLS"
fi
VALIDATE_CALLS=0

test_case "adaptive mode keeps unconfirmed symlink expansions fatal"
adaptive_escape_target="$TMP_ROOT/adaptive-escape-target"
mkdir -p "$adaptive_escape_target"
ln -s "$adaptive_escape_target" "$TMP_REPO/adaptive-escape"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
adaptive_status=0
tangle_validate_results_with_scope_contract adaptive-unsafe 'Build UI' "$BEFORE" "$SUBTASKS" "" "" "$BEFORE_STATE" || adaptive_status=$?
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
adaptive_unsafe_report="$RESULTS_DIR/tangle-validation-adaptive-unsafe.md"
if [[ "$adaptive_status" -ne 0 ]] && [[ "$VALIDATE_CALLS" -eq 0 ]] && \
   [[ "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" == *"could not be confirmed safe"* ]] && \
   [[ "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" == *"adaptive-escape"* ]] && \
   [[ "${TANGLE_SCOPE_EXPANSION_EVIDENCE:-}" != *"adaptive-escape"* ]] && \
   grep -q 'FAILED: Out-of-Scope Worktree Changes' "$adaptive_unsafe_report"; then
    test_pass
else
    test_fail "adaptive mode allowed an unconfirmed symlink expansion; status=$adaptive_status calls=$VALIDATE_CALLS"
fi
rm -f "$TMP_REPO/adaptive-escape"
VALIDATE_CALLS=0

test_case "adaptive mode requires a valid parent-owned state snapshot"
missing_state="$RESULTS_DIR/missing-state.txt"
rm -f "$missing_state"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
status=0
tangle_validate_results_with_scope_contract missing-state 'Build UI' "$BEFORE" "$SUBTASKS" "" "" "$missing_state" || status=$?
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
if [[ "$status" -ne 0 ]] && [[ "$VALIDATE_CALLS" -eq 0 ]] && [[ "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" == *"missing or invalid"* ]]; then
    test_pass
else
    test_fail "adaptive mode accepted a missing parent-owned state snapshot; status=$status"
fi
VALIDATE_CALLS=0

test_case "parent-owned state snapshot validator rejects partial snapshots"
partial_state="$RESULTS_DIR/partial-state.txt"
printf '%s\n' '## unstaged' '## staged' '## untracked' > "$partial_state"
if ! tangle_parent_owned_state_snapshot_is_valid "$partial_state"; then
    test_pass
else
    test_fail "partial parent-owned state snapshot was accepted"
fi

test_case "adaptive mode keeps parent-owned snapshot integrity failures fatal"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
export TANGLE_WORKTREE_BEFORE_STATE_DIGEST=deliberately-wrong
status=0
tangle_validate_results_with_scope_contract snapshot-integrity 'Build UI' "$BEFORE" "$SUBTASKS" "" "" "$BEFORE" || status=$?
unset TANGLE_WORKTREE_BEFORE_STATE_DIGEST OCTOPUS_TANGLE_WRITE_SCOPE_MODE
if [[ "$status" -ne 0 ]] && [[ "$VALIDATE_CALLS" -eq 0 ]] && [[ "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" == *"parent-owned worktree state snapshot"* ]]; then
    test_pass
else
    test_fail "adaptive mode cleared a parent-owned snapshot integrity failure; status=$status"
fi

test_case "adaptive mode keeps scope-manifest integrity failures fatal"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
status=0
tangle_validate_results_with_scope_contract manifest-integrity 'Build UI' "$BEFORE" "$SUBTASKS" "" deliberately-wrong "$BEFORE" || status=$?
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
if [[ "$status" -ne 0 ]] && [[ "$VALIDATE_CALLS" -eq 0 ]] && [[ "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" == *"parent-owned scope manifest"* ]]; then
    test_pass
else
    test_fail "adaptive mode cleared a scope-manifest integrity failure; status=$status"
fi

test_case "scope violation is surfaced as one deterministic blocking finding"
findings="$TMP_ROOT/findings.json"
printf '%s\n' '{"findings":[]}' > "$findings"
tangle_ensure_scope_contract_finding "$findings" "$violations"
tangle_ensure_scope_contract_finding "$findings" "$violations"
count=$(jq '[.findings[] | select(.category == "scope-contract" and .severity == "normal" and .verdict == "confirmed")] | length' "$findings")
file=$(jq -r '.findings[] | select(.category == "scope-contract") | .file' "$findings")
if [[ "$count" -eq 1 ]] && [[ "$file" == "src/existing.ts" ]]; then
    test_pass
else
    test_fail "expected one deterministic scope-contract finding; count=$count file=$file"
fi

test_case "validation wrapper passes after illegal write is reverted"
git -C "$TMP_REPO" checkout -- src/existing.ts
status=0
tangle_validate_results_with_scope_contract repaired 'Build UI' "$BEFORE" "$SUBTASKS" || status=$?
report="$RESULTS_DIR/tangle-validation-repaired.md"
if [[ "$status" -eq 0 ]] && [[ "$VALIDATE_CALLS" -eq 1 ]] && grep -q '# baseline validation' "$report" && grep -q 'PASS: every changed path' "$report" && [[ -z "${TANGLE_SCOPE_CONTRACT_VIOLATIONS:-}" ]]; then
    test_pass
else
    test_fail "scope contract did not clear or base validation was not restored; calls=$VALIDATE_CALLS"
fi


test_case "multiple scope violations are separated by real newlines"
violations=$'src/existing.ts\nThe parent-owned scope manifest changed before final validation.'
report="$RESULTS_DIR/newline-report.md"
: > "$report"
tangle_append_write_scope_contract_report "$report" "package.json" "src/existing.ts" "$violations" ""
if grep -Fxq -- '- src/existing.ts' "$report" && \
   grep -Fxq -- '- The parent-owned scope manifest changed before final validation.' "$report" && \
   ! grep -Fq '\n' "$report"; then
    test_pass
else
    test_fail "scope violations were not rendered as distinct lines"
fi

test_summary
