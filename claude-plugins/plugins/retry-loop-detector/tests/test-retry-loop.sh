#!/usr/bin/env bash
# test-retry-loop.sh - Tests for retry loop detection hook
#
# Runs the hook script with various inputs and verifies correct behavior.
# Exit code 0 = all tests pass, non-zero = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../hooks/detect-retry-loop.sh"

# Use isolated temp directory for test state
TEST_TMPDIR="${TMPDIR:-/tmp}/retry-loop-test-$$"
mkdir -p "$TEST_TMPDIR"
export TMPDIR="$TEST_TMPDIR"

PASS=0
FAIL=0

cleanup() {
    rm -rf "$TEST_TMPDIR"
}
trap cleanup EXIT

assert_contains() {
    local label="$1" output="$2" expected="$3"
    if [[ "$output" == *"$expected"* ]]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n    Expected to contain: %s\n    Got: %s\n" "$label" "$expected" "$output"
    fi
}

assert_empty_hook() {
    local label="$1" output="$2"
    if [ "$output" = "{}" ] || [ -z "$output" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n    Expected empty/no-op output\n    Got: %s\n" "$label" "$output"
    fi
}

run_hook() {
    printf '%s' "$1" | bash "$HOOK_SCRIPT" 2>/dev/null
}

reset_state() {
    rm -f "${TEST_TMPDIR}"/claude-retry-loop-detector-*.state
    rm -f "${TEST_TMPDIR}"/claude-retry-loop-detector-*.log
}

make_input() {
    local tool="$1" args="$2"
    printf '{"tool_name":"%s","tool_input":%s}' "$tool" "$args"
}

# ================================================================
echo "=== Test Suite: Retry Loop Detector ==="
echo ""

# ---- Test 1: Different tools pass without warning ----
echo "Test 1: Different tools pass without warning"
reset_state
OUT=$(run_hook "$(make_input "Read" '{"file_path":"/tmp/a.txt"}')")
assert_empty_hook "1st Read call" "$OUT"
OUT=$(run_hook "$(make_input "Grep" '{"pattern":"foo"}')")
assert_empty_hook "Grep call (different tool resets)" "$OUT"

# ---- Test 2: First two identical calls pass ----
echo ""
echo "Test 2: First two identical calls pass without warning"
reset_state
OUT=$(run_hook "$(make_input "Read" '{"file_path":"/tmp/test.txt"}')")
assert_empty_hook "1st identical call" "$OUT"
OUT=$(run_hook "$(make_input "Read" '{"file_path":"/tmp/test.txt"}')")
assert_empty_hook "2nd identical call" "$OUT"

# ---- Test 3: 3rd call triggers warning ----
echo ""
echo "Test 3: Third identical call triggers warning"
reset_state
run_hook "$(make_input "Bash" '{"command":"ls /nonexistent"}')" >/dev/null
run_hook "$(make_input "Bash" '{"command":"ls /nonexistent"}')" >/dev/null
OUT=$(run_hook "$(make_input "Bash" '{"command":"ls /nonexistent"}')")
assert_contains "3rd call warns" "$OUT" "WARNING"
assert_contains "3rd call mentions tool" "$OUT" "Bash"
assert_contains "3rd call shows count" "$OUT" "3 times"
assert_contains "3rd call allows" "$OUT" "allow"

# ---- Test 4: 5th call triggers block ----
echo ""
echo "Test 4: Fifth identical call triggers block"
reset_state
for _i in 1 2 3 4; do
    run_hook "$(make_input "Grep" '{"pattern":"error","path":"/var/log"}')" >/dev/null
done
OUT=$(run_hook "$(make_input "Grep" '{"pattern":"error","path":"/var/log"}')")
assert_contains "5th call blocks" "$OUT" "BLOCKED"
assert_contains "5th call shows count" "$OUT" "5 times"

# ---- Test 5: Same tool, different args resets counter ----
echo ""
echo "Test 5: Same tool with different args resets counter"
reset_state
run_hook "$(make_input "Read" '{"file_path":"/tmp/a.txt"}')" >/dev/null
run_hook "$(make_input "Read" '{"file_path":"/tmp/a.txt"}')" >/dev/null
OUT=$(run_hook "$(make_input "Read" '{"file_path":"/tmp/b.txt"}')")
assert_empty_hook "Different args resets counter" "$OUT"
OUT=$(run_hook "$(make_input "Read" '{"file_path":"/tmp/b.txt"}')")
assert_empty_hook "2nd call with new args still fine" "$OUT"

# ---- Test 6: Escape hatch ----
echo ""
echo "Test 6: Escape hatch disables detection"
reset_state
run_hook "$(make_input "Bash" '{"command":"failing-cmd"}')" >/dev/null
run_hook "$(make_input "Bash" '{"command":"failing-cmd"}')" >/dev/null
export DISABLE_RETRY_LOOP_DETECTOR=1
OUT=$(run_hook "$(make_input "Bash" '{"command":"failing-cmd"}')")
assert_empty_hook "Escape hatch suppresses warning" "$OUT"
unset DISABLE_RETRY_LOOP_DETECTOR

# ---- Test 7: Empty/malformed input ----
echo ""
echo "Test 7: Empty and malformed input handled gracefully"
reset_state
OUT=$(echo "" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_empty_hook "Empty input" "$OUT"
OUT=$(echo "not json at all" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_empty_hook "Malformed input" "$OUT"

# ---- Test 8: Retry events are logged ----
echo ""
echo "Test 8: Retry events are logged"
reset_state
for _i in 1 2 3; do
    run_hook "$(make_input "Edit" '{"file_path":"/tmp/x","old_string":"a","new_string":"b"}')" >/dev/null
done
HOSTNAME_SAFE=$(hostname -s 2>/dev/null | tr -cd 'a-zA-Z0-9_.-' || echo "local")
LOG_FILE="${TEST_TMPDIR}/claude-retry-loop-detector-${HOSTNAME_SAFE}.log"
if [ -f "$LOG_FILE" ]; then
    assert_contains "Log entry exists" "$(cat "$LOG_FILE")" "[RETRY]"
    assert_contains "Log has tool name" "$(cat "$LOG_FILE")" "tool=Edit"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: Log file not created\n"
fi

# ---- Test 9: Counter persists across different tools then same tool ----
echo ""
echo "Test 9: Interleaved tools reset properly"
reset_state
run_hook "$(make_input "Read" '{"file_path":"/tmp/a.txt"}')" >/dev/null
run_hook "$(make_input "Read" '{"file_path":"/tmp/a.txt"}')" >/dev/null
run_hook "$(make_input "Write" '{"file_path":"/tmp/b.txt","content":"x"}')" >/dev/null
# Read again with same args -- count should be 1, not 3
OUT=$(run_hook "$(make_input "Read" '{"file_path":"/tmp/a.txt"}')")
assert_empty_hook "Counter resets after different tool" "$OUT"

# ---- Test 10: Warning at exactly threshold, not before ----
echo ""
echo "Test 10: No warning at count 2, warning at count 3"
reset_state
run_hook "$(make_input "Glob" '{"pattern":"**/*.ts"}')" >/dev/null
OUT=$(run_hook "$(make_input "Glob" '{"pattern":"**/*.ts"}')")
assert_empty_hook "Count 2 is silent" "$OUT"
OUT=$(run_hook "$(make_input "Glob" '{"pattern":"**/*.ts"}')")
assert_contains "Count 3 warns" "$OUT" "WARNING"

# ---- Summary ----
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
