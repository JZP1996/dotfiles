#!/usr/bin/env bash
# test-check-compaction.sh - Tests for the check-compaction.sh hook
#
# Usage: bash tests/test-check-compaction.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../hooks/check-compaction.sh"

PASS=0
FAIL=0
TOTAL=0

if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    NC=''
fi

assert_equals() {
    local test_name="$1" actual="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
    fi
}

assert_contains() {
    local test_name="$1" actual="$2" expected="$3"
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
    local test_name="$1" actual="$2" unexpected="$3"
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

# Helper: create a test environment with config + data files
setup_test_env() {
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/.claude"
    echo "$test_dir"
}

# Helper: run hook with custom HOME
run_hook() {
    local stdin_data="$1"
    local home_dir="$2"
    printf '%s' "$stdin_data" | HOME="$home_dir" bash "$HOOK_SCRIPT" 2>/dev/null
}

STDIN_DATA='{"tool_name": "Bash", "tool_input": {"command": "ls"}, "hook_event_name": "PreToolUse", "session_id": "test", "cwd": "/tmp", "tool_use_id": "test-123"}'

# ─── Test Suite ──────────────────────────────────────────────────

echo ""
echo "=== Compaction Monitor Hook Tests ==="
echo ""

# --- Not opted-in tests ---

echo "--- Not opted-in ---"

TEST_DIR=$(setup_test_env)
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_equals "No config file returns {}" "$OUTPUT" "{}"
rm -rf "$TEST_DIR"

echo ""
echo "--- Opted-in, disabled ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": false}' > "$TEST_DIR/home/.compaction-monitor.json"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_equals "Disabled config returns {}" "$OUTPUT" "{}"
rm -rf "$TEST_DIR"

echo ""
echo "--- Below thresholds ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
# Low utilization
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 30.5, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_equals "Below all thresholds returns {}" "$OUTPUT" "{}"
rm -rf "$TEST_DIR"

echo ""
echo "--- CAUTION: high utilization ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 78.2, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "High utilization triggers CAUTION" "$OUTPUT" "Context pressure"
assert_contains "High utilization shows percentage" "$OUTPUT" "78%"
assert_contains "High utilization suggests delegation" "$OUTPUT" "Delegate"
rm -rf "$TEST_DIR"

echo ""
echo "--- CAUTION: compaction count ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 20.0, "alert_level": "NORMAL"}
EOF
echo "3" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "High compaction count triggers CAUTION" "$OUTPUT" "Context pressure"
assert_contains "Shows compaction count" "$OUTPUT" "3 compactions"
rm -rf "$TEST_DIR"

echo ""
echo "--- WARNING: critical utilization ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 93.1, "alert_level": "WARNING"}
EOF
echo "1" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "Critical utilization triggers WARNING" "$OUTPUT" "HIGH CONTEXT PRESSURE"
assert_contains "Critical shows percentage" "$OUTPUT" "93%"
assert_contains "Critical suggests handoff" "$OUTPUT" "handoff"
rm -rf "$TEST_DIR"

echo ""
echo "--- WARNING: critical compaction count ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 40.0, "alert_level": "NORMAL"}
EOF
echo "5" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "Critical compaction count triggers WARNING" "$OUTPUT" "HIGH CONTEXT PRESSURE"
assert_contains "Shows compaction count" "$OUTPUT" "5 compactions"
rm -rf "$TEST_DIR"

echo ""
echo "--- Graceful: missing token_usage.json ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
# No token_usage.json
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_equals "Missing token_usage.json returns {}" "$OUTPUT" "{}"
rm -rf "$TEST_DIR"

echo ""
echo "--- Graceful: missing compaction-count.txt ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 80.0, "alert_level": "CAUTION"}
EOF
# No compaction-count.txt
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "Missing compaction-count uses 0" "$OUTPUT" "0 compactions"
assert_contains "Still warns on utilization" "$OUTPUT" "Context pressure"
rm -rf "$TEST_DIR"

echo ""
echo "--- alert_level from token_usage.json ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 60.0, "alert_level": "WARNING"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "WARNING alert_level triggers WARNING even with moderate utilization" "$OUTPUT" "HIGH CONTEXT PRESSURE"
rm -rf "$TEST_DIR"

echo ""
echo "--- Custom thresholds ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true, "warn_utilization_pct": 50, "critical_utilization_pct": 70}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 55.0, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "Custom warn threshold at 50% triggers at 55%" "$OUTPUT" "Context pressure"
rm -rf "$TEST_DIR"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true, "warn_utilization_pct": 50, "critical_utilization_pct": 70}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 72.0, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "Custom critical threshold at 70% triggers WARNING at 72%" "$OUTPUT" "HIGH CONTEXT PRESSURE"
rm -rf "$TEST_DIR"

echo ""
echo "--- Malformed config ---"

TEST_DIR=$(setup_test_env)
echo 'not json at all' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 80.0, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
# Malformed config should use defaults (warn at 75), and 80 >= 75 so CAUTION
assert_contains "Malformed config falls back to defaults" "$OUTPUT" "Context pressure"
rm -rf "$TEST_DIR"

echo ""
echo "--- Empty stdin ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
OUTPUT=$(printf '' | HOME="$TEST_DIR/home" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_equals "Empty stdin returns {}" "$OUTPUT" "{}"
rm -rf "$TEST_DIR"

echo ""
echo "--- CAUTION: actionable options ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 78.0, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "CAUTION suggests /compact" "$OUTPUT" "/compact"
assert_contains "CAUTION suggests subagent delegation" "$OUTPUT" "subagent"
assert_contains "CAUTION suggests /handoff" "$OUTPUT" "/handoff"
rm -rf "$TEST_DIR"

echo ""
echo "--- WARNING: actionable options ---"

TEST_DIR=$(setup_test_env)
echo '{"enabled": true}' > "$TEST_DIR/home/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 93.0, "alert_level": "WARNING"}
EOF
echo "1" > "$TEST_DIR/home/.claude/compaction-count.txt"
OUTPUT=$(run_hook "$STDIN_DATA" "$TEST_DIR/home")
assert_contains "WARNING suggests /compact" "$OUTPUT" "/compact"
assert_contains "WARNING suggests /clear" "$OUTPUT" "/clear"
assert_contains "WARNING suggests subagent delegation" "$OUTPUT" "subagent"
assert_contains "WARNING suggests /handoff" "$OUTPUT" "/handoff"
rm -rf "$TEST_DIR"

echo ""
echo "--- Repo root config ---"

TEST_DIR=$(setup_test_env)
REPO_DIR="$TEST_DIR/repo"
mkdir -p "$REPO_DIR"
git -C "$REPO_DIR" init --quiet 2>/dev/null
echo '{"enabled": true}' > "$REPO_DIR/.compaction-monitor.json"
cat > "$TEST_DIR/home/.claude/token_usage.json" << 'EOF'
{"utilization_pct": 85.0, "alert_level": "NORMAL"}
EOF
echo "0" > "$TEST_DIR/home/.claude/compaction-count.txt"
REPO_STDIN=$(printf '{"tool_name": "Bash", "tool_input": {"command": "ls"}, "hook_event_name": "PreToolUse", "session_id": "test", "cwd": "%s", "tool_use_id": "test-123"}' "$REPO_DIR")
OUTPUT=$(run_hook "$REPO_STDIN" "$TEST_DIR/home")
assert_contains "Repo root config works" "$OUTPUT" "Context pressure"
rm -rf "$TEST_DIR"

# ─── Summary ─────────────────────────────────────────────────────

echo ""
echo "========================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
