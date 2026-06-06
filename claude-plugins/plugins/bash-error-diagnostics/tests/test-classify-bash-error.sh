#!/usr/bin/env bash
# test-classify-bash-error.sh - Tests for the PostToolUse Bash error classifier
#
# Usage: bash plugins/bash-error-diagnostics/tests/test-classify-bash-error.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/classify-bash-error.sh"

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

echo "=== Bash Error Classifier (PostToolUse) Tests ==="
echo ""

# ─── No-op cases ────────────────────────────────────────────────

run_test "Empty stdin" "" "EMPTY"

run_test "Non-Bash tool" \
    '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"tool_result":"contents"}' \
    "EMPTY"

run_test "Successful Bash command" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_result":"file1\nfile2"}' \
    "EMPTY"

run_test "Exit code 0" \
    '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_result":"Exit code: 0\nhi"}' \
    "EMPTY"

# ─── Error classification ───────────────────────────────────────

run_test "Command not found" \
    '{"tool_name":"Bash","tool_input":{"command":"foobar"},"tool_result":"bash: foobar: command not found\nExit code: 127"}' \
    "command_not_found"

run_test "Command not found - retry no" \
    '{"tool_name":"Bash","tool_input":{"command":"foobar"},"tool_result":"bash: foobar: command not found"}' \
    "Retry useful: No"

run_test "Permission denied" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /etc/shadow"},"tool_result":"cat: /etc/shadow: Permission denied\nExit code: 1"}' \
    "permission_denied"

run_test "File not found" \
    '{"tool_name":"Bash","tool_input":{"command":"cat missing.txt"},"tool_result":"cat: missing.txt: No such file or directory\nExit code: 1"}' \
    "file_not_found"

run_test "Network error" \
    '{"tool_name":"Bash","tool_input":{"command":"curl localhost:9999"},"tool_result":"curl: Connection refused\nExit code: 7"}' \
    "network"

run_test "Network retry maybe" \
    '{"tool_name":"Bash","tool_input":{"command":"curl localhost:9999"},"tool_result":"curl: Connection refused"}' \
    "Retry useful: Maybe"

run_test "Git error" \
    '{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_result":"fatal: not a git repository\nExit code: 128"}' \
    "git_error"

run_test "Syntax error" \
    '{"tool_name":"Bash","tool_input":{"command":"if then fi"},"tool_result":"bash: syntax error near unexpected token\nExit code: 2"}' \
    "syntax_error"

run_test "OOM/resource" \
    '{"tool_name":"Bash","tool_input":{"command":"big-process"},"tool_result":"Killed\nExit code: 137"}' \
    "resource"

# ─── Pipeline detection ─────────────────────────────────────────

run_test "Pipe in failed command - suggests pipefail" \
    '{"tool_name":"Bash","tool_input":{"command":"cat file | grep x | wc"},"tool_result":"cat: file: No such file or directory\nExit code: 1"}' \
    "pipe.*detected"

# ─── Subshell detection ─────────────────────────────────────────

run_test "Subshell in failed command" \
    '{"tool_name":"Bash","tool_input":{"command":"echo $(cat missing)"},"tool_result":"cat: missing: No such file or directory\nExit code: 1"}' \
    "Subshell"

# ─── Output format ──────────────────────────────────────────────

run_test "Returns valid hookSpecificOutput" \
    '{"tool_name":"Bash","tool_input":{"command":"bad"},"tool_result":"error: something failed\nExit code: 1"}' \
    "hookSpecificOutput"

run_test "Uses PostToolUse event name" \
    '{"tool_name":"Bash","tool_input":{"command":"bad"},"tool_result":"error: something failed"}' \
    "PostToolUse"

# ─── Summary ────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
