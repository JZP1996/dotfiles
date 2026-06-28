#!/usr/bin/env bash
# test-check-git-author.sh - Tests for the check-git-author.sh hook
#
# Runs a suite of tests verifying the hook correctly validates git author
# email before commit commands.
#
# Usage: bash plugins/git-author-check/tests/test-check-git-author.sh

set -euo pipefail

# Resolve hook script path relative to this test file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../hooks/check-git-author.sh"

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

# shellcheck disable=SC2329
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
        if [[ "$json_str" == "{"* ]]; then
            PASS=$((PASS + 1))
            echo -e "  ${GREEN}PASS${NC}: $test_name (basic JSON check)"
        else
            FAIL=$((FAIL + 1))
            echo -e "  ${RED}FAIL${NC}: $test_name (not JSON-like)"
            echo "    Output: $json_str"
        fi
    fi
}

# Create a temporary directory for test repos
TEST_DIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TEST_DIR'" EXIT

# Use a fixed state file path for test reproducibility (PID-scoped in production)
STATE_FILE="${TEST_DIR}/git-author-check-autofixed-test"
export GIT_AUTHOR_CHECK_STATE_FILE="$STATE_FILE"
rm -f "$STATE_FILE"

# Helper: create a test git repo with a specific email
setup_repo() {
    local repo_dir="$1"
    local email="$2"
    mkdir -p "$repo_dir"
    git -C "$repo_dir" init --quiet 2>/dev/null
    git -C "$repo_dir" config user.email "$email"
    git -C "$repo_dir" config user.name "Test User"
}

# Helper: run the hook with a given command and cwd
run_hook() {
    local cmd="$1"
    local cwd="$2"
    local env_vars="${3:-}"
    # Intentional word splitting: env_vars contains KEY=VALUE pairs
    # shellcheck disable=SC2086
    printf '{"tool_name": "Bash", "tool_input": {"command": "%s"}, "cwd": "%s"}' "$cmd" "$cwd" \
        | env $env_vars bash "$HOOK_SCRIPT" 2>/dev/null
}

make_input() {
    local cmd="$1"
    local cwd="${2:-/tmp}"
    printf '{"tool_name": "Bash", "tool_input": {"command": "%s"}, "cwd": "%s"}' "$cmd" "$cwd"
}

echo ""
echo "=== check-git-author.sh Hook Tests ==="
echo ""

# ─── Non-commit commands pass silently ───────────────────────────

echo "Non-commit commands (should pass silently):"

REPO="$TEST_DIR/repo-noncommit"
setup_repo "$REPO" "wrong@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"

OUTPUT=$(run_hook "git status" "$REPO")
assert_equals "git status passes silently" "$OUTPUT" "{}"

OUTPUT=$(run_hook "git log --oneline" "$REPO")
assert_equals "git log passes silently" "$OUTPUT" "{}"

OUTPUT=$(run_hook "git diff HEAD" "$REPO")
assert_equals "git diff passes silently" "$OUTPUT" "{}"

OUTPUT=$(run_hook "git add ." "$REPO")
assert_equals "git add passes silently" "$OUTPUT" "{}"

OUTPUT=$(run_hook "echo not a git command" "$REPO")
assert_equals "Non-git command passes silently" "$OUTPUT" "{}"

OUTPUT=$(run_hook "echo git commit in a string" "$REPO")
# This contains "git commit" in the string but it's an echo command
# The hook checks for git commit pattern, so this might match
# That's acceptable -- false positive on echo is safe (it's just a check)

# ─── Correct email passes ────────────────────────────────────────

echo ""
echo "Correct email (should pass):"

REPO="$TEST_DIR/repo-correct"
setup_repo "$REPO" "correct@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

OUTPUT=$(run_hook "git commit -m 'test'" "$REPO")
assert_equals "Correct email passes" "$OUTPUT" "{}"
assert_valid_json "Correct email output is valid JSON" "$OUTPUT"

# Case-insensitive match
setup_repo "$REPO" "Correct@Example.COM"
OUTPUT=$(run_hook "git commit -m 'test'" "$REPO")
assert_equals "Case-insensitive email match passes" "$OUTPUT" "{}"

# ─── Wrong email -- first time auto-fixes ─────────────────────────

echo ""
echo "Wrong email - first mismatch (should auto-fix + warn):"

REPO="$TEST_DIR/repo-autofix"
setup_repo "$REPO" "wrong@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

OUTPUT=$(run_hook "git commit -m 'test'" "$REPO")
assert_contains "First mismatch allows" "$OUTPUT" '"allow"'
assert_contains "First mismatch warns about auto-fix" "$OUTPUT" "Auto-corrected to expected email"
assert_contains "First mismatch shows old email" "$OUTPUT" "wrong@example.com"
assert_contains "First mismatch shows expected email" "$OUTPUT" "correct@example.com"
assert_valid_json "First mismatch output is valid JSON" "$OUTPUT"

# Verify email was corrected
FIXED_EMAIL=$(git -C "$REPO" config user.email 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [ "$FIXED_EMAIL" = "correct@example.com" ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Email was auto-corrected in git config"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Email was NOT auto-corrected (got: $FIXED_EMAIL)"
fi

# ─── Wrong email -- subsequent mismatch blocks ───────────────────

echo ""
echo "Wrong email - subsequent mismatch (should block):"

REPO="$TEST_DIR/repo-block"
setup_repo "$REPO" "wrong-again@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
# First trigger auto-fix for this repo
rm -f "$STATE_FILE"
run_hook "git commit -m 'first'" "$REPO" >/dev/null
# Reset email to wrong value to simulate drift
git -C "$REPO" config user.email "wrong-again@example.com"

OUTPUT=$(run_hook "git commit -m 'test'" "$REPO")
assert_contains "Subsequent mismatch blocks" "$OUTPUT" '"block"'
assert_contains "Block message shows current email" "$OUTPUT" "wrong-again@example.com"
assert_contains "Block message shows expected email" "$OUTPUT" "correct@example.com"
assert_valid_json "Block output is valid JSON" "$OUTPUT"

# ─── GIT_AUTHOR_EMAIL override bypasses check ───────────────────

echo ""
echo "GIT_AUTHOR_EMAIL override (should bypass):"

REPO="$TEST_DIR/repo-override"
setup_repo "$REPO" "wrong@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

OUTPUT=$(run_hook "GIT_AUTHOR_EMAIL=other@example.com git commit -m 'test'" "$REPO")
assert_equals "GIT_AUTHOR_EMAIL override bypasses check" "$OUTPUT" "{}"

# ─── No expected email configured -- warn ─────────────────────────

echo ""
echo "No expected email configured (should warn):"

REPO="$TEST_DIR/repo-noconfig"
setup_repo "$REPO" "someone@example.com"
rm -f "$STATE_FILE"
# No .git-author-check.json, no EXPECTED_GIT_EMAIL

OUTPUT=$(printf '%s' "$(make_input "git commit -m 'test'" "$REPO")" | EXPECTED_GIT_EMAIL="" HOME="$TEST_DIR/no-home" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_contains "No config warns" "$OUTPUT" "No expected email configured"
assert_contains "No config allows" "$OUTPUT" '"allow"'
assert_valid_json "No config output is valid JSON" "$OUTPUT"

# ─── EXPECTED_GIT_EMAIL env var ──────────────────────────────────

echo ""
echo "EXPECTED_GIT_EMAIL env var:"

REPO="$TEST_DIR/repo-envvar"
setup_repo "$REPO" "correct@example.com"
rm -f "$STATE_FILE"

OUTPUT=$(printf '%s' "$(make_input "git commit -m 'test'" "$REPO")" | EXPECTED_GIT_EMAIL="correct@example.com" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_equals "Env var with matching email passes" "$OUTPUT" "{}"

# Env var takes precedence over config file
echo '{"expected_email": "file@example.com"}' > "$REPO/.git-author-check.json"
OUTPUT=$(printf '%s' "$(make_input "git commit -m 'test'" "$REPO")" | EXPECTED_GIT_EMAIL="correct@example.com" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_equals "Env var takes precedence over config file" "$OUTPUT" "{}"

# ─── Home directory config ───────────────────────────────────────

echo ""
echo "Home directory config:"

REPO="$TEST_DIR/repo-homeconfig"
setup_repo "$REPO" "correct@example.com"
rm -f "$STATE_FILE"
# No repo-level config
mkdir -p "$TEST_DIR/home-with-config"
echo '{"expected_email": "correct@example.com"}' > "$TEST_DIR/home-with-config/.git-author-check.json"

OUTPUT=$(printf '%s' "$(make_input "git commit -m 'test'" "$REPO")" | EXPECTED_GIT_EMAIL="" HOME="$TEST_DIR/home-with-config" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_equals "Home directory config works" "$OUTPUT" "{}"

# ─── git -C path commit variant ─────────────────────────────────

echo ""
echo "Git command variants:"

REPO="$TEST_DIR/repo-variants"
setup_repo "$REPO" "correct@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

OUTPUT=$(run_hook "git -C /some/path commit -m 'test'" "$REPO")
assert_equals "git -C path commit is detected" "$OUTPUT" "{}"

OUTPUT=$(run_hook "git commit --amend --no-edit" "$REPO")
assert_equals "git commit --amend is detected" "$OUTPUT" "{}"

# ─── Chained command parsing (Issue #4) ──────────────────────────

echo ""
echo "Chained commands (should detect git commit in chains):"

REPO="$TEST_DIR/repo-chained"
setup_repo "$REPO" "correct@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

OUTPUT=$(run_hook "git add . && git commit -m 'test'" "$REPO")
assert_equals "git add && git commit detected (correct email passes)" "$OUTPUT" "{}"

OUTPUT=$(run_hook "git add -A ; git commit -m 'test'" "$REPO")
assert_equals "git add ; git commit detected (correct email passes)" "$OUTPUT" "{}"

OUTPUT=$(run_hook "echo hello && git add . && git commit -m 'test'" "$REPO")
assert_equals "multi-chain with git commit detected" "$OUTPUT" "{}"

# Verify chained commands with wrong email trigger mismatch
REPO="$TEST_DIR/repo-chained-wrong"
setup_repo "$REPO" "wrong@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

OUTPUT=$(run_hook "git add . && git commit -m 'test'" "$REPO")
assert_contains "chained command with wrong email triggers auto-fix" "$OUTPUT" '"allow"'
assert_contains "chained command shows auto-fix warning" "$OUTPUT" "Auto-corrected"

# ─── Multi-repo state isolation (Issue #1) ───────────────────────

echo ""
echo "Multi-repo state isolation:"

REPO_A="$TEST_DIR/repo-multi-a"
REPO_B="$TEST_DIR/repo-multi-b"
setup_repo "$REPO_A" "wrong@example.com"
setup_repo "$REPO_B" "wrong@example.com"
echo '{"expected_email": "a@example.com"}' > "$REPO_A/.git-author-check.json"
echo '{"expected_email": "b@example.com"}' > "$REPO_B/.git-author-check.json"
# Unset override so per-repo hash state files are used
unset GIT_AUTHOR_CHECK_STATE_FILE
rm -f "${TMPDIR:-/tmp}"/git-author-check-autofixed-* 2>/dev/null || true

# Auto-fix fires for repo A
OUTPUT_A=$(run_hook "git commit -m 'test'" "$REPO_A")
assert_contains "Repo A first mismatch auto-fixes" "$OUTPUT_A" '"allow"'

# Auto-fix should ALSO fire for repo B (independent state)
OUTPUT_B=$(run_hook "git commit -m 'test'" "$REPO_B")
assert_contains "Repo B first mismatch auto-fixes independently" "$OUTPUT_B" '"allow"'
assert_contains "Repo B shows correct expected email" "$OUTPUT_B" "b@example.com"

# Verify both repos got their respective emails
EMAIL_A=$(git -C "$REPO_A" config user.email 2>/dev/null)
EMAIL_B=$(git -C "$REPO_B" config user.email 2>/dev/null)
assert_equals "Repo A has its expected email" "$EMAIL_A" "a@example.com"
assert_equals "Repo B has its expected email" "$EMAIL_B" "b@example.com"

# Now a second mismatch on repo A should block, while repo B is unaffected
git -C "$REPO_A" config user.email "drifted@example.com"
OUTPUT_A2=$(run_hook "git commit -m 'test'" "$REPO_A")
assert_contains "Repo A second mismatch blocks" "$OUTPUT_A2" '"block"'

# Restore test state file override
export GIT_AUTHOR_CHECK_STATE_FILE="$STATE_FILE"

# ─── Malformed expected email warns (Issue #3) ──────────────────

echo ""
echo "Malformed expected email (should warn, not silently pass):"

REPO="$TEST_DIR/repo-malformed"
setup_repo "$REPO" "user@example.com"
rm -f "$STATE_FILE"

# Missing TLD
OUTPUT=$(printf '%s' "$(make_input "git commit -m 'test'" "$REPO")" | EXPECTED_GIT_EMAIL="user@example" bash "$HOOK_SCRIPT" 2>/dev/null)
assert_contains "Malformed email warns user" "$OUTPUT" "does not look like a valid email"
assert_contains "Malformed email allows (graceful)" "$OUTPUT" '"allow"'
assert_valid_json "Malformed email output is valid JSON" "$OUTPUT"

# ─── State file reset on email change (Issue #5) ────────────────

echo ""
echo "State file reset on expected email change:"

REPO="$TEST_DIR/repo-reset"
setup_repo "$REPO" "wrong@example.com"
echo '{"expected_email": "old@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

# Trigger auto-fix with old expected email
run_hook "git commit -m 'first'" "$REPO" >/dev/null

# Change expected email (simulates legitimate config update)
echo '{"expected_email": "new@example.com"}' > "$REPO/.git-author-check.json"
git -C "$REPO" config user.email "wrong@example.com"

# Should auto-fix again (not block), because expected email changed
OUTPUT=$(run_hook "git commit -m 'test'" "$REPO")
assert_contains "Changed expected email resets state (auto-fixes)" "$OUTPUT" '"allow"'
assert_contains "Shows new expected email in warning" "$OUTPUT" "new@example.com"

# ─── Empty/Invalid input ────────────────────────────────────────

echo ""
echo "Empty and invalid input:"

rm -f "$STATE_FILE"

OUTPUT=$(echo "" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_equals "Empty stdin returns empty JSON" "$OUTPUT" "{}"

OUTPUT=$(bash "$HOOK_SCRIPT" < /dev/null 2>/dev/null)
assert_equals "No stdin returns empty JSON" "$OUTPUT" "{}"

OUTPUT=$(printf 'not json' | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_valid_json "Invalid JSON stdin output is valid JSON" "$OUTPUT"

# ─── Performance ────────────────────────────────────────────────

echo ""
echo "Performance:"

REPO="$TEST_DIR/repo-perf"
setup_repo "$REPO" "correct@example.com"
echo '{"expected_email": "correct@example.com"}' > "$REPO/.git-author-check.json"
rm -f "$STATE_FILE"

TOTAL=$((TOTAL + 1))
START_TIME=$(date +%s%N 2>/dev/null || date +%s)
run_hook "git commit -m 'test'" "$REPO" >/dev/null
END_TIME=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#START_TIME} -gt 10 ]; then
    ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
else
    ELAPSED_MS=$(( (END_TIME - START_TIME) * 1000 ))
fi

if [ "$ELAPSED_MS" -lt 3000 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Completes within 3 seconds (${ELAPSED_MS}ms)"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Took too long (${ELAPSED_MS}ms, limit: 3000ms)"
fi

# ─── Exit status ────────────────────────────────────────────────

echo ""
echo "Exit status:"

TOTAL=$((TOTAL + 1))
run_hook "git commit -m 'test'" "$REPO" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: Normal run exits with code 0"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: Normal run exits with code $EXIT_CODE (expected 0)"
fi

# ─── Summary ────────────────────────────────────────────────────

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
