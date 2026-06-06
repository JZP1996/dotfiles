#!/usr/bin/env bash
# summarize-context.sh - PreToolUse hook for conversation summary
#
# Injects a reminder into Claude's context to maintain a running
# conversation summary file. The hook does NOT generate the summary —
# it only reminds the agent to update it. The skill provides the
# behavioral instructions.
#
# Input: JSON on stdin from Claude Code's hook system
# Output: JSON on stdout with hookSpecificOutput (opted-in) or {} (not opted-in)
#
# Opt-in: Requires .conversation-summary.json in $HOME or repo root.
#
# Config schema:
#   {
#     "enabled": true,
#     "output_dir": "docs/local/summaries",
#     "max_lines": 500,
#     "update_frequency": "moderate"
#   }
#
# Dependencies: bash, jq (with pure-bash fallback), git
#
# Security:
#   - No eval anywhere
#   - Config values validated and sanitized before injection into additionalContext
#   - Control characters rejected in config values
#   - Path traversal rejected in output_dir
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
if [ -n "${HOME:-}" ] && [ -f "${HOME}/.conversation-summary.json" ]; then
    CONFIG_FILE="${HOME}/.conversation-summary.json"
else
    # Try to find repo root
    REPO_ROOT=""
    if command -v git >/dev/null 2>&1 && [ -n "$CWD" ] && [ -d "$CWD" ]; then
        REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || true
    fi

    if [ -n "$REPO_ROOT" ] && [ -f "${REPO_ROOT}/.conversation-summary.json" ]; then
        CONFIG_FILE="${REPO_ROOT}/.conversation-summary.json"
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
OUTPUT_DIR="docs/local/summaries"
MAX_LINES="500"
UPDATE_FREQUENCY="moderate"

if command -v jq >/dev/null 2>&1; then
    # jq available — robust JSON parsing
    ENABLED=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r 'if has("enabled") then (.enabled | tostring) else "true" end' 2>/dev/null) || ENABLED="true"
    OUTPUT_DIR=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.output_dir // "docs/local/summaries"' 2>/dev/null) || OUTPUT_DIR="docs/local/summaries"
    MAX_LINES=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.max_lines // 500 | tostring' 2>/dev/null) || MAX_LINES="500"
    UPDATE_FREQUENCY=$(printf '%s\n' "$CONFIG_CONTENT" | jq -r '.update_frequency // "moderate"' 2>/dev/null) || UPDATE_FREQUENCY="moderate"

    # Validate JSON was parseable (jq returns empty on invalid JSON)
    if ! printf '%s\n' "$CONFIG_CONTENT" | jq . >/dev/null 2>&1; then
        # Malformed JSON — use defaults
        ENABLED="true"
        OUTPUT_DIR="docs/local/summaries"
        MAX_LINES="500"
        UPDATE_FREQUENCY="moderate"
    fi
else
    # Pure bash fallback — extract fields with regex
    # Basic JSON structure validation
    TRIMMED="${CONFIG_CONTENT#"${CONFIG_CONTENT%%[![:space:]]*}"}"
    if [[ ! "$TRIMMED" == "{"* ]]; then
        # Not JSON-like — use defaults
        ENABLED="true"
        OUTPUT_DIR="docs/local/summaries"
        MAX_LINES="500"
        UPDATE_FREQUENCY="moderate"
    else
        if [[ "$CONFIG_CONTENT" =~ \"enabled\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
            ENABLED="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"output_dir\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            OUTPUT_DIR="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"max_lines\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            MAX_LINES="${BASH_REMATCH[1]}"
        fi
        if [[ "$CONFIG_CONTENT" =~ \"update_frequency\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            UPDATE_FREQUENCY="${BASH_REMATCH[1]}"
        fi
    fi
fi

# ─── Check enabled flag ──────────────────────────────────────────

if [ "$ENABLED" = "false" ]; then
    echo '{}'
    exit 0
fi

# ─── Validate output_dir ─────────────────────────────────────────

# Must be a relative path (no leading /)
if [[ "$OUTPUT_DIR" == /* ]]; then
    echo '{}'
    exit 0
fi

# Must not contain path traversal (..)
if [[ "$OUTPUT_DIR" == *".."* ]]; then
    echo '{}'
    exit 0
fi

# Only allow safe path characters: alphanumeric, forward slash, underscore, dash, dot
if [[ ! "$OUTPUT_DIR" =~ ^[A-Za-z0-9/_.-]+$ ]]; then
    echo '{}'
    exit 0
fi

# ─── Validate max_lines ──────────────────────────────────────────

# Must be a positive integer
if [[ ! "$MAX_LINES" =~ ^[0-9]+$ ]]; then
    MAX_LINES="500"
fi

# Must be > 0
if [ "$MAX_LINES" -eq 0 ] 2>/dev/null; then
    MAX_LINES="500"
fi

# Must be <= 2000
if [ "$MAX_LINES" -gt 2000 ] 2>/dev/null; then
    MAX_LINES="2000"
fi

# ─── Validate update_frequency ────────────────────────────────────

case "$UPDATE_FREQUENCY" in
    high|moderate|low) ;;
    *) UPDATE_FREQUENCY="moderate" ;;
esac

# ─── Build frequency guidance ────────────────────────────────────

FREQ_GUIDANCE=""
case "$UPDATE_FREQUENCY" in
    high) FREQ_GUIDANCE="every 2-3 tool calls" ;;
    moderate) FREQ_GUIDANCE="every 5-10 tool calls" ;;
    low) FREQ_GUIDANCE="every 15-20 tool calls" ;;
esac

# ─── Output context reminder ─────────────────────────────────────

# All interpolated values are pre-validated:
#   - OUTPUT_DIR: constrained to [A-Za-z0-9/_.-]+ (no special chars)
#   - FREQ_GUIDANCE: hardcoded string from case statement (not user input)
#   - MAX_LINES: numeric string, 1-2000 range
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Conversation summary injection (opt-in enabled)",\n    "additionalContext": "[Conversation Summary: You are maintaining a running summary. Output dir: %s. Update it %s with key decisions, progress, and context. Max %s lines.]"\n  }\n}\n' "$OUTPUT_DIR" "$FREQ_GUIDANCE" "$MAX_LINES"

exit 0
