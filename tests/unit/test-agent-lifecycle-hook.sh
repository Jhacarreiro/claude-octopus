#!/usr/bin/env bash
# Regression coverage for optional agent lifecycle hooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/spawn.sh"

test_suite "agent lifecycle hook"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RESULTS_DIR="$TMP_DIR/results"
WORKSPACE_DIR="$TMP_DIR/workspace"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR"

cat > "$TMP_DIR/hook.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'argv=%s\n' "$1"
  printf 'event=%s\n' "$OCTOPUS_AGENT_HOOK_EVENT"
  printf 'agent=%s\n' "$OCTOPUS_AGENT_TYPE"
  printf 'task=%s\n' "$OCTOPUS_AGENT_TASK_ID"
  printf 'role=%s\n' "$OCTOPUS_AGENT_ROLE"
  printf 'phase=%s\n' "$OCTOPUS_AGENT_PHASE"
  printf 'pid=%s\n' "$OCTOPUS_AGENT_PID"
  printf 'result=%s\n' "$OCTOPUS_AGENT_RESULT_FILE"
  printf 'results_dir=%s\n' "$OCTOPUS_AGENT_RESULTS_DIR"
  printf 'workspace=%s\n' "$OCTOPUS_AGENT_WORKSPACE_DIR"
  printf 'exit=%s\n' "$OCTOPUS_AGENT_EXIT_CODE"
  printf 'status=%s\n' "$OCTOPUS_AGENT_STATUS"
  printf 'root=%s\n' "$OCTOPUS_AGENT_ROOT_SESSION_ID"
  printf 'parent=%s\n' "$OCTOPUS_AGENT_PARENT_SESSION_ID"
  printf 'preview=%s\n' "$OCTOPUS_AGENT_PROMPT_PREVIEW"
} >> "$HOOK_CAPTURE"
echo noisy stdout
echo noisy stderr >&2
HOOK
chmod +x "$TMP_DIR/hook.sh"

cat > "$TMP_DIR/fail-hook.sh" <<'HOOK'
#!/usr/bin/env bash
echo failing hook
exit 42
HOOK
chmod +x "$TMP_DIR/fail-hook.sh"

test_case "hook receives lifecycle metadata and redirects output"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/hook.sh"
export OCTOPUS_AGENT_LIFECYCLE_HOOK_LOG="$TMP_DIR/hook.log"
export HOOK_CAPTURE="$TMP_DIR/capture.txt"
export CRABFLEET_ROOT_SESSION_ID="IS-ROOT"
export CRABFLEET_PARENT_SESSION_ID="IS-PARENT"
prompt="Implement a very important subtask"
stdout="$(_octopus_agent_lifecycle_hook "spawned" "codex" "task-1" "developer" "tangle" "12345" "$RESULTS_DIR/codex-task-1.md" "" "running")"
if [[ -z "$stdout" ]] && \
   grep -q '^argv=spawned$' "$HOOK_CAPTURE" && \
   grep -q '^agent=codex$' "$HOOK_CAPTURE" && \
   grep -q '^task=task-1$' "$HOOK_CAPTURE" && \
   grep -q '^root=IS-ROOT$' "$HOOK_CAPTURE" && \
   grep -q '^parent=IS-PARENT$' "$HOOK_CAPTURE" && \
   grep -q '^preview=Implement a very important subtask$' "$HOOK_CAPTURE" && \
   grep -q 'noisy stdout' "$TMP_DIR/hook.log" && \
   grep -q 'noisy stderr' "$TMP_DIR/hook.log"; then
  test_pass
else
  test_fail "hook metadata/output redirection did not match expectations"
fi

test_case "hook failure is ignored"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/fail-hook.sh"
if _octopus_agent_lifecycle_hook "completed" "gemini" "task-2" "reviewer" "review" "222" "$RESULTS_DIR/gemini-task-2.md" "1" "failed"; then
  test_pass
else
  test_fail "hook failure should not fail agent lifecycle"
fi

test_case "missing hook is a no-op"
unset OCTOPUS_AGENT_LIFECYCLE_HOOK
if _octopus_agent_lifecycle_hook "spawned" "codex" "task-3" "developer" "tangle" "333" "$RESULTS_DIR/codex-task-3.md" "" "running"; then
  test_pass
else
  test_fail "unset hook should be a no-op"
fi

test_summary
