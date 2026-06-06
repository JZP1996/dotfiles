# Compaction Monitor Plugin

Monitors context utilization and compaction frequency to warn when session quality is degrading. Injects warnings into Claude's context via a PreToolUse hook when thresholds are exceeded.

## Why This Matters

Sessions that compact frequently (every 30-50 messages) show the highest error and retry rates. Compaction is both a symptom and an accelerant of degraded performance. Early warning enables proactive session splits before quality degrades.

## Opt-In Required

This plugin is **disabled by default**. To enable it, create a `.compaction-monitor.json` config file:

| Location | Scope |
|----------|-------|
| `~/.compaction-monitor.json` | User-global (all repos) |
| `<repo-root>/.compaction-monitor.json` | Repo-specific |

The home directory config takes precedence over the repo root config.

## Configuration

```json
{
  "enabled": true,
  "warn_utilization_pct": 75,
  "critical_utilization_pct": 90,
  "warn_compaction_count": 2,
  "critical_compaction_count": 4
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `enabled` | No | `true` | Master kill switch. Set to `false` to disable. |
| `warn_utilization_pct` | No | `75` | Context utilization percentage that triggers a CAUTION warning. |
| `critical_utilization_pct` | No | `90` | Context utilization percentage that triggers a WARNING. |
| `warn_compaction_count` | No | `2` | Number of compactions that triggers a CAUTION warning. |
| `critical_compaction_count` | No | `4` | Number of compactions that triggers a WARNING. |

## How It Works

The hook reads two data sources on every tool call:

1. **`~/.claude/token_usage.json`** - Context utilization percentage and alert level, updated on every completion.
2. **`~/.claude/compaction-count.txt`** - Compaction event counter (maintained by session protocol CTX-2 pattern).

### Warning Levels

| Level | Trigger | Action |
|-------|---------|--------|
| **NORMAL** | Below all thresholds | No output (zero context cost) |
| **CAUTION** | utilization >= warn_pct OR compactions >= warn_count | Suggests lowering delegation threshold |
| **WARNING** | utilization >= critical_pct OR compactions >= critical_count | Strongly recommends `/handoff` and fresh session |

The hook also respects the `alert_level` field from `token_usage.json` (CAUTION, WARNING, CRITICAL).

## Data Sources

### token_usage.json

This file is written by the context usage monitor (e.g., the VS Code extension or CLI wrapper) on every completion:

```json
{
  "utilization_pct": 47.2,
  "alert_level": "NORMAL"
}
```

### compaction-count.txt

A plain integer maintained per the CTX-2 pattern in session protocol. Incremented after each compaction recovery, reset at session start:

```bash
# Increment after compaction
count=$(cat ~/.claude/compaction-count.txt 2>/dev/null || echo 0)
echo $((count + 1)) > ~/.claude/compaction-count.txt

# Reset at session start
echo 0 > ~/.claude/compaction-count.txt
```

## Testing

```bash
bash plugins/compaction-monitor/tests/test-check-compaction.sh
```
