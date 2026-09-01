#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle verification signals"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

for signal in INT TERM; do
    test_case "verification cleanup invokes saved $signal trap and cannot resume"
    marker="$TEST_TMP_DIR/caller-${signal}.marker"
    continued="$TEST_TMP_DIR/continued-${signal}.marker"
    child="$TEST_TMP_DIR/verify-${signal}.sh"
    cat > "$child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
WORKFLOWS="$1"
MARKER="$2"
CONTINUED="$3"
SIGNAL="$4"
source "$WORKFLOWS"
log() { :; }
trap 'printf "caller-signal\n" > "$MARKER"' "$SIGNAL"
TANGLE_VERIFY_PREV_EXIT_TRAP=$(trap -p EXIT)
TANGLE_VERIFY_PREV_INT_TRAP=$(trap -p INT)
TANGLE_VERIFY_PREV_TERM_TRAP=$(trap -p TERM)
trap "tangle_handle_verification_signal $SIGNAL" "$SIGNAL"
kill -s "$SIGNAL" "$$"
printf 'resumed\n' > "$CONTINUED"
CHILD
    chmod +x "$child"
    set +e
    bash "$child" "$WORKFLOWS" "$marker" "$continued" "$signal"
    rc=$?
    set -e
    expected=143
    [[ "$signal" == "INT" ]] && expected=130
    if [[ "$rc" -eq "$expected" ]] && [[ -f "$marker" ]] && [[ ! -e "$continued" ]]; then
        test_pass
    else
        test_fail "$signal handler rc=$rc expected=$expected marker=$(test -f "$marker" && echo yes || echo no) continued=$(test -e "$continued" && echo yes || echo no)"
    fi
done

test_summary
