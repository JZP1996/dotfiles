#!/usr/bin/env bash
# check-git-author.sh - PreToolUse hook for git author email validation
#
# Intercepts Bash commands containing "git commit" and validates that
# git config user.email matches the expected email. Prevents wrong-identity
# commits that require interactive rebase to fix.
#
# Behavior:
#   - First mismatch: auto-fix (set correct email) + allow with warning
#   - Subsequent mismatches: block the commit
#   - GIT_AUTHOR_EMAIL env var set in command: bypass (intentional override)
#   - Non-commit git commands: pass silently
#   - No expected email configured: pass with warning
#
# Configuration (checked in order):
#   1. Environment variable: EXPECTED_GIT_EMAIL
#   2. Config file: .git-author-check.json in repo root
#   3. Config file: ~/.git-author-check.json
#
# Input: JSON on stdin from Claude Code's hook system
#   { "tool_name": "Bash", "tool_input": { "command": "..." }, "cwd": "..." }
#
# Output: JSON on stdout
#   - Non-commit command: {} (no-op)
#   - Correct email: {} (no-op)
#   - First mismatch: auto-fix + allow with additionalContext warning
#   - Subsequent mismatch: block with reason
#   - No config: allow with additionalContext warning
#
# Dependencies: bash 3.2+, git, jq (with pure-bash fallback)
#
# Security:
#   - No eval anywhere
#   - Read-only analysis of command string (never executes it)
#   - Only runs git config commands (read + write email)
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

# ─── Extract command and cwd from tool_input ─────────────────────

COMMAND=""
CWD=""
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
    CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
else
    # Pure bash fallback -- handles simple single-line JSON. Commands containing
    # escaped quotes or multi-line input may not parse correctly; jq is preferred.
    if [[ "$INPUT" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        COMMAND="${BASH_REMATCH[1]}"
    fi
    if [[ "$INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        CWD="${BASH_REMATCH[1]}"
    fi
fi

if [ -z "$COMMAND" ]; then
    echo '{}'
    exit 0
fi

# ─── Check if this is a git commit command ───────────────────────

# Match commands containing "git commit" (including "git -C /path commit").
# Handles chained commands with && ; or | by checking each segment.
# Intentionally over-matches: e.g., `echo "git commit"` triggers a check.
# False positives are safe (extra validation), false negatives are not.
IS_COMMIT=false

# Split on shell command separators (&&, ;, |) and check each segment
# This ensures "git add . && git commit -m msg" is detected
REMAINING="$COMMAND"
while [ -n "$REMAINING" ]; do
    # Extract the first command segment (up to &&, ;, ||, or |)
    SEGMENT="${REMAINING%%&&*}"
    if [ "$SEGMENT" = "$REMAINING" ]; then
        SEGMENT="${REMAINING%%;*}"
    fi
    if [ "$SEGMENT" = "$REMAINING" ]; then
        SEGMENT="${REMAINING%%||*}"
    fi
    if [ "$SEGMENT" = "$REMAINING" ]; then
        SEGMENT="${REMAINING%%|*}"
    fi

    # Check this segment for git commit
    if [[ "$SEGMENT" =~ git[[:space:]]+((-[A-Za-z][[:space:]]+[^[:space:]]+[[:space:]]+)*)commit ]]; then
        IS_COMMIT=true
        break
    elif [[ "$SEGMENT" =~ git[[:space:]]+commit ]]; then
        IS_COMMIT=true
        break
    fi

    # Remove the processed segment and separator from REMAINING
    if [ "$SEGMENT" = "$REMAINING" ]; then
        break
    fi
    REMAINING="${REMAINING#"$SEGMENT"}"
    # Strip the separator characters
    REMAINING="${REMAINING#&&}"
    REMAINING="${REMAINING#||}"
    REMAINING="${REMAINING#;}"
    REMAINING="${REMAINING#|}"
done

if [ "$IS_COMMIT" = false ]; then
    echo '{}'
    exit 0
fi

# ─── Check for GIT_AUTHOR_EMAIL override ─────────────────────────

# If the command explicitly sets GIT_AUTHOR_EMAIL, it's intentional
if [[ "$COMMAND" =~ GIT_AUTHOR_EMAIL= ]]; then
    echo '{}'
    exit 0
fi

# ─── Normalize path helper ───────────────────────────────────────

_normalize_path() {
    local p="$1"
    if [[ "$p" == *\\* ]]; then
        p="${p//\\//}"
    fi
    printf '%s' "$p"
}

CWD="$(_normalize_path "${CWD:-}")"

# ─── Determine expected email ────────────────────────────────────

EXPECTED_EMAIL=""

# Priority 1: Environment variable
if [ -n "${EXPECTED_GIT_EMAIL:-}" ]; then
    EXPECTED_EMAIL="$EXPECTED_GIT_EMAIL"
fi

# Priority 2: Repo root config file
REPO_ROOT=""
if [ -z "$EXPECTED_EMAIL" ] && [ -n "$CWD" ]; then
    if command -v git >/dev/null 2>&1; then
        REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || true
        REPO_ROOT="$(_normalize_path "${REPO_ROOT:-}")"
    fi
    if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.git-author-check.json" ]; then
        if command -v jq >/dev/null 2>&1; then
            EXPECTED_EMAIL=$(jq -r '.expected_email // empty' "$REPO_ROOT/.git-author-check.json" 2>/dev/null) || true
        elif [[ "$(cat "$REPO_ROOT/.git-author-check.json" 2>/dev/null)" =~ \"expected_email\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            EXPECTED_EMAIL="${BASH_REMATCH[1]}"
        fi
    fi
else
    # Still resolve REPO_ROOT for state file even when email comes from env var
    if [ -n "$CWD" ] && command -v git >/dev/null 2>&1; then
        REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || true
        REPO_ROOT="$(_normalize_path "${REPO_ROOT:-}")"
    fi
fi

# Priority 3: Home directory config file
if [ -z "$EXPECTED_EMAIL" ] && [ -f "${HOME:-}/.git-author-check.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        EXPECTED_EMAIL=$(jq -r '.expected_email // empty' "$HOME/.git-author-check.json" 2>/dev/null) || true
    elif [[ "$(cat "$HOME/.git-author-check.json" 2>/dev/null)" =~ \"expected_email\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        EXPECTED_EMAIL="${BASH_REMATCH[1]}"
    fi
fi

# No expected email configured -- warn but allow
if [ -z "$EXPECTED_EMAIL" ]; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "No expected git email configured -- skipping author check",\n    "additionalContext": "git-author-check: No expected email configured. Set EXPECTED_GIT_EMAIL env var or create .git-author-check.json with {\\\"expected_email\\\": \\\"you@example.com\\\"} in repo root or home directory."\n  }\n}\n'
    exit 0
fi

# ─── Validate expected email format ──────────────────────────────

# Basic sanity: must contain @ and a valid TLD. Warn (not silently pass) on
# malformed config so the user knows their configuration is broken.
if [[ ! "$EXPECTED_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Expected email format is invalid -- skipping author check",\n    "additionalContext": "git-author-check: Expected email [%s] does not look like a valid email address (missing TLD or invalid characters). Fix your .git-author-check.json or EXPECTED_GIT_EMAIL value."\n  }\n}\n' "$EXPECTED_EMAIL"
    exit 0
fi

# ─── State file (per-repo, per-user) ────────────────────────────

# State tracks whether auto-fix has fired for this repo. Keyed by both UID
# and repo root path hash so different repos with different expected emails
# maintain independent auto-fix state.
STATE_DIR="${TMPDIR:-/tmp}"
REPO_HASH=""
if [ -n "$REPO_ROOT" ]; then
    # Use cksum for portability (available on macOS and Linux without extra deps)
    REPO_HASH=$(printf '%s' "$REPO_ROOT" | cksum | cut -d' ' -f1)
fi
STATE_FILE="${GIT_AUTHOR_CHECK_STATE_FILE:-${STATE_DIR}/git-author-check-autofixed-$(id -u 2>/dev/null || echo $$)-${REPO_HASH:-global}}"

# ─── Get current git email ──────────────────────────────────────

CURRENT_EMAIL=""
if command -v git >/dev/null 2>&1 && [ -n "$CWD" ]; then
    CURRENT_EMAIL=$(git -C "$CWD" config user.email 2>/dev/null) || true
fi

if [ -z "$CURRENT_EMAIL" ]; then
    # Can't determine current email -- allow but warn
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Could not determine current git email -- allowing commit",\n    "additionalContext": "git-author-check: Could not read git config user.email. Verify your git configuration."\n  }\n}\n'
    exit 0
fi

# Sanitize current email: strip characters that could break JSON output.
# Only allow alphanumeric, dots, hyphens, underscores, plus, percent, and @.
CURRENT_EMAIL_SAFE=$(printf '%s' "$CURRENT_EMAIL" | tr -cd 'A-Za-z0-9._%+@-')

# ─── Compare emails ─────────────────────────────────────────────

# Case-insensitive comparison
CURRENT_LOWER=$(printf '%s' "$CURRENT_EMAIL_SAFE" | tr '[:upper:]' '[:lower:]')
EXPECTED_LOWER=$(printf '%s' "$EXPECTED_EMAIL" | tr '[:upper:]' '[:lower:]')

if [ "$CURRENT_LOWER" = "$EXPECTED_LOWER" ]; then
    # Email matches -- no-op
    echo '{}'
    exit 0
fi

# ─── Email mismatch -- check if first time ───────────────────────

# Reset state if the expected email has changed since last auto-fix.
# This handles legitimate email changes: if the stored expected email
# no longer matches the current config, treat as a fresh state.
if [ -f "$STATE_FILE" ]; then
    STORED_EMAIL=$(cat "$STATE_FILE" 2>/dev/null) || true
    STORED_LOWER=$(printf '%s' "$STORED_EMAIL" | tr '[:upper:]' '[:lower:]')
    if [ "$STORED_LOWER" != "$EXPECTED_LOWER" ]; then
        rm -f "$STATE_FILE"
    fi
fi

if [ ! -f "$STATE_FILE" ]; then
    # First mismatch: auto-fix and allow with warning.
    # Because this is a PreToolUse hook, it runs BEFORE the Bash tool executes.
    # Setting git config here means the subsequent "git commit" picks up the
    # corrected user.email, so the commit is authored correctly.
    if command -v git >/dev/null 2>&1 && [ -n "$CWD" ]; then
        git -C "$CWD" config user.email "$EXPECTED_EMAIL" 2>/dev/null || true
    fi

    # Mark that we've auto-fixed once for this repo
    printf '%s' "$EXPECTED_EMAIL" > "$STATE_FILE" 2>/dev/null || true

    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "allow",\n    "permissionDecisionReason": "Auto-fixed git author email (first occurrence)",\n    "additionalContext": "git-author-check: Author email was [%s] but expected [%s]. Auto-corrected to expected email. This was a one-time fix; future mismatches will block the commit."\n  }\n}\n' "$CURRENT_EMAIL_SAFE" "$EXPECTED_EMAIL"
    exit 0
fi

# ─── Subsequent mismatch -- block ────────────────────────────────

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "block",\n    "permissionDecisionReason": "Git author email mismatch (repeated)",\n    "additionalContext": "git-author-check: BLOCKED. Author email is [%s] but expected [%s]. Run: git config user.email %s. This is a repeated mismatch. The hook auto-fixed once before but the email has drifted again."\n  }\n}\n' "$CURRENT_EMAIL_SAFE" "$EXPECTED_EMAIL" "$EXPECTED_EMAIL"
exit 0
