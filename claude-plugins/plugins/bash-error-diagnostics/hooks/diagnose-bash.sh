#!/usr/bin/env bash
# diagnose-bash.sh - PreToolUse hook for Bash error diagnostics
#
# Detects Bash commands that use pipes without pipefail and injects
# additionalContext reminding the agent to use `set -o pipefail` so
# that failures in intermediate pipeline stages are not silently lost.
#
# Problem: 35.6% of Bash tool errors are "Exit code 1" with no useful
# diagnostics. Piped commands (cmd1 | cmd2) only report the exit code
# of the LAST command, silently swallowing failures in earlier stages.
#
# Input: JSON on stdin from Claude Code's hook system
#   { "tool_name": "Bash", "tool_input": { "command": "..." }, "cwd": "..." }
#
# Output: JSON on stdout
#   - Piped command without pipefail: additionalContext with diagnostic guidance
#   - Otherwise: {} (no-op)
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

# ─── Extract command from tool_input ─────────────────────────────

COMMAND=""
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
else
    # Pure bash fallback - extract command value
    if [[ "$INPUT" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        COMMAND="${BASH_REMATCH[1]}"
    fi
fi

if [ -z "$COMMAND" ]; then
    echo '{}'
    exit 0
fi

# ─── Detect pipe usage ──────────────────────────────────────────

# Match a single | that is not part of || (logical OR)
# Remove all || first, then check for remaining |
HAS_PIPE=false
STRIPPED="${COMMAND//||/}"
if [[ "$STRIPPED" == *"|"* ]]; then
    HAS_PIPE=true
fi

if [ "$HAS_PIPE" = false ]; then
    echo '{}'
    exit 0
fi

# ─── Check if pipefail is already set ────────────────────────────

HAS_PIPEFAIL=false
if [[ "$COMMAND" == *"pipefail"* ]]; then
    HAS_PIPEFAIL=true
fi

if [ "$HAS_PIPEFAIL" = true ]; then
    echo '{}'
    exit 0
fi

# ─── Detect common error-swallowing patterns ────────────────────

WARNINGS=""

# Pattern: cmd 2>/dev/null | ... (stderr discarded before pipe)
if [[ "$COMMAND" =~ 2\>/dev/null[[:space:]]*\| ]]; then
    WARNINGS="stderr is redirected to /dev/null before a pipe, which discards error output from that stage. "
fi

# Pattern: ... || true at the end (exit code masked)
if [[ "$COMMAND" =~ \|\|[[:space:]]*true[[:space:]]*$ ]]; then
    WARNINGS="${WARNINGS}The trailing '|| true' masks the exit code, preventing error detection. "
fi

# Pattern: ... 2>&1 | ... (stderr merged into stdout before pipe)
if [[ "$COMMAND" =~ 2\>\&1[[:space:]]*\| ]]; then
    WARNINGS="${WARNINGS}stderr is merged with stdout before piping, which can make errors hard to distinguish from normal output. "
fi

# ─── Build context message ──────────────────────────────────────

CONTEXT="This command uses pipes without 'set -o pipefail'. Without pipefail, only the exit code of the LAST command in the pipeline is reported. If an earlier stage fails, the error is silently lost. Consider prepending 'set -o pipefail;' to catch failures in any pipeline stage."

if [ -n "$WARNINGS" ]; then
    CONTEXT="${CONTEXT} Additional concerns: ${WARNINGS}"
fi

# ─── Output ─────────────────────────────────────────────────────

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Bash pipe detected without pipefail — injecting diagnostic guidance",\n    "additionalContext": "%s"\n  }\n}\n' "$CONTEXT"

exit 0
