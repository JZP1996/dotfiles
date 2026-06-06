#!/usr/bin/env bash
# track-failure.sh - PostToolUse hook for circuit breaker
#
# After each tool call, checks whether it failed. If it did, computes a
# fingerprint (tool_name + normalized args hash) and records the consecutive
# failure count in a PID-scoped state file. Successful calls reset the
# counter for that fingerprint.
#
# Transient errors (429, ETIMEDOUT, ECONNRESET, DNS failures) are excluded
# from tracking because retrying them is appropriate.
#
# Input:  JSON on stdin from Claude Code hook system
#   { "tool_name": "...", "tool_input": {...}, "tool_result": "..." }
#
# Output: JSON on stdout
#   - On failure recorded: additionalContext with warning
#   - Otherwise: {} (no-op)
#
# State: $TMPDIR/claude-circuit-breaker-<uid>-<pid>.json
#
# Dependencies: bash 3.2+, jq (with pure-bash fallback)
#
# Security:
#   - No eval anywhere
#   - Read-only analysis of tool result strings
#   - State writes use atomic mv pattern
#   - Every error path -> {} + exit 0

set -euo pipefail

trap 'echo "{}"; exit 0' ERR

# ---- Configuration ----
TRIP_THRESHOLD=3
STATE_DIR="${TMPDIR:-/tmp}"
# PID-scoped state to prevent cross-agent interference
# CIRCUIT_BREAKER_PID allows test injection; PPID gives Claude Code process in production
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
RESULT=""

if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
    TOOL_INPUT=$(printf '%s\n' "$INPUT" | jq -r '(.tool_input | tostring) // empty' 2>/dev/null) || true
    RESULT=$(printf '%s\n' "$INPUT" | jq -r '
        if .tool_result | type == "string" then .tool_result
        elif .tool_result.content | type == "string" then .tool_result.content
        elif .tool_result.stdout | type == "string" then .tool_result.stdout
        elif .tool_result.stderr | type == "string" then .tool_result.stderr
        else (.tool_result | tostring)
        end // empty' 2>/dev/null | head -c 3000) || true
else
    if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        TOOL_NAME="${BASH_REMATCH[1]}"
    fi
    if [[ "$INPUT" =~ \"tool_input\"[[:space:]]*:[[:space:]]*\{([^}]*)\} ]]; then
        TOOL_INPUT="${BASH_REMATCH[1]}"
    fi
    RESULT="${INPUT:0:3000}"
fi

if [ -z "$TOOL_NAME" ]; then
    echo '{}'
    exit 0
fi

# ---- Compute fingerprint ----
# Fingerprint = md5 of tool_name + normalized tool_input
# This groups identical commands together regardless of whitespace
NORMALIZED_INPUT=$(printf '%s:%s' "$TOOL_NAME" "$TOOL_INPUT" | tr -s '[:space:]' ' ')

if command -v md5sum >/dev/null 2>&1; then
    FINGERPRINT=$(printf '%s' "$NORMALIZED_INPUT" | md5sum | cut -d' ' -f1)
elif command -v md5 >/dev/null 2>&1; then
    FINGERPRINT=$(printf '%s' "$NORMALIZED_INPUT" | md5 -q)
else
    # Fallback: use first 64 chars as fingerprint
    FINGERPRINT=$(printf '%s' "$NORMALIZED_INPUT" | head -c 64 | tr -d '"\\/')
fi

# ---- Detect failure ----
HAS_ERROR=false
ERROR_LINE=""
EXIT_CODE_FOUND=false

# Check exit code pattern (ground truth when available)
if [[ "${RESULT:-}" =~ [Ee]xit[[:space:]]*[Cc]ode[[:space:]]*:?[[:space:]]*([0-9]+) ]]; then
    EXIT_CODE_FOUND=true
    if [ "${BASH_REMATCH[1]}" != "0" ]; then
        HAS_ERROR=true
    fi
fi

# Fall back to pattern matching only when no exit code was detected.
# Patterns like "error:" and "Exception" can match legitimate output
# (grep results, filenames, commit messages) so we avoid them when
# a reliable exit code signal already determined success/failure.
if [ "$EXIT_CODE_FOUND" = false ] && [ "$HAS_ERROR" = false ]; then
    for pat in "command not found" "No such file or directory" "Permission denied" \
               "Connection refused" "fatal:" "ENOENT" "EACCES" \
               "EPERM" "Traceback" "panic:"; do
        if [[ "${RESULT:-}" == *"$pat"* ]]; then
            HAS_ERROR=true
            # Grab first error line for display
            ERROR_LINE=$(printf '%s' "$RESULT" | grep -m1 "$pat" 2>/dev/null | head -c 120) || true
            break
        fi
    done
fi

# ---- Check transient error allowlist ----
# These errors are expected to be retried and should NOT trip the breaker
IS_TRANSIENT=false
if [ "$HAS_ERROR" = true ]; then
    R="${RESULT:-}"
    # HTTP 429 rate limit
    if [[ "$R" == *"429"* ]] && [[ "$R" == *"rate"* || "$R" == *"Rate"* || "$R" == *"Too Many"* || "$R" == *"too many"* ]]; then
        IS_TRANSIENT=true
    fi
    # HTTP 429 status code alone
    if [[ "$R" =~ [Ss]tatus[[:space:]]*:?[[:space:]]*429 ]]; then
        IS_TRANSIENT=true
    fi
    # Network transient errors
    for tpat in "ETIMEDOUT" "ECONNRESET" "ECONNREFUSED" "ENETUNREACH" \
                "retry-after" "Retry-After" "retry after" \
                "DNS resolution" "dns resolution" "getaddrinfo" "ENOTFOUND" \
                "Name or service not known" "Temporary failure in name resolution" \
                "Service Unavailable" "Bad Gateway" \
                "502 Bad Gateway" "503 Service Unavailable" \
                "HTTP 502" "HTTP 503" "status 502" "status 503" \
                "Status: 502" "Status: 503"; do
        if [[ "$R" == *"$tpat"* ]]; then
            IS_TRANSIENT=true
            break
        fi
    done
fi

if [ "$IS_TRANSIENT" = true ]; then
    echo '{}'
    exit 0
fi

# ---- Load state ----
# State format (JSON): { "<fingerprint>": { "count": N, "error": "..." }, ... }
STATE="{}"
if [ -f "$STATE_FILE" ]; then
    STATE=$(cat "$STATE_FILE" 2>/dev/null) || STATE="{}"
    # Validate it's JSON
    if command -v jq >/dev/null 2>&1; then
        if ! printf '%s' "$STATE" | jq empty 2>/dev/null; then
            STATE="{}"
        fi
    fi
fi

# ---- Update state ----
if [ "$HAS_ERROR" = true ]; then
    # Increment failure count
    if command -v jq >/dev/null 2>&1; then
        CURRENT_COUNT=$(printf '%s' "$STATE" | jq -r --arg fp "$FINGERPRINT" '.[$fp].count // 0' 2>/dev/null) || CURRENT_COUNT=0
        NEW_COUNT=$((CURRENT_COUNT + 1))
        ESCAPED_ERR=$(printf '%s' "${ERROR_LINE:-unknown}" | head -c 120)
        STATE=$(printf '%s' "$STATE" | jq --arg fp "$FINGERPRINT" --argjson count "$NEW_COUNT" --arg err "$ESCAPED_ERR" \
            '.[$fp] = {"count": $count, "error": $err}' 2>/dev/null) || true
    else
        # Pure bash fallback: simple file-based tracking
        NEW_COUNT=1
        if [ -f "${STATE_FILE}.${FINGERPRINT}" ]; then
            CURRENT_COUNT=$(cat "${STATE_FILE}.${FINGERPRINT}" 2>/dev/null) || CURRENT_COUNT=0
            NEW_COUNT=$((CURRENT_COUNT + 1))
        fi
        printf '%d' "$NEW_COUNT" > "${STATE_FILE}.${FINGERPRINT}" 2>/dev/null || true
    fi
else
    # Success: clear this fingerprint from state
    if command -v jq >/dev/null 2>&1; then
        STATE=$(printf '%s' "$STATE" | jq --arg fp "$FINGERPRINT" 'del(.[$fp])' 2>/dev/null) || true
    else
        rm -f "${STATE_FILE}.${FINGERPRINT}" 2>/dev/null || true
    fi
    NEW_COUNT=0
fi

# ---- Write state (atomic) ----
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$STATE" > "${STATE_FILE}.tmp" 2>/dev/null && \
        mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
fi

# ---- Produce output ----
if [ "$HAS_ERROR" = true ] && [ "${NEW_COUNT:-0}" -ge "$TRIP_THRESHOLD" ]; then
    WARN_MSG="[Circuit Breaker] This command has now failed ${NEW_COUNT} consecutive times with the same error. The next identical attempt will be BLOCKED. Try a different approach. Last error: ${ERROR_LINE:-unknown}"
    WARN_ESCAPED="${WARN_MSG//\\/\\\\}"
    WARN_ESCAPED="${WARN_ESCAPED//\"/\\\"}"
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PostToolUse",\n    "additionalContext": "%s"\n  }\n}\n' "$WARN_ESCAPED"
elif [ "$HAS_ERROR" = true ] && [ "${NEW_COUNT:-0}" -ge 2 ]; then
    INFO_MSG="[Circuit Breaker] Consecutive failure #${NEW_COUNT} for this command. Breaker trips at ${TRIP_THRESHOLD}."
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PostToolUse",\n    "additionalContext": "%s"\n  }\n}\n' "$INFO_MSG"
else
    echo '{}'
fi

exit 0
