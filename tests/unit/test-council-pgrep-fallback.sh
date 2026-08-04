#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"

test_suite "Council cancellation without pgrep"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
ln -s "$(command -v ps)" "$tmp/bin/ps"
ln -s "$(command -v sleep)" "$tmp/bin/sleep"

test_case "ps fallback enumerates direct children"
(
    sleep 5 &
    wait
) &
parent=$!
sleep 0.1
children=$(PATH="$tmp/bin"; _council_child_pids "$parent")
_council_cancel_tree "$parent"
wait "$parent" 2>/dev/null || true
if [[ -n "$children" ]]; then test_pass; else test_fail "ps fallback found no child"; fi

test_case "cancellation remains race-free when pgrep is unavailable"
(
    trap '' HUP INT TERM
    trap 'exit 143' USR1
    (
        /bin/sleep 3
        : > "$tmp/child.mark"
    ) &
    echo $! > "$tmp/child.pid"
    /bin/sleep 3
    : > "$tmp/late.response"
) &
seat=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$tmp/child.pid" ]] && break
    /bin/sleep 0.05
done
child=$(cat "$tmp/child.pid")
( PATH="$tmp/bin"; _council_cancel_tree "$seat" )
wait "$seat" 2>/dev/null || true
/bin/sleep 0.3
seat_alive=no
child_alive=no
kill -0 "$seat" 2>/dev/null && seat_alive=yes
kill -0 "$child" 2>/dev/null && child_alive=yes
if [[ "$seat_alive" == no && "$child_alive" == no && ! -e "$tmp/child.mark" && ! -e "$tmp/late.response" ]]; then
    test_pass
else
    test_fail "seat=$seat_alive child=$child_alive marker=$([[ -e "$tmp/child.mark" ]] && echo yes || echo no) late=$([[ -e "$tmp/late.response" ]] && echo yes || echo no)"
fi

test_summary
