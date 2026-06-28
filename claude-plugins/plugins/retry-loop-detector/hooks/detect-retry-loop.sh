#!/usr/bin/env bash
# detect-retry-loop.sh - PreToolUse hook for retry loop detection
#
# Tracks consecutive calls to the same tool with identical (normalized)
# arguments. Warns at 3 consecutive identical calls, blocks at 5+.
#
# State is stored in a temp file keyed by user ID and hostname to
# persist across invocations within a session while avoiding collisions
# on shared network storage (NFS).
#
# Escape hatch: set DISABLE_RETRY_LOOP_DETECTOR=1 to bypass.
#
# Input:  JSON on stdin from Claude Code hook system
# Output: JSON on stdout with warning or {}

set -euo pipefail

trap 'echo "{}"; exit 0' ERR

# ---- Configuration ----
WARN_THRESHOLD=3
BLOCK_THRESHOLD=5
STATE_DIR="${TMPDIR:-/tmp}"
# Scope state by user ID and hostname to prevent collisions on shared storage
HOSTNAME_SAFE=$(hostname -s 2>/dev/null | tr -cd 'a-zA-Z0-9_.-' || echo "local")
STATE_FILE="${STATE_DIR}/claude-retry-loop-detector-$(id -u)-${HOSTNAME_SAFE}.state"
LOG_FILE="${STATE_DIR}/claude-retry-loop-detector-${HOSTNAME_SAFE}.log"

# ---- Escape hatch ----
if [ "${DISABLE_RETRY_LOOP_DETECTOR:-0}" = "1" ]; then
    echo '{}'
    exit 0
fi

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

# ---- Hash helper: prefer shasum, fall back to sha256sum ----
_hash() {
    shasum -a 256 2>/dev/null || sha256sum 2>/dev/null
}

# ---- Extract tool_name and compute args fingerprint ----
TOOL_NAME=""
ARGS_HASH=""

if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
    # Normalize tool_input: sort keys, compact, then hash
    ARGS_HASH=$(printf '%s\n' "$INPUT" | jq -Sc '.tool_input // {}' 2>/dev/null | _hash | cut -d' ' -f1) || true
else
    # Fallback: regex extraction for tool name, hash full input
    if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        TOOL_NAME="${BASH_REMATCH[1]}"
    fi
    ARGS_HASH=$(printf '%s\n' "$INPUT" | _hash | cut -d' ' -f1) || true
fi

if [ -z "$TOOL_NAME" ]; then
    echo '{}'
    exit 0
fi

# Combine tool name and args hash for the fingerprint
FINGERPRINT="${TOOL_NAME}:${ARGS_HASH}"

# ---- Read current state ----
LAST_FINGERPRINT=""
CURRENT_COUNT=0

if [ -f "$STATE_FILE" ]; then
    # State file format: line 1 = fingerprint, line 2 = count
    { read -r LAST_FINGERPRINT; read -r STORED_COUNT; } < "$STATE_FILE" 2>/dev/null || true
    if [[ "${STORED_COUNT:-}" =~ ^[0-9]+$ ]]; then
        CURRENT_COUNT="$STORED_COUNT"
    fi
fi

# ---- Compare and update ----
if [ "$FINGERPRINT" = "$LAST_FINGERPRINT" ]; then
    NEW_COUNT=$((CURRENT_COUNT + 1))
else
    NEW_COUNT=1
fi

# Write updated state
printf '%s\n%d\n' "$FINGERPRINT" "$NEW_COUNT" > "$STATE_FILE" 2>/dev/null || true

# ---- Check thresholds ----
if [ "$NEW_COUNT" -lt "$WARN_THRESHOLD" ]; then
    echo '{}'
    exit 0
fi

# ---- Log retry event ----
printf '%s [RETRY] tool=%s count=%d\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL_NAME" "$NEW_COUNT" \
    >> "$LOG_FILE" 2>/dev/null || true

# ---- Generate warning or block ----
if [ "$NEW_COUNT" -ge "$BLOCK_THRESHOLD" ]; then
    WARNING_MSG="BLOCKED: ${TOOL_NAME} called ${NEW_COUNT} times with identical arguments. This is a retry loop. STOP and ask the user what they want before continuing. If the user told you to stop or try something different, do NOT retry this approach. Set DISABLE_RETRY_LOOP_DETECTOR=1 to bypass."
    REASON="Retry loop detector: ${NEW_COUNT} consecutive identical calls (blocked)"
    DECISION="block"
else
    WARNING_MSG="WARNING: You have called ${TOOL_NAME} with the same arguments ${NEW_COUNT} times consecutively. This appears to be a retry loop. Consider: (1) changing your approach, (2) using a different tool, (3) modifying your arguments. If the user told you to stop, do NOT continue this approach."
    REASON="Retry loop detector: ${NEW_COUNT} consecutive identical calls"
    DECISION="allow"
fi

if command -v jq >/dev/null 2>&1; then
    if [ "$DECISION" = "block" ]; then
        jq -n \
            --arg reason "$WARNING_MSG" \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "block", permissionDecisionReason: $reason}}'
    else
        jq -n \
            --arg ctx "$WARNING_MSG" \
            --arg reason "$REASON" \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason, additionalContext: $ctx}}'
    fi
else
    if [ "$DECISION" = "block" ]; then
        ESCAPED="${WARNING_MSG//\\/\\\\}"
        ESCAPED="${ESCAPED//\"/\\\"}"
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"%s"}}\n' "$ESCAPED"
    else
        ESCAPED_MSG="${WARNING_MSG//\\/\\\\}"
        ESCAPED_MSG="${ESCAPED_MSG//\"/\\\"}"
        ESCAPED_REASON="${REASON//\\/\\\\}"
        ESCAPED_REASON="${ESCAPED_REASON//\"/\\\"}"
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s","additionalContext":"%s"}}\n' "$ESCAPED_REASON" "$ESCAPED_MSG"
    fi
fi

exit 0
