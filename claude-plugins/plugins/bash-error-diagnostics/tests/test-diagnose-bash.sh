#!/usr/bin/env bash
# test-diagnose-bash.sh - Tests for the bash error diagnostics hook
#
# Usage: bash plugins/bash-error-diagnostics/tests/test-diagnose-bash.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/diagnose-bash.sh"

PASS=0
FAIL=0
TOTAL=0

run_test() {
    local description="$1"
    local input="$2"
    local expected_pattern="$3"  # regex to match in output, or "EMPTY" for {}
    TOTAL=$((TOTAL + 1))

    local output
    output=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null) || true

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

echo "=== Bash Error Diagnostics Hook Tests ==="
echo ""

# ─── No-op cases (should return {}) ─────────────────────────────

run_test "Empty stdin" \
    "" \
    "EMPTY"

run_test "Simple command without pipe" \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "EMPTY"

run_test "Command with pipefail already set" \
    '{"tool_name":"Bash","tool_input":{"command":"set -o pipefail; cat file.txt | grep foo"}}' \
    "EMPTY"

run_test "No command field" \
    '{"tool_name":"Bash","tool_input":{}}' \
    "EMPTY"

run_test "Echo with pipe char in string but also pipefail" \
    '{"tool_name":"Bash","tool_input":{"command":"set -o pipefail; echo hello | wc"}}' \
    "EMPTY"

# ─── Detection cases (should inject context) ────────────────────

run_test "Simple pipe without pipefail" \
    '{"tool_name":"Bash","tool_input":{"command":"cat file.txt | grep pattern"}}' \
    "pipefail"

run_test "Multi-stage pipe" \
    '{"tool_name":"Bash","tool_input":{"command":"find . -name *.ts | xargs grep foo | wc -l"}}' \
    "pipefail"

run_test "Pipe with stderr redirect" \
    '{"tool_name":"Bash","tool_input":{"command":"make 2>/dev/null | tail -5"}}' \
    "stderr is redirected"

run_test "Pipe with || true" \
    '{"tool_name":"Bash","tool_input":{"command":"cat missing.txt | grep x || true"}}' \
    "masks the exit code"

run_test "Pipe with 2>&1 merge" \
    '{"tool_name":"Bash","tool_input":{"command":"npm test 2>&1 | head -20"}}' \
    "stderr is merged"

run_test "Returns valid JSON" \
    '{"tool_name":"Bash","tool_input":{"command":"cat file | head"}}' \
    "hookSpecificOutput"

run_test "Uses allow permission" \
    '{"tool_name":"Bash","tool_input":{"command":"ls | wc"}}' \
    "permissionDecision.*allow"

# ─── Edge cases ─────────────────────────────────────────────────

run_test "Command with || (no pipe for data)" \
    '{"tool_name":"Bash","tool_input":{"command":"test -f file || echo missing"}}' \
    "EMPTY"

# ─── Summary ────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
