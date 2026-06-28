#!/usr/bin/env bash
# test-summarize-context.sh - Tests for the summarize-context.sh hook
#
# Runs a suite of tests verifying the hook correctly injects summary context
# when opted-in and returns {} when not opted-in.
#
# Usage: bash tests/test-summarize-context.sh

set -euo pipefail

# Resolve hook script path relative to this test file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../hooks/summarize-context.sh"

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
echo "=== summarize-context.sh Hook Tests ==="
echo ""

# ─── Opt-In Tests ─────────────────────────────────────────────────

echo "Opt-in behavior:"

# Test: Opted-in with config in HOME
mkdir -p "$TEST_DIR/home-optin"
echo '{"enabled": true}' > "$TEST_DIR/home-optin/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-optin")
assert_contains "Opted-in via HOME config returns summary context" "$OUTPUT" "additionalContext"
assert_contains "Opted-in has permissionDecision=allow" "$OUTPUT" '"allow"'
assert_contains "Opted-in has hookEventName" "$OUTPUT" "hookEventName"
assert_contains "Opted-in has Conversation Summary prefix" "$OUTPUT" "Conversation Summary:"
assert_valid_json "Opted-in output is valid JSON" "$OUTPUT"

# Test: Opted-out (no config file)
mkdir -p "$TEST_DIR/no-config"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/no-config")
assert_equals "No config file returns empty JSON" "$OUTPUT" "{}"

# Test: Disabled (enabled: false)
mkdir -p "$TEST_DIR/home-disabled"
echo '{"enabled": false}' > "$TEST_DIR/home-disabled/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-disabled")
assert_equals "Disabled config returns empty JSON" "$OUTPUT" "{}"

# Test: Config in repo root (via cwd)
mkdir -p "$TEST_DIR/repo-root"
git -C "$TEST_DIR/repo-root" init --quiet 2>/dev/null || true
echo '{"enabled": true}' > "$TEST_DIR/repo-root/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input "$TEST_DIR/repo-root")" "$TEST_DIR/no-config")
assert_contains "Repo root config returns summary context" "$OUTPUT" "additionalContext"

# Test: HOME config takes precedence over repo root
mkdir -p "$TEST_DIR/home-precedence"
echo '{"enabled": false}' > "$TEST_DIR/home-precedence/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input "$TEST_DIR/repo-root")" "$TEST_DIR/home-precedence")
assert_equals "HOME config takes precedence (disabled)" "$OUTPUT" "{}"

# ─── Config Field Tests ──────────────────────────────────────────

echo ""
echo "Config field handling:"

# Test: Default output_dir
mkdir -p "$TEST_DIR/home-defaults"
echo '{"enabled": true}' > "$TEST_DIR/home-defaults/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-defaults")
assert_contains "Default output_dir is docs/local/summaries" "$OUTPUT" "docs/local/summaries"

# Test: Custom output_dir
mkdir -p "$TEST_DIR/home-custom-dir"
echo '{"enabled": true, "output_dir": "my/custom/path"}' > "$TEST_DIR/home-custom-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-custom-dir")
assert_contains "Custom output_dir is used" "$OUTPUT" "my/custom/path"

# Test: Default max_lines
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-defaults")
assert_contains "Default max_lines is 500" "$OUTPUT" "500"

# Test: Custom max_lines
mkdir -p "$TEST_DIR/home-custom-lines"
echo '{"enabled": true, "max_lines": 200}' > "$TEST_DIR/home-custom-lines/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-custom-lines")
assert_contains "Custom max_lines is used" "$OUTPUT" "200"

# Test: Default update_frequency
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-defaults")
assert_contains "Default update_frequency is moderate" "$OUTPUT" "every 5-10 tool calls"

# Test: High update_frequency
mkdir -p "$TEST_DIR/home-freq-high"
echo '{"enabled": true, "update_frequency": "high"}' > "$TEST_DIR/home-freq-high/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-freq-high")
assert_contains "High frequency guidance" "$OUTPUT" "every 2-3 tool calls"

# Test: Low update_frequency
mkdir -p "$TEST_DIR/home-freq-low"
echo '{"enabled": true, "update_frequency": "low"}' > "$TEST_DIR/home-freq-low/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-freq-low")
assert_contains "Low frequency guidance" "$OUTPUT" "every 15-20 tool calls"

# ─── Validation Tests ────────────────────────────────────────────

echo ""
echo "Input validation:"

# Test: Absolute output_dir rejected
mkdir -p "$TEST_DIR/home-abs-dir"
echo '{"enabled": true, "output_dir": "/etc/evil"}' > "$TEST_DIR/home-abs-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-abs-dir")
assert_equals "Absolute output_dir rejected" "$OUTPUT" "{}"

# Test: Path traversal in output_dir rejected
mkdir -p "$TEST_DIR/home-traversal"
echo '{"enabled": true, "output_dir": "docs/../../etc"}' > "$TEST_DIR/home-traversal/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-traversal")
assert_equals "Path traversal in output_dir rejected" "$OUTPUT" "{}"

# Test: output_dir with just .. rejected
mkdir -p "$TEST_DIR/home-dotdot"
echo '{"enabled": true, "output_dir": ".."}' > "$TEST_DIR/home-dotdot/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-dotdot")
assert_equals "Bare .. in output_dir rejected" "$OUTPUT" "{}"

# Test: output_dir with special characters rejected
mkdir -p "$TEST_DIR/home-special-dir"
echo '{"enabled": true, "output_dir": "docs/local/sum maries"}' > "$TEST_DIR/home-special-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-special-dir")
assert_equals "output_dir with spaces rejected" "$OUTPUT" "{}"

# Test: max_lines 0 falls back to default
mkdir -p "$TEST_DIR/home-zero-lines"
echo '{"enabled": true, "max_lines": 0}' > "$TEST_DIR/home-zero-lines/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-zero-lines")
assert_contains "max_lines 0 falls back to 500" "$OUTPUT" "500"

# Test: max_lines over 2000 capped
mkdir -p "$TEST_DIR/home-huge-lines"
echo '{"enabled": true, "max_lines": 5000}' > "$TEST_DIR/home-huge-lines/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-huge-lines")
assert_contains "max_lines over 2000 capped to 2000" "$OUTPUT" "2000"

# Test: max_lines non-numeric falls back to default
mkdir -p "$TEST_DIR/home-nan-lines"
echo '{"enabled": true, "max_lines": "abc"}' > "$TEST_DIR/home-nan-lines/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-nan-lines")
assert_contains "max_lines non-numeric falls back to 500" "$OUTPUT" "500"

# Test: Unknown update_frequency falls back to moderate
mkdir -p "$TEST_DIR/home-bad-freq"
echo '{"enabled": true, "update_frequency": "extreme"}' > "$TEST_DIR/home-bad-freq/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-bad-freq")
assert_contains "Unknown update_frequency falls back to moderate" "$OUTPUT" "every 5-10 tool calls"

# ─── Malformed Config Tests ──────────────────────────────────────

echo ""
echo "Malformed config handling:"

# Test: Malformed JSON config
mkdir -p "$TEST_DIR/home-malformed"
echo 'not valid json {{{' > "$TEST_DIR/home-malformed/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-malformed")
# Malformed JSON → use defaults (enabled=true)
assert_contains "Malformed JSON uses defaults (still returns context)" "$OUTPUT" "additionalContext"
assert_valid_json "Malformed JSON output is still valid JSON" "$OUTPUT"

# Test: Empty config file
mkdir -p "$TEST_DIR/home-empty-config"
echo -n '' > "$TEST_DIR/home-empty-config/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-empty-config")
assert_equals "Empty config file returns empty JSON" "$OUTPUT" "{}"

# Test: Config with only whitespace
mkdir -p "$TEST_DIR/home-whitespace"
echo '   ' > "$TEST_DIR/home-whitespace/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-whitespace")
# Whitespace-only → jq fails → defaults, or bash regex finds nothing → defaults
assert_valid_json "Whitespace-only config output is valid JSON" "$OUTPUT"

# Test: Empty JSON object (all defaults)
mkdir -p "$TEST_DIR/home-empty-obj"
echo '{}' > "$TEST_DIR/home-empty-obj/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-empty-obj")
assert_contains "Empty JSON object uses defaults" "$OUTPUT" "additionalContext"

# ─── Empty/Invalid Input Tests ───────────────────────────────────

echo ""
echo "Empty and invalid input:"

# Test: Empty stdin
mkdir -p "$TEST_DIR/home-stdin"
echo '{"enabled": true}' > "$TEST_DIR/home-stdin/.conversation-summary.json"
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

# Test: Control characters in config
# Control chars in a value that still parses as valid JSON don't cause rejection;
# the hook sanitizes the value or proceeds with defaults. Verify output is valid JSON
# and doesn't pass through the control character unsanitized.
mkdir -p "$TEST_DIR/home-control"
printf '{"enabled": true, "output_dir": "docs\x01local"}' > "$TEST_DIR/home-control/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-control")
assert_valid_json "Control characters in config produces valid JSON" "$OUTPUT"
assert_not_contains "Control characters sanitized from output" "$OUTPUT" $'\x01'

# Test: Prompt injection in output_dir (semicolon)
mkdir -p "$TEST_DIR/home-injection-dir"
echo '{"enabled": true, "output_dir": "docs;echo INJECTED"}' > "$TEST_DIR/home-injection-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-injection-dir")
assert_equals "Semicolon in output_dir rejected" "$OUTPUT" "{}"

# Test: Shell metacharacters in output_dir
mkdir -p "$TEST_DIR/home-metachar-dir"
# shellcheck disable=SC2016
echo '{"enabled": true, "output_dir": "$(whoami)/summaries"}' > "$TEST_DIR/home-metachar-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-metachar-dir")
assert_equals "Shell metachar in output_dir rejected" "$OUTPUT" "{}"

# Test: Backtick injection in output_dir
mkdir -p "$TEST_DIR/home-backtick-dir"
# shellcheck disable=SC2016
printf '{"enabled": true, "output_dir": "`whoami`/summaries"}' > "$TEST_DIR/home-backtick-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-backtick-dir")
assert_equals "Backtick injection in output_dir rejected" "$OUTPUT" "{}"

# Test: Newline injection in update_frequency
mkdir -p "$TEST_DIR/home-newline-freq"
printf '{"enabled": true, "update_frequency": "moderate\\nINJECTED"}' > "$TEST_DIR/home-newline-freq/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-newline-freq")
assert_not_contains "Newline in update_frequency doesn't leak" "$OUTPUT" "INJECTED"
assert_valid_json "Newline injection output is valid JSON" "$OUTPUT"

# Test: Very long output_dir string
mkdir -p "$TEST_DIR/home-long-dir"
LONG_DIR=$(printf 'a%.0s' {1..1000})
echo "{\"enabled\": true, \"output_dir\": \"$LONG_DIR\"}" > "$TEST_DIR/home-long-dir/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-long-dir")
assert_valid_json "Very long output_dir output is valid JSON" "$OUTPUT"

# ─── jq Fallback Tests ──────────────────────────────────────────

echo ""
echo "jq fallback (bash-only parsing):"

# Test: Simulate jq unavailability by creating a modified copy of the hook
# that replaces "command -v jq" with "false" to force the bash regex fallback
HOOK_NO_JQ="$TEST_DIR/summarize-context-no-jq.sh"
sed 's/command -v jq/false/g' "$HOOK_SCRIPT" > "$HOOK_NO_JQ"
chmod +x "$HOOK_NO_JQ"

run_hook_no_jq() {
    local input="$1"
    local home_override="${2:-$TEST_DIR/no-home}"
    printf '%s' "$input" | HOME="$home_override" bash "$HOOK_NO_JQ" 2>/dev/null
}

mkdir -p "$TEST_DIR/home-fallback"
echo '{"enabled": true, "output_dir": "docs/local/summaries", "max_lines": 300, "update_frequency": "high"}' > "$TEST_DIR/home-fallback/.conversation-summary.json"
OUTPUT=$(run_hook_no_jq "$(make_input /tmp)" "$TEST_DIR/home-fallback")
assert_contains "jq fallback returns summary context" "$OUTPUT" "additionalContext"
assert_contains "jq fallback parses output_dir" "$OUTPUT" "docs/local/summaries"
assert_contains "jq fallback parses max_lines" "$OUTPUT" "300"
assert_contains "jq fallback parses update_frequency" "$OUTPUT" "every 2-3 tool calls"
assert_valid_json "jq fallback output is valid JSON" "$OUTPUT"

# Test: jq fallback with disabled config
mkdir -p "$TEST_DIR/home-fallback-disabled"
echo '{"enabled": false}' > "$TEST_DIR/home-fallback-disabled/.conversation-summary.json"
OUTPUT=$(run_hook_no_jq "$(make_input /tmp)" "$TEST_DIR/home-fallback-disabled")
assert_equals "jq fallback disabled returns empty JSON" "$OUTPUT" "{}"

# Test: jq fallback with malformed JSON config (regex finds no fields → defaults)
mkdir -p "$TEST_DIR/home-fallback-malformed"
echo 'not valid json {{{' > "$TEST_DIR/home-fallback-malformed/.conversation-summary.json"
OUTPUT=$(run_hook_no_jq "$(make_input /tmp)" "$TEST_DIR/home-fallback-malformed")
assert_contains "jq fallback malformed JSON uses defaults" "$OUTPUT" "additionalContext"
assert_valid_json "jq fallback malformed JSON output is valid JSON" "$OUTPUT"

# Test: jq fallback with path traversal
mkdir -p "$TEST_DIR/home-fallback-traversal"
echo '{"enabled": true, "output_dir": "../../../etc"}' > "$TEST_DIR/home-fallback-traversal/.conversation-summary.json"
OUTPUT=$(run_hook_no_jq "$(make_input /tmp)" "$TEST_DIR/home-fallback-traversal")
assert_equals "jq fallback path traversal rejected" "$OUTPUT" "{}"

# Test: jq fallback with absolute path
mkdir -p "$TEST_DIR/home-fallback-abs"
echo '{"enabled": true, "output_dir": "/etc/evil"}' > "$TEST_DIR/home-fallback-abs/.conversation-summary.json"
OUTPUT=$(run_hook_no_jq "$(make_input /tmp)" "$TEST_DIR/home-fallback-abs")
assert_equals "jq fallback absolute path rejected" "$OUTPUT" "{}"

# ─── Output Structure Tests ─────────────────────────────────────

echo ""
echo "Output structure validation:"

mkdir -p "$TEST_DIR/home-structure"
echo '{"enabled": true}' > "$TEST_DIR/home-structure/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-structure")
assert_valid_json "Full output is valid JSON" "$OUTPUT"
assert_contains "Has hookEventName=PreToolUse" "$OUTPUT" '"PreToolUse"'
assert_contains "Has permissionDecision=allow" "$OUTPUT" '"allow"'
assert_contains "Has permissionDecisionReason" "$OUTPUT" "permissionDecisionReason"
assert_contains "Has additionalContext" "$OUTPUT" "additionalContext"
assert_contains "Context starts with [Conversation Summary:" "$OUTPUT" '\[Conversation Summary:'

# ─── Config Field Defaults Tests ─────────────────────────────────

echo ""
echo "Config field defaults:"

# Test: Config with only enabled field
mkdir -p "$TEST_DIR/home-minimal"
echo '{"enabled": true}' > "$TEST_DIR/home-minimal/.conversation-summary.json"
OUTPUT=$(run_hook "$(make_input /tmp)" "$TEST_DIR/home-minimal")
assert_contains "Minimal config (enabled only) works" "$OUTPUT" "additionalContext"
assert_contains "Minimal config has default output_dir" "$OUTPUT" "docs/local/summaries"
assert_contains "Minimal config has default max_lines" "$OUTPUT" "500"
assert_contains "Minimal config has default frequency" "$OUTPUT" "every 5-10 tool calls"

# ─── Windows Path Tests ──────────────────────────────────────────

echo ""
echo "Windows path handling:"

# Test: Windows-style CWD with backslashes
mkdir -p "$TEST_DIR/home-win"
echo '{"enabled": true}' > "$TEST_DIR/home-win/.conversation-summary.json"
OUTPUT=$(run_hook "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"C:\\\\Users\\\\Tim\\\\repos"}')" "$TEST_DIR/home-win")
assert_contains "Windows backslash CWD returns summary context" "$OUTPUT" "additionalContext"
assert_valid_json "Windows backslash CWD output is valid JSON" "$OUTPUT"

# Test: CWD with spaces (common on Windows)
mkdir -p "$TEST_DIR/home-spaces"
echo '{"enabled": true}' > "$TEST_DIR/home-spaces/.conversation-summary.json"
OUTPUT=$(run_hook "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/c/Users/Tim Lovell/repos"}')" "$TEST_DIR/home-spaces")
assert_valid_json "CWD with spaces produces valid JSON" "$OUTPUT"

# ─── Performance Test ────────────────────────────────────────────

echo ""
echo "Performance:"

mkdir -p "$TEST_DIR/home-perf"
echo '{"enabled": true}' > "$TEST_DIR/home-perf/.conversation-summary.json"

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

# ─── Exit Status Tests ──────────────────────────────────────────

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

# ─── Summary ─────────────────────────────────────────────────────

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
