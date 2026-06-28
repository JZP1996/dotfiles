# sleep-cap

PreToolUse hook that blocks excessive `sleep` commands in Bash tool calls to prevent wasted wall-clock time.

## Problem

Agents insert long `sleep` commands (600s, 900s) that waste wall-clock time. Analysis found 407 minutes of sleep across 3 sessions, with one session losing 6.8 hours to sleep alone.

## How It Works

The hook intercepts every Bash tool call, scans for `sleep` commands, converts durations to seconds (handling `s`, `m`, `h` suffixes), and blocks any sleep exceeding the threshold (default: 60 seconds).

Blocked commands receive a suggestion to use `run_in_background: true` instead.

## Detection

Detects all common patterns:

| Pattern | Example |
|---------|---------|
| Simple | `sleep 600` |
| With suffix | `sleep 600s`, `sleep 10m`, `sleep 1h` |
| In chains | `sleep 120 && echo done` |
| In loops | `while true; do sleep 300; done` |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SLEEP_CAP_THRESHOLD` | `60` | Maximum allowed sleep duration in seconds |

## Override

Add `# sleep-cap:ignore` anywhere in the command to bypass the check:

```bash
# sleep-cap:ignore
sleep 600  # Intentional long wait
```

## Observability

Blocked sleeps are logged to `~/.claude/logs/sleep-cap.log` with timestamp, duration, threshold, and truncated command.

## Tests

```bash
bash plugins/sleep-cap/tests/test-cap-sleep.sh
```
