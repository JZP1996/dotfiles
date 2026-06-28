#!/usr/bin/env bash
# check-breaker.sh - PreToolUse hook for circuit breaker
#
# Before each tool call, checks whether the circuit breaker has tripped
# for the fingerprint of the incoming call. If the same command has failed
# TRIP_THRESHOLD consecutive times, blocks execution and forces a new approach.
#
# Bypass: include "# circuit-breaker: override" in the command text.
#
# Input:  JSON on stdin from Claude Code hook system
#   { "tool_name": "...", "tool_input": {...} }
#
# Output: JSON on stdout
#   - Breaker tripped: block with reason
#   - Otherwise: {} (allow)
#
# State: $TMPDIR/claude-circuit-breaker-<uid>-<pid>.json (shared with track-failure.sh)
#
# Dependencies: bash 3.2+, jq (with pure-bash fallback)
#
# Security:
#   - No eval anywhere
#   - Read-only check against state file
#   - Every error path -> {} + exit 0

set -euo pipefail

trap 'echo "{}"; exit 0' ERR

# ---- Configuration ----
TRIP_THRESHOLD=3
STATE_DIR="${TMPDIR:-/tmp}"
AGENT_PID="${CIRCUIT_BREAKER_PID:-${PPID:-$$}}"
STATE_FILE="${STATE_DIR}/claude-circuit-breaker-$(id -u)-${AGENT_PID}.json"

# ---- Read stdin ----
INPUT=""
if ! INPUT=$(cat 2>/dev/null); then
    echo '{}'
    exit 0
fi

if [ -z "$INPUT" ]; then
    echo '{}'
    exit 0
fi

# ---- Extract fields ----
TOOL_NAME=""
TOOL_INPUT=""

if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
    TOOL_INPUT=$(printf '%s\n' "$INPUT" | jq -r '(.tool_input | tostring) // empty' 2>/dev/null) || true
else
    if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        TOOL_NAME="${BASH_REMATCH[1]}"
    fi
    if [[ "$INPUT" =~ \"tool_input\"[[:space:]]*:[[:space:]]*\{([^}]*)\} ]]; then
        TOOL_INPUT="${BASH_REMATCH[1]}"
    fi
fi

if [ -z "$TOOL_NAME" ]; then
    echo '{}'
    exit 0
fi

# ---- Check bypass ----
if [[ "${TOOL_INPUT:-}" == *"circuit-breaker: override"* ]]; then
    echo '{}'
    exit 0
fi

# ---- Compute fingerprint (same algorithm as track-failure.sh) ----
NORMALIZED_INPUT=$(printf '%s:%s' "$TOOL_NAME" "$TOOL_INPUT" | tr -s '[:space:]' ' ')

if command -v md5sum >/dev/null 2>&1; then
    FINGERPRINT=$(printf '%s' "$NORMALIZED_INPUT" | md5sum | cut -d' ' -f1)
elif command -v md5 >/dev/null 2>&1; then
    FINGERPRINT=$(printf '%s' "$NORMALIZED_INPUT" | md5 -q)
else
    FINGERPRINT=$(printf '%s' "$NORMALIZED_INPUT" | head -c 64 | tr -d '"\\/')
fi

# ---- Check state ----
if [ ! -f "$STATE_FILE" ]; then
    echo '{}'
    exit 0
fi

FAIL_COUNT=0

if command -v jq >/dev/null 2>&1; then
    STATE_CONTENT=$(cat "$STATE_FILE" 2>/dev/null) || STATE_CONTENT="{}"
    FAIL_COUNT=$(printf '%s' "$STATE_CONTENT" | jq -r --arg fp "$FINGERPRINT" '.[$fp].count // 0' 2>/dev/null) || FAIL_COUNT=0
    LAST_ERROR=$(printf '%s' "$STATE_CONTENT" | jq -r --arg fp "$FINGERPRINT" '.[$fp].error // "unknown"' 2>/dev/null) || LAST_ERROR="unknown"
else
    if [ -f "${STATE_FILE}.${FINGERPRINT}" ]; then
        FAIL_COUNT=$(cat "${STATE_FILE}.${FINGERPRINT}" 2>/dev/null) || FAIL_COUNT=0
    fi
    LAST_ERROR="unknown"
fi

# ---- Evaluate ----
if [ "$FAIL_COUNT" -ge "$TRIP_THRESHOLD" ]; then
    BLOCK_MSG="CIRCUIT BREAKER TRIPPED: This command has failed ${FAIL_COUNT} consecutive times with the same error. You MUST try a different approach. Do NOT retry the same command. Last error: ${LAST_ERROR:-unknown}. To override, prefix your command with '# circuit-breaker: override'."

    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg reason "$BLOCK_MSG" \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "block", permissionDecisionReason: $reason}}'
    else
        ESCAPED="${BLOCK_MSG//\\/\\\\}"
        ESCAPED="${ESCAPED//\"/\\\"}"
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"%s"}}\n' "$ESCAPED"
    fi
    exit 0
fi

echo '{}'
exit 0
