#!/usr/bin/env bash
# classify-bash-error.sh - PostToolUse hook for Bash error classification
#
# When a Bash command fails, classifies the error and provides structured
# diagnostics including error category, likely cause, retry guidance, and
# pipeline/subshell analysis.
#
# Input: JSON on stdin from Claude Code's hook system
#   { "tool_name": "Bash", "tool_input": { "command": "..." }, "tool_result": { ... } }
#
# Output: JSON on stdout
#   - On error: additionalContext with structured diagnostics
#   - On success or non-Bash: {} (no-op)
#
# Dependencies: bash 3.2+, jq (with pure-bash fallback)
#
# Security:
#   - No eval anywhere
#   - Read-only analysis of command and result strings
#   - Static template output only
#   - Tool result content truncated to 2000 chars to avoid oversized output
#   - Every error path -> {} + exit 0

set -euo pipefail

trap 'echo "{}"; exit 0' ERR

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

# ─── Parse fields ────────────────────────────────────────────────

TOOL_NAME=""
COMMAND=""
RESULT=""

if command -v jq >/dev/null 2>&1; then
    TOOL_NAME=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
    COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
    # tool_result may be a string or object; extract text content, truncate
    RESULT=$(printf '%s\n' "$INPUT" | jq -r '
        if .tool_result | type == "string" then .tool_result
        elif .tool_result.content | type == "string" then .tool_result.content
        elif .tool_result.stdout | type == "string" then .tool_result.stdout
        elif .tool_result.stderr | type == "string" then .tool_result.stderr
        else (.tool_result | tostring)
        end // empty' 2>/dev/null | head -c 2000) || true
else
    # Pure bash fallback
    if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        TOOL_NAME="${BASH_REMATCH[1]}"
    fi
    if [[ "$INPUT" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        COMMAND="${BASH_REMATCH[1]}"
    fi
    # Bash fallback for result is limited; get what we can
    RESULT="${INPUT:0:2000}"
fi

# ─── Gate: only Bash tool ────────────────────────────────────────

if [ "${TOOL_NAME:-}" != "Bash" ]; then
    echo '{}'
    exit 0
fi

# ─── Detect error ────────────────────────────────────────────────

HAS_ERROR=false
EXIT_CODE=""

# Check for exit code pattern
if [[ "${RESULT:-}" =~ [Ee]xit[[:space:]]*[Cc]ode[[:space:]]*:?[[:space:]]*([0-9]+) ]]; then
    EXIT_CODE="${BASH_REMATCH[1]}"
    if [ "$EXIT_CODE" != "0" ]; then
        HAS_ERROR=true
    fi
fi

# Check for common error strings
if [ "$HAS_ERROR" = false ]; then
    for pat in "command not found" "No such file or directory" "Permission denied" \
               "Connection refused" "Connection timed out" "fatal:" "error:" "Error:" \
               "ENOENT" "EACCES" "EPERM"; do
        if [[ "${RESULT:-}" == *"$pat"* ]]; then
            HAS_ERROR=true
            break
        fi
    done
fi

# No error detected - exit silently
if [ "$HAS_ERROR" = false ]; then
    echo '{}'
    exit 0
fi

# ─── Analyze command structure ───────────────────────────────────

HAS_PIPES=false
PIPE_COUNT=0
HAS_SUBSHELL=false

# Detect pipes (not ||)
STRIPPED="${COMMAND//||/}"
if [[ "$STRIPPED" == *"|"* ]]; then
    HAS_PIPES=true
    # Count pipe characters in stripped command
    PIPE_ONLY="${STRIPPED//[^|]/}"
    PIPE_COUNT="${#PIPE_ONLY}"
fi

# Detect subshells (literal string match, not expansion)
# shellcheck disable=SC2016
if [[ "$COMMAND" == *'$('* ]] || [[ "$COMMAND" == *'`'* ]]; then
    HAS_SUBSHELL=true
fi

# ─── Classify error ─────────────────────────────────────────────

ERROR_CLASS="unknown"
LIKELY_CAUSE="Exit code ${EXIT_CODE:-unknown}"
SUGGESTION="Review error output. Break complex commands into simpler steps."
RETRY="Unknown"

R="${RESULT:-}"

if [[ "$R" == *"command not found"* ]]; then
    ERROR_CLASS="command_not_found"
    RETRY="No"
    LIKELY_CAUSE="A required command is not installed or not in PATH"
    SUGGESTION="Check if the tool is installed. Use 'which <cmd>' or 'command -v <cmd>' to verify."
elif [[ "$R" == *"Permission denied"* ]] || [[ "$R" == *"EACCES"* ]] || [[ "$R" == *"EPERM"* ]]; then
    ERROR_CLASS="permission_denied"
    RETRY="No"
    LIKELY_CAUSE="Insufficient permissions to access file or execute command"
    SUGGESTION="Check permissions with 'ls -la'. Do NOT retry with sudo."
elif [[ "$R" == *"No such file or directory"* ]] || [[ "$R" == *"ENOENT"* ]]; then
    ERROR_CLASS="file_not_found"
    RETRY="No"
    LIKELY_CAUSE="Referenced path does not exist"
    SUGGESTION="Verify the path exists. Use 'ls' to check parent directory."
elif [[ "$R" == *"Connection refused"* ]] || [[ "$R" == *"Connection timed out"* ]]; then
    ERROR_CLASS="network"
    RETRY="Maybe"
    LIKELY_CAUSE="Network connectivity or service unavailable"
    SUGGESTION="Check if the service is running. Retry may help for transient failures."
elif [[ "$R" == *"fatal:"* ]] && [[ "${COMMAND:-}" == *"git"* ]]; then
    ERROR_CLASS="git_error"
    RETRY="No"
    LIKELY_CAUSE="Git operation failed"
    SUGGESTION="Check 'git status' and branch state before retrying."
elif [[ "$R" == *"syntax error"* ]] || [[ "$R" == *"unexpected token"* ]]; then
    ERROR_CLASS="syntax_error"
    RETRY="No"
    LIKELY_CAUSE="Command has a syntax error"
    SUGGESTION="Fix the command syntax before retrying."
elif [[ "$R" == *"Killed"* ]] || [[ "$R" == *"out of memory"* ]] || [[ "$R" == *"Cannot allocate"* ]]; then
    ERROR_CLASS="resource"
    RETRY="No"
    LIKELY_CAUSE="Process killed (OOM or resource limit)"
    SUGGESTION="Reduce scope, process in smaller chunks, or limit output."
elif [[ "$R" == *"npm ERR!"* ]] || [[ "$R" == *"pip"*"error"* ]]; then
    ERROR_CLASS="package_manager"
    RETRY="Maybe"
    LIKELY_CAUSE="Package manager operation failed"
    SUGGESTION="Check network connectivity and package availability."
fi

# ─── Build diagnostic output ────────────────────────────────────

DIAG="Error class: ${ERROR_CLASS}. Likely cause: ${LIKELY_CAUSE}. Retry useful: ${RETRY}."

if [ "$HAS_PIPES" = true ]; then
    DIAG="${DIAG} Pipeline: ${PIPE_COUNT} pipe(s) detected without pipefail. Only the last command exit code is reported. Consider: set -o pipefail; <command>"
fi

if [ "$HAS_SUBSHELL" = true ]; then
    DIAG="${DIAG} Subshell: Failures inside \$(...) may be masked. Consider breaking into sequential commands."
fi

DIAG="${DIAG} Suggested approach: ${SUGGESTION}"

# ─── Output JSON ────────────────────────────────────────────────

# Escape special chars for JSON
DIAG_ESCAPED="${DIAG//\\/\\\\}"
DIAG_ESCAPED="${DIAG_ESCAPED//\"/\\\"}"

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PostToolUse",\n    "additionalContext": "[Bash Error Diagnostics] %s"\n  }\n}\n' "$DIAG_ESCAPED"

exit 0
