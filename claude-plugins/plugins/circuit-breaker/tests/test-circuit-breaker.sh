#!/usr/bin/env bash
# test-circuit-breaker.sh - Tests for the circuit breaker hooks
#
# Usage: bash plugins/circuit-breaker/tests/test-circuit-breaker.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POST_HOOK="${SCRIPT_DIR}/../hooks/track-failure.sh"
PRE_HOOK="${SCRIPT_DIR}/../hooks/check-breaker.sh"

PASS=0
FAIL=0
TOTAL=0

# Use a unique temp dir per test run to isolate state
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

run_post() {
    # Run PostToolUse hook with isolated state
    printf '%s' "$2" | TMPDIR="$TEST_TMPDIR" CIRCUIT_BREAKER_PID="$1" bash "$POST_HOOK" 2>/dev/null
}

run_pre() {
    # Run PreToolUse hook with isolated state
    printf '%s' "$2" | TMPDIR="$TEST_TMPDIR" CIRCUIT_BREAKER_PID="$1" bash "$PRE_HOOK" 2>/dev/null
}

run_test() {
    local description="$1"
    local output="$2"
    local expected_pattern="$3"
    TOTAL=$((TOTAL + 1))

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

echo "=== Circuit Breaker Hook Tests ==="
echo ""

# ---- Test PID for isolation ----
TEST_PID="99901"
TEST_PID2="99902"

# ---- 1. Successful tool call - no state change ----
echo "--- Successful calls ---"

OUT=$(run_post "$TEST_PID" '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_result":"file1\nfile2"}')
run_test "Successful Bash - no output" "$OUT" "EMPTY"

OUT=$(run_pre "$TEST_PID" '{"tool_name":"Bash","tool_input":{"command":"ls"}}')
run_test "Pre-check after success - allowed" "$OUT" "EMPTY"

# ---- 2. First failure - logged but not blocked ----
echo ""
echo "--- First failure ---"

rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true

FAIL_INPUT='{"tool_name":"Bash","tool_input":{"command":"az account show"},"tool_result":"ERROR: Please run az login. Exit code: 1"}'
PRE_INPUT='{"tool_name":"Bash","tool_input":{"command":"az account show"}}'

OUT=$(run_post "$TEST_PID" "$FAIL_INPUT")
run_test "1st failure - not blocked, no trip warning" "$OUT" "EMPTY"

OUT=$(run_pre "$TEST_PID" "$PRE_INPUT")
run_test "Pre-check after 1st failure - still allowed" "$OUT" "EMPTY"

# ---- 3. Second failure - logged ----
echo ""
echo "--- Second failure ---"

OUT=$(run_post "$TEST_PID" "$FAIL_INPUT")
run_test "2nd failure - info message" "$OUT" "Consecutive failure #2"

OUT=$(run_pre "$TEST_PID" "$PRE_INPUT")
run_test "Pre-check after 2nd failure - still allowed" "$OUT" "EMPTY"

# ---- 4. Third failure - breaker trips ----
echo ""
echo "--- Third failure (trip) ---"

OUT=$(run_post "$TEST_PID" "$FAIL_INPUT")
run_test "3rd failure - trip warning" "$OUT" "Circuit Breaker"

OUT=$(run_pre "$TEST_PID" "$PRE_INPUT")
run_test "Pre-check after trip - BLOCKED" "$OUT" "CIRCUIT BREAKER TRIPPED"
run_test "Block message includes count" "$OUT" "failed [34] consecutive"
run_test "Block includes override hint" "$OUT" "circuit-breaker: override"

# ---- 5. Different fingerprint after trip - allowed ----
echo ""
echo "--- Different command after trip ---"

DIFF_PRE='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
OUT=$(run_pre "$TEST_PID" "$DIFF_PRE")
run_test "Different command - allowed despite tripped breaker" "$OUT" "EMPTY"

# ---- 6. Transient error (429) - does NOT count ----
echo ""
echo "--- Transient errors ---"

rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true

TRANSIENT_429='{"tool_name":"Bash","tool_input":{"command":"curl api.example.com"},"tool_result":"HTTP 429 Too Many Requests. Rate limit exceeded. Exit code: 1"}'
TRANSIENT_PRE='{"tool_name":"Bash","tool_input":{"command":"curl api.example.com"}}'

for _ in 1 2 3 4; do
    OUT=$(run_post "$TEST_PID" "$TRANSIENT_429")
done
run_test "4x 429 errors - no trip (transient allowlisted)" "$OUT" "EMPTY"

OUT=$(run_pre "$TEST_PID" "$TRANSIENT_PRE")
run_test "Pre-check after 4x 429 - still allowed" "$OUT" "EMPTY"

# ETIMEDOUT
rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true
TRANSIENT_TIMEOUT='{"tool_name":"Bash","tool_input":{"command":"curl slow.example.com"},"tool_result":"Error: ETIMEDOUT connecting to slow.example.com. Exit code: 1"}'
for _ in 1 2 3 4; do
    OUT=$(run_post "$TEST_PID" "$TRANSIENT_TIMEOUT")
done
run_test "4x ETIMEDOUT - no trip (transient)" "$OUT" "EMPTY"

# DNS resolution
rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true
TRANSIENT_DNS='{"tool_name":"Bash","tool_input":{"command":"curl bad.local"},"tool_result":"Error: getaddrinfo ENOTFOUND bad.local. Exit code: 1"}'
for _ in 1 2 3 4; do
    OUT=$(run_post "$TEST_PID" "$TRANSIENT_DNS")
done
run_test "4x DNS failure - no trip (transient)" "$OUT" "EMPTY"

# ECONNREFUSED
rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true
TRANSIENT_CONNREFUSED='{"tool_name":"Bash","tool_input":{"command":"curl localhost:9999"},"tool_result":"Error: ECONNREFUSED connecting to localhost:9999. Exit code: 1"}'
for _ in 1 2 3 4; do
    OUT=$(run_post "$TEST_PID" "$TRANSIENT_CONNREFUSED")
done
run_test "4x ECONNREFUSED - no trip (transient)" "$OUT" "EMPTY"

# ---- 7. Override bypass ----
echo ""
echo "--- Override bypass ---"

rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true

for _ in 1 2 3; do
    run_post "$TEST_PID" "$FAIL_INPUT" >/dev/null
done

OUT=$(run_pre "$TEST_PID" "$PRE_INPUT")
run_test "Breaker is tripped (setup for override test)" "$OUT" "CIRCUIT BREAKER TRIPPED"

OVERRIDE_PRE='{"tool_name":"Bash","tool_input":{"command":"# circuit-breaker: override\naz account show"}}'
OUT=$(run_pre "$TEST_PID" "$OVERRIDE_PRE")
run_test "Override prefix - bypasses breaker" "$OUT" "EMPTY"

# ---- 8. PID scoping - two PIDs don't interfere ----
echo ""
echo "--- PID isolation ---"

rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true

for _ in 1 2 3; do
    run_post "$TEST_PID" "$FAIL_INPUT" >/dev/null
done

OUT=$(run_pre "$TEST_PID" "$PRE_INPUT")
run_test "PID1 breaker tripped" "$OUT" "CIRCUIT BREAKER TRIPPED"

OUT=$(run_pre "$TEST_PID2" "$PRE_INPUT")
run_test "PID2 unaffected by PID1 breaker" "$OUT" "EMPTY"

# ---- 9. Reset after success ----
echo ""
echo "--- Reset after success ---"

rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true

run_post "$TEST_PID" "$FAIL_INPUT" >/dev/null
run_post "$TEST_PID" "$FAIL_INPUT" >/dev/null

SUCCESS_INPUT='{"tool_name":"Bash","tool_input":{"command":"az account show"},"tool_result":"{\n  \"name\": \"my-sub\"\n}"}'
run_post "$TEST_PID" "$SUCCESS_INPUT" >/dev/null

OUT=$(run_post "$TEST_PID" "$FAIL_INPUT")
run_test "After success reset, failure count restarts at 1" "$OUT" "EMPTY"

run_post "$TEST_PID" "$FAIL_INPUT" >/dev/null
OUT=$(run_post "$TEST_PID" "$FAIL_INPUT")
run_test "After reset, 3 new failures needed to trip" "$OUT" "Circuit Breaker"

# ---- 10. Non-Bash tools ----
echo ""
echo "--- Non-Bash tools ---"

rm -f "${TEST_TMPDIR}"/claude-circuit-breaker-* 2>/dev/null || true

EDIT_FAIL='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"},"tool_result":"Error: old_string not found in file. ENOENT"}'
EDIT_PRE='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"}}'

for _ in 1 2 3; do
    run_post "$TEST_PID" "$EDIT_FAIL" >/dev/null
done

OUT=$(run_pre "$TEST_PID" "$EDIT_PRE")
run_test "Edit tool - breaker trips after 3 failures" "$OUT" "CIRCUIT BREAKER TRIPPED"

# ---- 11. Empty/malformed input ----
echo ""
echo "--- Edge cases ---"

OUT=$(run_post "$TEST_PID" "")
run_test "Empty stdin to PostToolUse" "$OUT" "EMPTY"

OUT=$(run_pre "$TEST_PID" "")
run_test "Empty stdin to PreToolUse" "$OUT" "EMPTY"

OUT=$(run_post "$TEST_PID" "not json at all")
run_test "Malformed JSON to PostToolUse" "$OUT" "EMPTY"

OUT=$(run_pre "$TEST_PID" "not json at all")
run_test "Malformed JSON to PreToolUse" "$OUT" "EMPTY"

# ---- Summary ----
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
