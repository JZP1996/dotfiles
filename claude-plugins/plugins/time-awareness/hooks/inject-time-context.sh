#!/usr/bin/env bash
# inject-time-context.sh - PreToolUse hook for time awareness
#
# Injects the current system time and timezone into Claude's context
# via additionalContext on every tool call. Invisible to the user.
#
# Input: JSON on stdin from Claude Code's hook system
# Output: JSON on stdout with hookSpecificOutput (opted-in) or {} (not opted-in)
#
# Opt-in: Requires .time-awareness.json in $HOME or repo root.
#
# Config schema:
#   {
#     "enabled": true,
#     "timezone": "America/Los_Angeles",
#     "format": "iso"
#   }
#
# Dependencies: bash, date, jq (with pure-bash fallback), git
#
# Security:
#   - No eval anywhere
#   - Static template output only (no user-controlled values in additionalContext)
#   - Timezone validated via TZ=<value> date (invalid → system default fallback)
#   - Control characters rejected in config values
#   - Every error path → {} + exit 0

set -euo pipefail

# Fail-safe: any unexpected error outputs empty JSON
trap 'echo "{}"; exit 0' ERR

# ─── Windows path normalization ───────────────────────────────────
# On Windows (Git Bash via cmd.exe), paths may use backslashes.
# Normalize to forward slashes for POSIX compatibility.
_normalize_path() {
    local p="$1"
    # Convert Windows backslashes to forward slashes
    if [[ "$p" == *\\* ]]; then
        p="${p//\\//}"
    fi
    printf '%s' "$p"
}

# Normalize HOME if it has Windows backslashes
if [ -n "${HOME:-}" ] && [[ "$HOME" == *\\* ]]; then
    HOME="$(_normalize_path "$HOME")"
fi

# ─── Read stdin ───────────────────────────────────────────────────

INPUT=""
if ! INPUT=$(cat 2>/dev/null); then
    echo '{}'
    exit 0
fi

if [ -z "$INPUT" ]; then
    echo '{}'
    exit 0
fi

# ─── Extract cwd from stdin ──────────────────────────────────────

CWD=""
if command -v jq >/dev/null 2>&1; then
    CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
else
    if [[ "$INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        CWD="${BASH_REMATCH[1]}"
    fi
fi

# Normalize CWD (may be Windows-style from Claude Code on Windows)
if [ -n "$CWD" ]; then
    CWD="$(_normalize_path "$CWD")"
fi

# ─── Find config file (opt-in check) ─────────────────────────────

CONFIG_FILE=""

# Search order: $HOME first, then repo root
if [ -n "${HOME:-}" ] && [ -f "${HOME}/.time-awareness.json" ]; then
    CONFIG_FILE="${HOME}/.time-awareness.json"
else
    # Try to find repo root
    REPO_ROOT=""
    if command -v git >/dev/null 2>&1 && [ -n "$CWD" ] && [ -d "$CWD" ]; then
        REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || true
    fi

    if [ -n "$REPO_ROOT" ] && [ -f "${REPO_ROOT}/.time-awareness.json" ]; then
        CONFIG_FILE="${REPO_ROOT}/.time-awareness.json"
    fi
fi

# Not opted-in — exit silently
if [ -z "$CONFIG_FILE" ]; then
    echo '{}'
    exit 0
fi

# ─── Read and parse config ────────────────────────────────────────

CONFIG_CONTENT=""
CONFIG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null) || true

if [ -z "$CONFIG_CONTENT" ]; then
    echo '{}'
    exit 0
fi

# Reject control characters in config content (defense-in-depth)
# Allow normal whitespace (space, tab, newline, carriage return for Windows line endings)
if [[ "$CONFIG_CONTENT" =~ [$'\x01'-$'\x08'$'\x0b'$'\x0c'$'\x0e'-$'\x1f'$'\x7f'] ]]; then
    echo '{}'
    exit 0
fi

ENABLED="true"
TIMEZONE=""
FORMAT="iso"

if command -v jq >/dev/null 2>&1; then
    # jq available — robust JSON parsing
    ENABLED=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r 'if has("enabled") then (.enabled | tostring) else "true" end' 2>/dev/null) || ENABLED="true"
    TIMEZONE=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.timezone // empty' 2>/dev/null) || TIMEZONE=""
    FORMAT=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.format // "iso"' 2>/dev/null) || FORMAT="iso"

    # Validate JSON was parseable (jq returns empty on invalid JSON)
    if ! printf '%s\n' "$CONFIG_CONTENT" | jq . >/dev/null 2>&1; then
        # Malformed JSON — use defaults (enabled, system TZ, iso format)
        ENABLED="true"
        TIMEZONE=""
        FORMAT="iso"
    fi
else
    # Pure bash fallback — extract fields with regex
    if [[ "$CONFIG_CONTENT" =~ \"enabled\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
        ENABLED="${BASH_REMATCH[1]}"
    fi
    if [[ "$CONFIG_CONTENT" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        TIMEZONE="${BASH_REMATCH[1]}"
    fi
    if [[ "$CONFIG_CONTENT" =~ \"format\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        FORMAT="${BASH_REMATCH[1]}"
    fi
fi

# ─── Check enabled flag ──────────────────────────────────────────

if [ "$ENABLED" = "false" ]; then
    echo '{}'
    exit 0
fi

# ─── Validate timezone ───────────────────────────────────────────

# Reject timezone values with control characters or shell metacharacters
if [ -n "$TIMEZONE" ]; then
    # Only allow alphanumeric, forward slash, underscore, dash, plus, dot
    if [[ ! "$TIMEZONE" =~ ^[A-Za-z0-9/_+.-]+$ ]]; then
        TIMEZONE=""
    fi
fi

# Validate timezone by attempting to use it with date
# Invalid timezone → falls back to system default
if [ -n "$TIMEZONE" ]; then
    if ! TZ="$TIMEZONE" date +%Z >/dev/null 2>&1; then
        TIMEZONE=""
    fi
fi

# ─── Validate format ─────────────────────────────────────────────

# Only allow known format values
case "$FORMAT" in
    iso|unix) ;;
    *) FORMAT="iso" ;;
esac

# ─── Verify date command ─────────────────────────────────────────

if ! command -v date >/dev/null 2>&1; then
    echo '{}'
    exit 0
fi

# ─── Generate timestamp ──────────────────────────────────────────

TIMESTAMP=""

if [ "$FORMAT" = "unix" ]; then
    # Unix epoch format
    if [ -n "$TIMEZONE" ]; then
        TIMESTAMP=$(TZ="$TIMEZONE" date +%s 2>/dev/null) || true
    else
        TIMESTAMP=$(date +%s 2>/dev/null) || true
    fi

    if [ -z "$TIMESTAMP" ]; then
        echo '{}'
        exit 0
    fi

    # Output for unix format — use printf to avoid shell expansion in template
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Time context injection (opt-in enabled)",\n    "additionalContext": "[System time: %s unix]"\n  }\n}\n' "$TIMESTAMP"
else
    # ISO format: 2026-02-27 14:32:05 PST (Thu)
    # Use POSIX-compatible format strings that work on both GNU and BSD date
    if [ -n "$TIMEZONE" ]; then
        TIMESTAMP=$(TZ="$TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z (%a)' 2>/dev/null) || true
    else
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z (%a)' 2>/dev/null) || true
    fi

    if [ -z "$TIMESTAMP" ]; then
        echo '{}'
        exit 0
    fi

    # Output for iso format — use printf to avoid shell expansion in template
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Time context injection (opt-in enabled)",\n    "additionalContext": "[System time: %s]"\n  }\n}\n' "$TIMESTAMP"
fi

exit 0
