#!/usr/bin/env bash
# check-compaction.sh - PreToolUse hook for compaction monitoring
#
# Monitors context utilization (via ~/.claude/token_usage.json) and
# compaction count (via ~/.claude/compaction-count.txt) to warn when
# session quality is degrading due to context pressure.
#
# Input: JSON on stdin from Claude Code's hook system
# Output: JSON on stdout with hookSpecificOutput (warning) or {} (below thresholds)
#
# Opt-in: Requires .compaction-monitor.json in $HOME or repo root.
#
# Config schema:
#   {
#     "enabled": true,
#     "warn_utilization_pct": 75,
#     "critical_utilization_pct": 90,
#     "warn_compaction_count": 2,
#     "critical_compaction_count": 4
#   }
#
# Dependencies: bash, jq (with pure-bash fallback), git
#
# Security:
#   - No eval anywhere
#   - Config values validated and sanitized
#   - Control characters rejected in config values
#   - Every error path -> {} + exit 0

set -euo pipefail

# Fail-safe: any unexpected error outputs empty JSON
trap 'echo "{}"; exit 0' ERR

# --- Windows path normalization ---
_normalize_path() {
    local p="$1"
    if [[ "$p" == *\\* ]]; then
        p="${p//\\//}"
    fi
    printf '%s' "$p"
}

if [ -n "${HOME:-}" ] && [[ "$HOME" == *\\* ]]; then
    HOME="$(_normalize_path "$HOME")"
fi

# --- Read stdin ---

INPUT=""
if ! INPUT=$(cat 2>/dev/null); then
    echo '{}'
    exit 0
fi

if [ -z "$INPUT" ]; then
    echo '{}'
    exit 0
fi

# --- Extract cwd from stdin ---

CWD=""
if command -v jq >/dev/null 2>&1; then
    CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
else
    if [[ "$INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        CWD="${BASH_REMATCH[1]}"
    fi
fi

if [ -n "$CWD" ]; then
    CWD="$(_normalize_path "$CWD")"
fi

# --- Find config file (opt-in check) ---

CONFIG_FILE=""

if [ -n "${HOME:-}" ] && [ -f "${HOME}/.compaction-monitor.json" ]; then
    CONFIG_FILE="${HOME}/.compaction-monitor.json"
else
    REPO_ROOT=""
    if command -v git >/dev/null 2>&1 && [ -n "$CWD" ] && [ -d "$CWD" ]; then
        REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || true
    fi

    if [ -n "$REPO_ROOT" ] && [ -f "${REPO_ROOT}/.compaction-monitor.json" ]; then
        CONFIG_FILE="${REPO_ROOT}/.compaction-monitor.json"
    fi
fi

# Not opted-in
if [ -z "$CONFIG_FILE" ]; then
    echo '{}'
    exit 0
fi

# --- Read and parse config ---

CONFIG_CONTENT=""
CONFIG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null) || true

if [ -z "$CONFIG_CONTENT" ]; then
    echo '{}'
    exit 0
fi

# Reject control characters
if [[ "$CONFIG_CONTENT" =~ [$'\x01'-$'\x08'$'\x0b'$'\x0c'$'\x0e'-$'\x1f'$'\x7f'] ]]; then
    echo '{}'
    exit 0
fi

ENABLED="true"
WARN_UTIL_PCT="75"
CRIT_UTIL_PCT="90"
WARN_COMPACT_COUNT="2"
CRIT_COMPACT_COUNT="4"

if command -v jq >/dev/null 2>&1; then
    ENABLED=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r 'if has("enabled") then (.enabled | tostring) else "true" end' 2>/dev/null) || ENABLED="true"
    WARN_UTIL_PCT=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.warn_utilization_pct // 75 | tostring' 2>/dev/null) || WARN_UTIL_PCT="75"
    CRIT_UTIL_PCT=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.critical_utilization_pct // 90 | tostring' 2>/dev/null) || CRIT_UTIL_PCT="90"
    WARN_COMPACT_COUNT=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.warn_compaction_count // 2 | tostring' 2>/dev/null) || WARN_COMPACT_COUNT="2"
    CRIT_COMPACT_COUNT=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.critical_compaction_count // 4 | tostring' 2>/dev/null) || CRIT_COMPACT_COUNT="4"

else
    # Pure bash fallback
    TRIMMED="${CONFIG_CONTENT#"${CONFIG_CONTENT%%[![:space:]]*}"}"
    if [[ ! "$TRIMMED" == "{"* ]]; then
        ENABLED="true"
    else
        if [[ "$CONFIG_CONTENT" =~ \"enabled\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
            ENABLED="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"warn_utilization_pct\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            WARN_UTIL_PCT="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"critical_utilization_pct\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            CRIT_UTIL_PCT="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"warn_compaction_count\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            WARN_COMPACT_COUNT="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"critical_compaction_count\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            CRIT_COMPACT_COUNT="${BASH_REMATCH[1]}"
        fi
    fi
fi

if [ "$ENABLED" = "false" ]; then
    echo '{}'
    exit 0
fi

# --- Validate numeric config values ---

validate_pct() {
    local val="$1" default="$2"
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        printf '%s' "$default"
        return
    fi
    if [ "$val" -gt 100 ] 2>/dev/null; then
        printf '%s' "100"
        return
    fi
    if [ "$val" -lt 1 ] 2>/dev/null; then
        printf '%s' "$default"
        return
    fi
    printf '%s' "$val"
}

validate_count() {
    local val="$1" default="$2"
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        printf '%s' "$default"
        return
    fi
    if [ "$val" -lt 1 ] 2>/dev/null; then
        printf '%s' "$default"
        return
    fi
    if [ "$val" -gt 100 ] 2>/dev/null; then
        printf '%s' "100"
        return
    fi
    printf '%s' "$val"
}

WARN_UTIL_PCT=$(validate_pct "$WARN_UTIL_PCT" "75")
CRIT_UTIL_PCT=$(validate_pct "$CRIT_UTIL_PCT" "90")
WARN_COMPACT_COUNT=$(validate_count "$WARN_COMPACT_COUNT" "2")
CRIT_COMPACT_COUNT=$(validate_count "$CRIT_COMPACT_COUNT" "4")

# --- Read context utilization ---

UTIL_PCT="0"
ALERT_LEVEL="NORMAL"

TOKEN_FILE="${HOME}/.claude/token_usage.json"
if [ -f "$TOKEN_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
        UTIL_PCT=$(jq -r '.utilization_pct // 0 | floor | tostring' "$TOKEN_FILE" 2>/dev/null) || UTIL_PCT="0"
        ALERT_LEVEL=$(jq -r '.alert_level // "NORMAL"' "$TOKEN_FILE" 2>/dev/null) || ALERT_LEVEL="NORMAL"
    else
        TOKEN_CONTENT=$(cat "$TOKEN_FILE" 2>/dev/null) || true
        if [[ "$TOKEN_CONTENT" =~ \"utilization_pct\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            UTIL_PCT="${BASH_REMATCH[1]}"
        fi
        if [[ "$TOKEN_CONTENT" =~ \"alert_level\"[[:space:]]*:[[:space:]]*\"([A-Z]+)\" ]]; then
            ALERT_LEVEL="${BASH_REMATCH[1]}"
        fi
    fi
fi

# Validate UTIL_PCT is numeric
if [[ ! "$UTIL_PCT" =~ ^[0-9]+$ ]]; then
    UTIL_PCT="0"
fi

# --- Read compaction count ---

COMPACT_COUNT="0"
COMPACT_FILE="${HOME}/.claude/compaction-count.txt"
if [ -f "$COMPACT_FILE" ]; then
    COMPACT_COUNT=$(cat "$COMPACT_FILE" 2>/dev/null) || COMPACT_COUNT="0"
    # Validate numeric
    if [[ ! "$COMPACT_COUNT" =~ ^[0-9]+$ ]]; then
        COMPACT_COUNT="0"
    fi
fi

# --- Determine warning level ---
# CRITICAL > WARNING > CAUTION > NORMAL

LEVEL="NORMAL"

if [ "$UTIL_PCT" -ge "$WARN_UTIL_PCT" ] 2>/dev/null; then
    LEVEL="CAUTION"
fi
if [ "$COMPACT_COUNT" -ge "$WARN_COMPACT_COUNT" ] 2>/dev/null; then
    LEVEL="CAUTION"
fi
if [ "$UTIL_PCT" -ge "$CRIT_UTIL_PCT" ] 2>/dev/null; then
    LEVEL="WARNING"
fi
if [ "$COMPACT_COUNT" -ge "$CRIT_COMPACT_COUNT" ] 2>/dev/null; then
    LEVEL="WARNING"
fi

# Also respect alert_level from token_usage.json
case "$ALERT_LEVEL" in
    WARNING|CRITICAL)
        LEVEL="WARNING"
        ;;
    CAUTION)
        if [ "$LEVEL" = "NORMAL" ]; then
            LEVEL="CAUTION"
        fi
        ;;
esac

# --- Output ---

if [ "$LEVEL" = "NORMAL" ]; then
    echo '{}'
    exit 0
fi

if [ "$LEVEL" = "CAUTION" ]; then
    MSG="[Context pressure: ${UTIL_PCT}% utilized, ${COMPACT_COUNT} compactions. Lower delegation threshold to weighted 2. Delegate aggressively to preserve context quality. Options to manage context: (1) /compact - proactively compress context now, before automatic compaction loses more detail. (2) Delegate remaining work to a subagent - preserves your findings while giving the work a fresh, full context window. (3) /handoff - checkpoint progress to SESSION-BOOTSTRAP.md and resume in a new session with full context.]"
else
    MSG="[HIGH CONTEXT PRESSURE: ${UTIL_PCT}% utilized, ${COMPACT_COUNT} compactions. Quality is degrading. Recommended actions: (1) /compact - compress context immediately to reclaim space, though some detail will be lost. (2) /clear - start a completely fresh conversation if context is too degraded to be useful. (3) Delegate ALL remaining work to subagents - each gets a fresh context window and returns synthesized results. (4) /handoff - checkpoint everything to SESSION-BOOTSTRAP.md and continue in a new session. This is the safest option when quality is visibly degraded.]"
fi

# Escape backslashes and quotes for safe JSON embedding
MSG_ESCAPED="${MSG//\\/\\\\}"
MSG_ESCAPED="${MSG_ESCAPED//\"/\\\"}"

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Compaction monitor (%s)",\n    "additionalContext": "%s"\n  }\n}\n' "$LEVEL" "$MSG_ESCAPED"

exit 0
