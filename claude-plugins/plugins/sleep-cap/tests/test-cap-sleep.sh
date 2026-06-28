#!/usr/bin/env bash
# test-cap-sleep.sh - Tests for the sleep-cap hook
#
# Usage: bash plugins/sleep-cap/tests/test-cap-sleep.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/cap-sleep.sh"

PASS=0
FAIL=0
TOTAL=0

run_test() {
    local description="$1"
    local input="$2"
    local expected_pattern="$3"  # regex to match in output, or "EMPTY" for {}
    local env_prefix="${4:-}"    # optional env var prefix
    TOTAL=$((TOTAL + 1))

    local output
    if [ -n "$env_prefix" ]; then
        # shellcheck disable=SC2086
        output=$(printf '%s' "$input" | env $env_prefix bash "$HOOK" 2>/dev/null) || true
    else
        output=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null) || true
    fi

    if [ "$expected_pattern" = "EMPTY" ]; then
        if [ "$output" = "{}" ]; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $description"
            echo "  Expected: {}"
            echo "  Got: $output"
        fi
    else
        if echo "$output" | grep -qE "$expected_pattern"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $description"
            echo "  Expected pattern: $expected_pattern"
            echo "  Got: $output"
        fi
    fi
}

echo "=== Sleep Cap Hook Tests ==="
echo ""

# ─── No-op cases (should return {}) ─────────────────────────────

run_test "Empty stdin" \
    "" \
    "EMPTY"

run_test "No sleep command" \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "EMPTY"

run_test "No command field" \
    '{"tool_name":"Bash","tool_input":{}}' \
    "EMPTY"

run_test "sleep 5 (under threshold)" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 5"}}' \
    "EMPTY"

run_test "sleep 30 && echo done (under threshold)" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 30 && echo done"}}' \
    "EMPTY"

run_test "sleep 60 (at threshold, not over)" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 60"}}' \
    "EMPTY"

# ─── Block cases (should block) ─────────────────────────────────

run_test "sleep 600 — blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 600"}}' \
    "permissionDecision.*block"

run_test "sleep 600 — shows duration" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 600"}}' \
    "600s.*exceeds"

run_test "sleep 600 — suggests run_in_background" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 600"}}' \
    "run_in_background"

run_test "sleep 10m — blocked (converts to 600s)" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 10m"}}' \
    "permissionDecision.*block"

run_test "sleep 1h — blocked (converts to 3600s)" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 1h"}}' \
    "permissionDecision.*block"

run_test "sleep 600s — blocked (with s suffix)" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 600s"}}' \
    "permissionDecision.*block"

run_test "while loop with sleep 300 — blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"while true; do echo checking; sleep 300; done"}}' \
    "permissionDecision.*block"

run_test "sleep in chain — sleep 120 && echo done — blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 120 && echo done"}}' \
    "permissionDecision.*block"

# ─── Override cases ──────────────────────────────────────────────

run_test "sleep-cap:ignore override passes" \
    '{"tool_name":"Bash","tool_input":{"command":"# sleep-cap:ignore\nsleep 600"}}' \
    "EMPTY"

run_test "SLEEP_CAP_THRESHOLD=900 — sleep 600 passes" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 600"}}' \
    "EMPTY" \
    "SLEEP_CAP_THRESHOLD=900"

run_test "SLEEP_CAP_THRESHOLD=30 — sleep 60 blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 60"}}' \
    "permissionDecision.*block" \
    "SLEEP_CAP_THRESHOLD=30"

# ─── Edge cases ──────────────────────────────────────────────────

run_test "Word 'sleep' in echo — not blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"echo need more sleep"}}' \
    "EMPTY"

run_test "sleep with number in echo string — not blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"echo \"sleep 300 is too long\""}}' \
    "EMPTY"

run_test "grep for sleep pattern — not blocked" \
    '{"tool_name":"Bash","tool_input":{"command":"grep \"sleep 600\" logfile.txt"}}' \
    "EMPTY"

run_test "Multiple sleeps — blocks on max" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 5 && sleep 300 && sleep 10"}}' \
    "permissionDecision.*block"

run_test "Returns valid JSON with hookSpecificOutput" \
    '{"tool_name":"Bash","tool_input":{"command":"sleep 600"}}' \
    "hookSpecificOutput"

# ─── Summary ────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
