#!/usr/bin/env bash
# cap-sleep.sh - PreToolUse hook that blocks excessive sleep commands
#
# Detects sleep commands in Bash tool calls and blocks those exceeding
# a configurable threshold (default 60 seconds). Suggests run_in_background
# as an alternative to long sleeps.
#
# Input: JSON on stdin from Claude Code's hook system
#   { "tool_name": "Bash", "tool_input": { "command": "..." }, "cwd": "..." }
#
# Output: JSON on stdout
#   - Sleep exceeding threshold: block with suggestion
#   - Otherwise: {} (no-op)
#
# Configuration:
#   SLEEP_CAP_THRESHOLD — max allowed sleep in seconds (default: 60)
#   # sleep-cap:ignore  — inline comment to bypass the check (must follow #)
#
# Dependencies: bash 3.2+, jq (with pure-bash fallback)
#
# Security:
#   - No eval anywhere
#   - Read-only analysis of command string (never executes it)
#   - Static template output only
#   - Every error path -> {} + exit 0

set -euo pipefail

# Fail-safe: any unexpected error outputs empty JSON
trap 'echo "{}"; exit 0' ERR

# ─── Configuration ───────────────────────────────────────────────

THRESHOLD="${SLEEP_CAP_THRESHOLD:-60}"

# ─── Read stdin ──────────────────────────────────────────────────

INPUT=""
if ! INPUT=$(cat 2>/dev/null); then
    echo '{}'
    exit 0
fi

if [ -z "$INPUT" ]; then
    echo '{}'
    exit 0
fi

# ─── Extract command from tool_input ─────────────────────────────

COMMAND=""
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
else
    # Pure bash fallback - extract command value
    # Greedy match captures full value even with escaped quotes (best-effort fallback)
    if [[ "$INPUT" =~ \"command\"[[:space:]]*:[[:space:]]*\"(.+)\" ]]; then
        COMMAND="${BASH_REMATCH[1]}"
    fi
fi

if [ -z "$COMMAND" ]; then
    echo '{}'
    exit 0
fi

# ─── Check for override comment ─────────────────────────────────

if [[ "$COMMAND" == *"# sleep-cap:ignore"* ]]; then
    echo '{}'
    exit 0
fi

# ─── Detect sleep commands and convert to seconds ────────────────

# Fast path: skip grep entirely for commands without "sleep"
if [[ "$COMMAND" != *sleep* ]]; then
    echo '{}'
    exit 0
fi

# Find all sleep durations in the command and check each one.
# Matches: sleep 600, sleep 600s, sleep 10m, sleep 1h, sleep 0.5h
# Works in chains (sleep 30 && ...) and loops (while ...; sleep 300; done)

MAX_SLEEP=0
MAX_SLEEP_ORIGINAL=""

# Extract all sleep arguments using grep
# Pattern: sleep followed by a number with optional suffix
# Prefix alternation covers: start-of-line, statement separators, subshells
SLEEP_MATCHES=""
if command -v grep >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # Dollar sign and backtick are literal regex chars, not expansions
    SLEEP_MATCHES=$(printf '%s\n' "$COMMAND" | grep -oE '(^|[;&|$(`]|&&|\|\||do |then )[[:space:]]*sleep[[:space:]]+[0-9]+(\.[0-9]+)?[smh]?' | grep -oE '[0-9]+(\.[0-9]+)?[smh]?$') || true
fi

if [ -z "$SLEEP_MATCHES" ]; then
    echo '{}'
    exit 0
fi

while IFS= read -r match; do
    [ -z "$match" ] && continue

    SECONDS_VAL=0
    ORIGINAL="$match"

    # Extract numeric part and suffix
    if [[ "$match" =~ ^([0-9]+(\.[0-9]+)?)([smh]?)$ ]]; then
        NUM="${BASH_REMATCH[1]}"
        SUFFIX="${BASH_REMATCH[3]}"

        case "$SUFFIX" in
            h)
                # Hours to seconds — use integer arithmetic (bash doesn't do float)
                # Handle decimals by multiplying by 3600
                if [[ "$NUM" == *.* ]]; then
                    # Split on decimal point
                    WHOLE="${NUM%%.*}"
                    FRAC="${NUM#*.}"
                    # Pad/truncate fraction to 3 digits for millisecond precision
                    FRAC="${FRAC}000"
                    FRAC="${FRAC:0:3}"
                    SECONDS_VAL=$(( (WHOLE * 3600) + (FRAC * 3600 / 1000) ))
                else
                    SECONDS_VAL=$(( NUM * 3600 ))
                fi
                ;;
            m)
                if [[ "$NUM" == *.* ]]; then
                    WHOLE="${NUM%%.*}"
                    FRAC="${NUM#*.}"
                    FRAC="${FRAC}000"
                    FRAC="${FRAC:0:3}"
                    SECONDS_VAL=$(( (WHOLE * 60) + (FRAC * 60 / 1000) ))
                else
                    SECONDS_VAL=$(( NUM * 60 ))
                fi
                ;;
            s|"")
                if [[ "$NUM" == *.* ]]; then
                    WHOLE="${NUM%%.*}"
                    SECONDS_VAL="$WHOLE"
                else
                    SECONDS_VAL="$NUM"
                fi
                ;;
        esac
    fi

    if [ "$SECONDS_VAL" -gt "$MAX_SLEEP" ] 2>/dev/null; then
        MAX_SLEEP="$SECONDS_VAL"
        MAX_SLEEP_ORIGINAL="$ORIGINAL"
    fi
done <<< "$SLEEP_MATCHES"

# ─── Check against threshold ────────────────────────────────────

if [ "$MAX_SLEEP" -le "$THRESHOLD" ] 2>/dev/null; then
    echo '{}'
    exit 0
fi

# ─── Log blocked sleep for observability ────────────────────────

LOG_DIR="${HOME}/.claude/logs"
if [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null; then
    LOG_FILE="${LOG_DIR}/sleep-cap.log"
    # Truncate log if it exceeds 1MB to prevent unbounded growth
    if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
        tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
    fi
    printf '%s sleep-cap: BLOCKED sleep %s (%ds > %ds threshold) in command: %.200s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)" \
        "$MAX_SLEEP_ORIGINAL" "$MAX_SLEEP" "$THRESHOLD" "$COMMAND" \
        >> "$LOG_FILE" 2>/dev/null || true
fi

# ─── Build block response ───────────────────────────────────────

REASON="sleep ${MAX_SLEEP_ORIGINAL} (${MAX_SLEEP}s) exceeds the ${THRESHOLD}s threshold. Long sleeps waste wall-clock time."
SUGGESTION="Instead of sleeping, use the Bash tool with run_in_background: true for long-running commands, or use a shorter polling interval (5-10s). If you must wait, keep sleep under ${THRESHOLD}s. To override this check, add '# sleep-cap:ignore' as a comment in your command."

# Use jq if available for proper JSON escaping, otherwise use printf
if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg reason "$REASON" \
        --arg suggestion "$SUGGESTION" \
        '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "block",
                permissionDecisionReason: $reason,
                additionalContext: $suggestion
            }
        }'
else
    # Escape for JSON (minimal: backslash and double-quote)
    REASON_ESC="${REASON//\\/\\\\}"
    REASON_ESC="${REASON_ESC//\"/\\\"}"
    SUGGESTION_ESC="${SUGGESTION//\\/\\\\}"
    SUGGESTION_ESC="${SUGGESTION_ESC//\"/\\\"}"

    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "block",\n    "permissionDecisionReason": "%s",\n    "additionalContext": "%s"\n  }\n}\n' \
        "$REASON_ESC" "$SUGGESTION_ESC"
fi

exit 0
