# Time Awareness Plugin

Injects the current system time and timezone into Claude's context on every tool call via a PreToolUse hook. The time context is invisible to the user but available to Claude for time-aware reasoning.

## Opt-In Required

This plugin is **disabled by default**. To enable it, create a `.time-awareness.json` config file in one of these locations:

| Location | Scope |
|----------|-------|
| `~/.time-awareness.json` | User-global (all repos) |
| `<repo-root>/.time-awareness.json` | Repo-specific |

The home directory config takes precedence over the repo root config.

## Configuration

```json
{
  "enabled": true,
  "timezone": "America/Los_Angeles",
  "format": "iso"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `enabled` | No | `true` | Master kill switch. Set to `false` to disable. |
| `timezone` | No | System default | IANA timezone (e.g., `America/Los_Angeles`, `UTC`). |
| `format` | No | `"iso"` | `"iso"` for human-readable, `"unix"` for epoch seconds. |

### Minimal Config

```json
{"enabled": true}
```

This uses system defaults for timezone and ISO format.

## Context Format

### ISO Format (default)

```
[System time: 2026-02-27 14:32:05 PST (Thu)]
```

Components: ISO date, 24-hour time, timezone abbreviation, day of week.

### Unix Format

```
[System time: 1740700325 unix]
```

Unix epoch seconds.

## How It Works

1. On every tool call, Claude Code invokes the `inject-time-context.sh` hook
2. The hook checks for a `.time-awareness.json` config file
3. If opted-in, it generates a timestamp and returns it as `additionalContext`
4. Claude receives the time context invisibly — it doesn't appear in the chat

**Performance note:** The hook runs on every tool call (`.*` matcher) by design, adding ~20ms when opted-in or ~8ms when not opted-in (early exit). Over a typical session (~100 tool calls), this adds ~2 seconds of cumulative overhead — negligible relative to total session time. The 2-second timeout ensures the hook never blocks tool execution.

## Dependencies

- `bash` (4.0+)
- `date` (coreutils — available on all platforms)
- `jq` (optional — pure bash fallback when unavailable)
- `git` (for repo root detection)

No external dependencies. No installation required.

## Security

- **No `eval`** — config parsing uses jq or bash regex
- **Static template output** — no user-controlled values in `additionalContext`
- **Timezone validation** — invalid timezones fall back to system default
- **Control character rejection** — config files with control characters are rejected
- **Fail-safe** — every error path outputs `{}` and exits 0 (never blocks tool execution)

## Testing

```bash
bash plugins/time-awareness/tests/test-inject-time-context.sh
```

69 tests covering opt-in/opt-out, timezone validation, security edge cases (injection, control characters), jq fallback, format options, and performance.

## Cross-Platform Support

Works on macOS (BSD `date`), Linux (GNU `date`), and Windows (WSL/Git Bash). Uses POSIX-compatible format strings for maximum compatibility.
