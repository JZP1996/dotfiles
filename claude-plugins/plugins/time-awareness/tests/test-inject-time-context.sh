#!/usr/bin/env bash
# test-inject-time-context.sh - Tests for the inject-time-context.sh hook
#
# Runs a suite of tests verifying the hook correctly injects time context
# when opted-in and returns {} when not opted-in.
#
# Usage: bash tests/test-inject-time-context.sh

set -euo pipefail

# Resolve hook script path relative to this test file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../hooks/inject-time-context.sh"

PASS=0
FAIL=0
TOTAL=0

# Colors (if terminal supports them)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    NC=''
fi

assert_contains() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"
    TOTAL=$((TOTAL + 1))

    if echo "$actual" | grep -q "$expected"; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo "    Expected to contain: $expected"
        echo "    Actual: $actual"
    fi
}

assert_not_contains() {
    local test_name="$1"
    local actual="$2"
    local unexpected="$3"
    TOTAL=$((TOTAL + 1))

    if echo "$actual" | grep -q "$unexpected"; then
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo "    Expected NOT to contain: $unexpected"
        echo "    Actual: $actual"
    else
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
    fi
}

assert_equals() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"
    TOTAL=$((TOTAL + 1))

    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo "    Expected: $expected"
        echo "    Actual: $actual"
    fi
}

assert_valid_json() {
    local test_name="$1"
    local json_str="$2"
    TOTAL=$((TOTAL + 1))

    if command -v jq >/dev/null 2>&1; then
        if echo "$json_str" | jq . >/dev/null 2>&1; then
            PASS=$((PASS + 1))
            echo -e "  ${GREEN}PASS${NC}: $test_name (valid JSON)"
        else
            FAIL=$((FAIL + 1))
            echo -e "  ${RED}FAIL${NC}: $test_name (invalid JSON)"
            echo "    Output: $json_str"
        fi
    else
        # Without jq, do a basic check
        if [[ "$json_str" == "{"* ]] || [[ "$json_str" == "["* ]]; then
            PASS=$((PASS + 1))
            echo -e "  ${GREEN}PASS${NC}: $test_name (basic JSON check, jq not available)"
        else
            FAIL=$((FAIL + 1))
            echo -e "  ${RED}FAIL${NC}: $test_name (not JSON-like)"
            echo "    Output: $json_str"
        fi
    fi
}

# Create a temporary directory for test config files
TEST_DIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TEST_DIR'" EXIT

run_hook() {
    local input="$1"
    local home_override="${2:-$TEST_DIR/no-home}"
    printf '%s' "$input" | HOME="$home_override" bash "$HOOK_SCRIPT" 2>/dev/null
}

make_input() {
    local cwd="${1:-/tmp}"
    printf '{"tool_name": "Bash", "tool_input": {"command": "ls"}, "hook_event_name": "PreToolUse", "session_id": "test", "cwd": "%s", "tool_use_id": "test-123"}' "$cwd"
}

echo ""
echo "=== inject-time-context.sh Hook Tests ==="
echo ""

# ─── Opt-In Tests ─────────────────────────────────────────────────

echo "Opt-in behavior:"

# Test: Opted-in with config in HOME
mkdir -p "$TEST_DIR/home-optin"
echo '{"enabled": true}' > "$TEST_DIR/home-optin/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-optin")
assert_contains "Opted-in via HOME config returns time context" "$OUTPUT" "additionalContext"
assert_contains "Opted-in has permissionDecision=allow" "$OUTPUT" '"allow"'
assert_contains "Opted-in has hookEventName" "$OUTPUT" "hookEventName"
assert_contains "Opted-in has System time prefix" "$OUTPUT" "System time:"
assert_valid_json "Opted-in output is valid JSON" "$OUTPUT"

# Test: Opted-out (no config file)
mkdir -p "$TEST_DIR/no-config"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/no-config")
assert_equals "No config file returns empty JSON" "$OUTPUT" "{}"

# Test: Disabled (enabled: false)
mkdir -p "$TEST_DIR/home-disabled"
echo '{"enabled": false}' > "$TEST_DIR/home-disabled/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-disabled")
assert_equals "Disabled config returns empty JSON" "$OUTPUT" "{}"

# Test: Config in repo root (via cwd)
mkdir -p "$TEST_DIR/repo-root"
git -C "$TEST_DIR/repo-root" init --quiet 2>/dev/null || true
echo '{"enabled": true}' > "$TEST_DIR/repo-root/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input "$TEST_DIR/repo-root")" "$TEST_DIR/no-config")
assert_contains "Repo root config returns time context" "$OUTPUT" "additionalContext"

# Test: HOME config takes precedence over repo root
mkdir -p "$TEST_DIR/home-precedence"
echo '{"enabled": false}' > "$TEST_DIR/home-precedence/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input "$TEST_DIR/repo-root")" "$TEST_DIR/home-precedence")
assert_equals "HOME config takes precedence (disabled)" "$OUTPUT" "{}"

# ─── Timezone Tests ───────────────────────────────────────────────

echo ""
echo "Timezone handling:"

# Test: Custom timezone (UTC)
mkdir -p "$TEST_DIR/home-utc"
echo '{"enabled": true, "timezone": "UTC"}' > "$TEST_DIR/home-utc/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-utc")
assert_contains "UTC timezone returns time context" "$OUTPUT" "additionalContext"
assert_contains "UTC timezone contains UTC" "$OUTPUT" "UTC"
assert_valid_json "UTC timezone output is valid JSON" "$OUTPUT"

# Test: Custom timezone (America/New_York)
mkdir -p "$TEST_DIR/home-ny"
echo '{"enabled": true, "timezone": "America/New_York"}' > "$TEST_DIR/home-ny/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-ny")
assert_contains "America/New_York timezone returns time context" "$OUTPUT" "additionalContext"
assert_valid_json "America/New_York timezone output is valid JSON" "$OUTPUT"

# Test: Invalid timezone (graceful fallback to system default)
mkdir -p "$TEST_DIR/home-invalid-tz"
echo '{"enabled": true, "timezone": "Invalid/Timezone_XYZ"}' > "$TEST_DIR/home-invalid-tz/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-invalid-tz")
assert_contains "Invalid timezone still returns time context" "$OUTPUT" "additionalContext"
assert_valid_json "Invalid timezone output is valid JSON" "$OUTPUT"

# Test: Empty timezone string (uses system default)
mkdir -p "$TEST_DIR/home-empty-tz"
echo '{"enabled": true, "timezone": ""}' > "$TEST_DIR/home-empty-tz/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-empty-tz")
assert_contains "Empty timezone returns time context" "$OUTPUT" "additionalContext"
assert_valid_json "Empty timezone output is valid JSON" "$OUTPUT"

# ─── Format Tests ─────────────────────────────────────────────────

echo ""
echo "Format options:"

# Test: ISO format (default)
mkdir -p "$TEST_DIR/home-iso"
echo '{"enabled": true, "format": "iso"}' > "$TEST_DIR/home-iso/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-iso")
assert_contains "ISO format has date pattern" "$OUTPUT" "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"
assert_valid_json "ISO format output is valid JSON" "$OUTPUT"

# Test: Unix format
mkdir -p "$TEST_DIR/home-unix"
echo '{"enabled": true, "format": "unix"}' > "$TEST_DIR/home-unix/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-unix")
assert_contains "Unix format returns time context" "$OUTPUT" "additionalContext"
assert_contains "Unix format contains unix label" "$OUTPUT" "unix"
assert_valid_json "Unix format output is valid JSON" "$OUTPUT"

# Test: Unknown format falls back to iso
mkdir -p "$TEST_DIR/home-unknown-fmt"
echo '{"enabled": true, "format": "custom_bad"}' > "$TEST_DIR/home-unknown-fmt/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-unknown-fmt")
assert_contains "Unknown format falls back to iso" "$OUTPUT" "System time:"
assert_not_contains "Unknown format does not use unix" "$OUTPUT" "unix"
assert_valid_json "Unknown format output is valid JSON" "$OUTPUT"

# Test: No format specified defaults to iso
mkdir -p "$TEST_DIR/home-no-fmt"
echo '{"enabled": true}' > "$TEST_DIR/home-no-fmt/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-no-fmt")
assert_contains "Default format is iso" "$OUTPUT" "System time:"
assert_not_contains "Default format is not unix" "$OUTPUT" "unix"

# ─── Malformed Config Tests ───────────────────────────────────────

echo ""
echo "Malformed config handling:"

# Test: Malformed JSON config
mkdir -p "$TEST_DIR/home-malformed"
echo 'not valid json {{{' > "$TEST_DIR/home-malformed/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-malformed")
# Malformed JSON → use defaults (enabled=true, system TZ, iso format)
assert_contains "Malformed JSON uses defaults (still returns time)" "$OUTPUT" "additionalContext"
assert_valid_json "Malformed JSON output is still valid JSON" "$OUTPUT"

# Test: Empty config file
mkdir -p "$TEST_DIR/home-empty-config"
echo -n '' > "$TEST_DIR/home-empty-config/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-empty-config")
assert_equals "Empty config file returns empty JSON" "$OUTPUT" "{}"

# Test: Config with only whitespace
mkdir -p "$TEST_DIR/home-whitespace"
echo '   ' > "$TEST_DIR/home-whitespace/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-whitespace")
# Whitespace-only → jq fails → defaults, or bash regex finds nothing → defaults
assert_valid_json "Whitespace-only config output is valid JSON" "$OUTPUT"

# ─── Empty/Invalid Input Tests ────────────────────────────────────

echo ""
echo "Empty and invalid input:"

# Test: Empty stdin
mkdir -p "$TEST_DIR/home-stdin"
echo '{"enabled": true}' > "$TEST_DIR/home-stdin/.time-awareness.json"
OUTPUT=$(echo "" | HOME="$TEST_DIR/home-stdin" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_equals "Empty stdin returns empty JSON" "$OUTPUT" "{}"

# Test: No stdin at all
OUTPUT=$(HOME="$TEST_DIR/home-stdin" bash "$HOOK_SCRIPT" < /dev/null 2>/dev/null)
assert_equals "No stdin returns empty JSON" "$OUTPUT" "{}"

# Test: Invalid JSON on stdin
OUTPUT=$(printf 'not json' | HOME="$TEST_DIR/home-stdin" bash "$HOOK_SCRIPT" 2>/dev/null)
# Invalid JSON → cwd extraction fails → can't find repo root → uses HOME config
assert_valid_json "Invalid JSON stdin output is valid JSON" "$OUTPUT"

# ─── Security Edge Cases ─────────────────────────────────────────

echo ""
echo "Security edge cases:"

# Test: Prompt injection in timezone field
mkdir -p "$TEST_DIR/home-injection"
echo '{"enabled": true, "timezone": "UTC; echo INJECTED"}' > "$TEST_DIR/home-injection/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-injection")
assert_not_contains "Prompt injection in timezone is rejected" "$OUTPUT" "INJECTED"
assert_valid_json "Prompt injection output is valid JSON" "$OUTPUT"

# Test: Shell metacharacters in timezone
mkdir -p "$TEST_DIR/home-metachar"
# shellcheck disable=SC2016
echo '{"enabled": true, "timezone": "$(whoami)"}' > "$TEST_DIR/home-metachar/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-metachar")
assert_not_contains "Shell metachar in timezone is rejected" "$OUTPUT" "whoami"
assert_valid_json "Shell metachar output is valid JSON" "$OUTPUT"

# Test: Backtick injection in timezone
mkdir -p "$TEST_DIR/home-backtick"
# shellcheck disable=SC2016
printf '{"enabled": true, "timezone": "`whoami`"}' > "$TEST_DIR/home-backtick/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-backtick")
assert_not_contains "Backtick injection in timezone is rejected" "$OUTPUT" "whoami"
assert_valid_json "Backtick injection output is valid JSON" "$OUTPUT"

# Test: Control characters in config
# Control chars in a value that still parses as valid JSON don't cause rejection;
# the hook sanitizes the value or proceeds with defaults. Verify output is valid JSON
# and doesn't pass through the control character unsanitized.
mkdir -p "$TEST_DIR/home-control"
printf '{"enabled": true, "timezone": "UTC\x01"}' > "$TEST_DIR/home-control/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-control")
assert_valid_json "Control characters in config produces valid JSON" "$OUTPUT"
assert_not_contains "Control characters sanitized from output" "$OUTPUT" $'\x01'

# Test: Newline injection in timezone
mkdir -p "$TEST_DIR/home-newline-tz"
printf '{"enabled": true, "timezone": "UTC\\nINJECTED"}' > "$TEST_DIR/home-newline-tz/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-newline-tz")
assert_not_contains "Newline in timezone doesn't leak" "$OUTPUT" "INJECTED"
assert_valid_json "Newline injection output is valid JSON" "$OUTPUT"

# Test: Very long timezone string
mkdir -p "$TEST_DIR/home-long-tz"
LONG_TZ=$(printf 'A%.0s' {1..1000})
echo "{\"enabled\": true, \"timezone\": \"$LONG_TZ\"}" > "$TEST_DIR/home-long-tz/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-long-tz")
assert_valid_json "Very long timezone output is valid JSON" "$OUTPUT"

# ─── jq Fallback Tests ───────────────────────────────────────────

echo ""
echo "jq fallback (bash-only parsing):"

# Test: Simulate jq unavailability by creating a modified copy of the hook
# that replaces "command -v jq" with "false" to force the bash regex fallback
HOOK_NO_JQ="$TEST_DIR/inject-time-context-no-jq.sh"
sed 's/command -v jq/false/g' "$HOOK_SCRIPT" > "$HOOK_NO_JQ"
chmod +x "$HOOK_NO_JQ"

mkdir -p "$TEST_DIR/home-fallback"
echo '{"enabled": true, "timezone": "UTC", "format": "iso"}' > "$TEST_DIR/home-fallback/.time-awareness.json"
OUTPUT=$(printf '%s' "$(make_input /tmp)" | HOME="$TEST_DIR/home-fallback" bash "$HOOK_NO_JQ" 2>/dev/null)
assert_contains "jq fallback returns time context" "$OUTPUT" "additionalContext"
assert_valid_json "jq fallback output is valid JSON" "$OUTPUT"

# Test: jq fallback with disabled config
mkdir -p "$TEST_DIR/home-fallback-disabled"
echo '{"enabled": false}' > "$TEST_DIR/home-fallback-disabled/.time-awareness.json"
OUTPUT=$(printf '%s' "$(make_input /tmp)" | HOME="$TEST_DIR/home-fallback-disabled" bash "$HOOK_NO_JQ" 2>/dev/null)
assert_equals "jq fallback disabled returns empty JSON" "$OUTPUT" "{}"

# Test: jq fallback with unix format
mkdir -p "$TEST_DIR/home-fallback-unix"
echo '{"enabled": true, "format": "unix"}' > "$TEST_DIR/home-fallback-unix/.time-awareness.json"
OUTPUT=$(printf '%s' "$(make_input /tmp)" | HOME="$TEST_DIR/home-fallback-unix" bash "$HOOK_NO_JQ" 2>/dev/null)
assert_contains "jq fallback unix format returns time context" "$OUTPUT" "unix"
assert_valid_json "jq fallback unix format output is valid JSON" "$OUTPUT"

# Test: jq fallback with invalid timezone (validates regex path handles TZ validation)
mkdir -p "$TEST_DIR/home-fallback-badtz"
echo '{"enabled": true, "timezone": "Invalid/Timezone_XYZ"}' > "$TEST_DIR/home-fallback-badtz/.time-awareness.json"
OUTPUT=$(printf '%s' "$(make_input /tmp)" | HOME="$TEST_DIR/home-fallback-badtz" bash "$HOOK_NO_JQ" 2>/dev/null)
assert_contains "jq fallback invalid timezone still returns time" "$OUTPUT" "additionalContext"
assert_valid_json "jq fallback invalid timezone output is valid JSON" "$OUTPUT"

# Test: jq fallback with malformed JSON config (regex finds no fields → defaults)
mkdir -p "$TEST_DIR/home-fallback-malformed"
echo 'not valid json {{{' > "$TEST_DIR/home-fallback-malformed/.time-awareness.json"
OUTPUT=$(printf '%s' "$(make_input /tmp)" | HOME="$TEST_DIR/home-fallback-malformed" bash "$HOOK_NO_JQ" 2>/dev/null)
assert_contains "jq fallback malformed JSON uses defaults" "$OUTPUT" "additionalContext"
assert_valid_json "jq fallback malformed JSON output is valid JSON" "$OUTPUT"


# ─── Output Structure Tests ──────────────────────────────────────

echo ""
echo "Output structure validation:"

mkdir -p "$TEST_DIR/home-structure"
echo '{"enabled": true, "timezone": "UTC", "format": "iso"}' > "$TEST_DIR/home-structure/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-structure")
assert_valid_json "Full output is valid JSON" "$OUTPUT"
assert_contains "Has hookEventName=PreToolUse" "$OUTPUT" '"PreToolUse"'
assert_contains "Has permissionDecision=allow" "$OUTPUT" '"allow"'
assert_contains "Has permissionDecisionReason" "$OUTPUT" "permissionDecisionReason"
assert_contains "Has additionalContext" "$OUTPUT" "additionalContext"
assert_contains "Context starts with [System time:" "$OUTPUT" '\[System time:'
assert_contains "Context ends with ]" "$OUTPUT" '\]'

# Verify the time context contains a day-of-week abbreviation
assert_contains "Contains day-of-week" "$OUTPUT" '(Mon)\|(Tue)\|(Wed)\|(Thu)\|(Fri)\|(Sat)\|(Sun)'

# ─── Config Field Defaults Tests ──────────────────────────────────

echo ""
echo "Config field defaults:"

# Test: Config with only enabled field
mkdir -p "$TEST_DIR/home-minimal"
echo '{"enabled": true}' > "$TEST_DIR/home-minimal/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-minimal")
assert_contains "Minimal config (enabled only) works" "$OUTPUT" "additionalContext"

# Test: Config with enabled and timezone only
mkdir -p "$TEST_DIR/home-partial"
echo '{"enabled": true, "timezone": "UTC"}' > "$TEST_DIR/home-partial/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-partial")
assert_contains "Partial config (no format) works" "$OUTPUT" "additionalContext"

# Test: Empty JSON object (all defaults)
mkdir -p "$TEST_DIR/home-empty-obj"
echo '{}' > "$TEST_DIR/home-empty-obj/.time-awareness.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-empty-obj")
assert_contains "Empty JSON object uses defaults" "$OUTPUT" "additionalContext"

# ─── Windows Path Tests ──────────────────────────────────────────

echo ""
echo "Windows path handling:"

# Test: Windows-style CWD with backslashes
mkdir -p "$TEST_DIR/home-win"
echo '{"enabled": true}' > "$TEST_DIR/home-win/.time-awareness.json"
OUTPUT=$(run_hook "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"C:\\\\Users\\\\Tim\\\\repos"}')" "$TEST_DIR/home-win")
assert_contains "Windows backslash CWD returns time context" "$OUTPUT" "additionalContext"
assert_valid_json "Windows backslash CWD output is valid JSON" "$OUTPUT"

# Test: Windows HOME with backslashes (simulated via override)
mkdir -p "$TEST_DIR/win-home-bs"
echo '{"enabled": true}' > "$TEST_DIR/win-home-bs/.time-awareness.json"
OUTPUT=$(printf '%s' "$(make_input /tmp)" | HOME="$TEST_DIR/win-home-bs" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_contains "Config found with normalized HOME" "$OUTPUT" "additionalContext"

# Test: CWD with spaces (common on Windows)
mkdir -p "$TEST_DIR/home-spaces"
echo '{"enabled": true}' > "$TEST_DIR/home-spaces/.time-awareness.json"
OUTPUT=$(run_hook "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/c/Users/Tim Lovell/repos"}')" "$TEST_DIR/home-spaces")
assert_valid_json "CWD with spaces produces valid JSON" "$OUTPUT"

# ─── Performance Test ─────────────────────────────────────────────

echo ""
echo "Performance:"

mkdir -p "$TEST_DIR/home-perf"
echo '{"enabled": true}' > "$TEST_DIR/home-perf/.time-awareness.json"

TOTAL=$((TOTAL + 1))
START_TIME=$(date +%s%N 2>/dev/null || date +%s)
run_hook "$(make_input /tmp)" "$TEST_DIR/home-perf" >/dev/null
END_TIME=$(date +%s%N 2>/dev/null || date +%s)

# Handle nanosecond vs second precision
if [ ${#START_TIME} -gt 10 ]; then
    ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
else
    ELAPSED_MS=$(( (END_TIME - START_TIME) * 1000 ))
fi

if [ "$ELAPSED_MS" -lt 2000 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Completes within 2 seconds (${ELAPSED_MS}ms)"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Took too long (${ELAPSED_MS}ms, limit: 2000ms)"
fi

# ─── Exit Status Tests ───────────────────────────────────────────

echo ""
echo "Exit status:"

TOTAL=$((TOTAL + 1))
run_hook "$(make_input /tmp)" "$TEST_DIR/home-optin" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Opted-in exits with code 0"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Opted-in exits with code $EXIT_CODE (expected 0)"
fi

TOTAL=$((TOTAL + 1))
run_hook "$(make_input /tmp)" "$TEST_DIR/no-config" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Opted-out exits with code 0"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Opted-out exits with code $EXIT_CODE (expected 0)"
fi

TOTAL=$((TOTAL + 1))
echo "" | HOME="$TEST_DIR/home-stdin" bash "$HOOK_SCRIPT" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Empty stdin exits with code 0"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Empty stdin exits with code $EXIT_CODE (expected 0)"
fi

# ─── Summary ──────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo -e "Total: $TOTAL | ${GREEN}Passed: $PASS${NC} | ${RED}Failed: $FAIL${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
