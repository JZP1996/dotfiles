# Git Author Check Plugin

Validates git author email before commit commands to prevent wrong-identity commits. In corporate environments, author identity affects IP attribution and audit trails. Wrong email on commits requires interactive rebase to fix.

## How It Works

A PreToolUse hook intercepts Bash commands containing `git commit`:

1. Extracts the command from Claude Code's hook input
2. Checks if the command is a `git commit` (skips `git status`, `git log`, etc.)
3. Bypasses if `GIT_AUTHOR_EMAIL` is explicitly set (intentional override)
4. Reads expected email from config (env var or JSON file)
5. Compares current `git config user.email` against expected (case-insensitive)
6. On first mismatch: auto-corrects and allows with warning
7. On subsequent mismatches: blocks the commit

## Configuration

Set the expected email in one of these locations (checked in order):

### Option 1: Environment Variable

```bash
export EXPECTED_GIT_EMAIL="you@company.com"
```

### Option 2: Repo-level Config

Create `.git-author-check.json` in your repo root:

```json
{
  "expected_email": "you@company.com"
}
```

### Option 3: Home Directory Config

Create `~/.git-author-check.json`:

```json
{
  "expected_email": "you@company.com"
}
```

## Behavior Matrix

| Scenario | Action |
|----------|--------|
| Non-commit git command | Pass silently |
| Non-git command | Pass silently |
| Correct email | Pass silently |
| Wrong email (first time) | Auto-fix + allow with warning |
| Wrong email (again) | Block with message |
| `GIT_AUTHOR_EMAIL` set in command | Bypass (intentional override) |
| No expected email configured | Allow with warning |

## Dependencies

- `bash` (3.2+)
- `git`
- `jq` (optional, pure-bash fallback available)

No external dependencies beyond git. No configuration required beyond setting the expected email.

## Known Limitations

- **Pure-bash JSON fallback**: When `jq` is unavailable, the regex-based parser does not handle escaped quotes or multi-line JSON input. Install `jq` for full correctness.
- **Over-matching on commit detection**: The hook matches any command containing `git commit`, which may trigger on non-commit contexts (e.g., `echo "git commit"`). False positives are safe since the check only validates email configuration.

## Testing

```bash
bash plugins/git-author-check/tests/test-check-git-author.sh
```

## Cross-Platform Support

Works on macOS, Linux, and Windows (WSL/Git Bash) via the Node.js shim pattern.
