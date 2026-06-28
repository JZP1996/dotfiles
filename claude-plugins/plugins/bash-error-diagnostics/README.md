# Bash Error Diagnostics Plugin

Reduces silent Bash failures by combining preventive pipeline guidance with structured post-failure error classification. Targets the 35.6% of Bash tool errors that show only "Exit code 1" with no actionable diagnostics.

## How It Works

Two complementary hooks work together:

### PreToolUse: Pipeline Guard

Before a Bash command runs, inspects the command string:

1. Detects pipe operators (`|`) without `set -o pipefail`
2. Injects `additionalContext` reminding the agent to prepend `set -o pipefail;`
3. Warns about common error-swallowing patterns:
   - `2>/dev/null |` (stderr discarded before pipe)
   - `|| true` (exit code masked)
   - `2>&1 |` (stderr merged with stdout, losing structure)

### PostToolUse: Error Classifier

After a Bash command fails, classifies the error and provides structured diagnostics:

| Error Class | Retry Useful? | Example |
|-------------|---------------|---------|
| `command_not_found` | No | Tool not installed or not in PATH |
| `permission_denied` | No | Insufficient file or execution permissions |
| `file_not_found` | No | Referenced path does not exist |
| `network` | Maybe | Connection refused or timed out |
| `git_error` | No | Git operation failed |
| `syntax_error` | No | Command syntax error |
| `resource` | No | Process killed (OOM/timeout) |
| `package_manager` | Maybe | npm/pip operation failed |
| `unknown` | Unknown | Unclassified error |

Additionally detects:
- **Pipeline failures**: Counts pipe stages, suggests `pipefail`
- **Subshell failures**: Warns that `$(...)` may mask errors

## Performance

Both hooks run only on Bash tool calls (`"matcher": "Bash"`). Pure string matching with no subprocesses or file I/O beyond stdin.

- PreToolUse: <5ms (fires on all Bash calls)
- PostToolUse: <5ms (fires on all Bash calls, early exit on success)

## Dependencies

- `bash` (3.2+)
- `jq` (optional, pure-bash fallback available)

No external dependencies. No configuration required. Always-on when the plugin is registered.

## Testing

```bash
# PreToolUse tests (13 tests)
bash plugins/bash-error-diagnostics/tests/test-diagnose-bash.sh

# PostToolUse tests (17 tests)
bash plugins/bash-error-diagnostics/tests/test-classify-bash-error.sh
```

## Cross-Platform Support

Works on macOS, Linux, and Windows (WSL/Git Bash) via the Node.js shim pattern.
