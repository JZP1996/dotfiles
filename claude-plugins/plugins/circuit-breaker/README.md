# Circuit Breaker

PostToolUse/PreToolUse hook pair that prevents agents from retrying the same failing command indefinitely.

## How It Works

1. **PostToolUse** (`track-failure.sh`): After each tool call, checks if it failed. If so, computes a fingerprint (tool name + normalized args hash) and increments a consecutive failure counter. Successful calls reset the counter.

2. **PreToolUse** (`check-breaker.sh`): Before each tool call, checks if the fingerprint matches a tripped breaker (3+ consecutive failures). If tripped, blocks execution with a diagnostic message.

## Transient Error Allowlist

These error patterns are excluded from tracking because retrying them is appropriate:

- HTTP 429 (rate limit / Too Many Requests)
- `ETIMEDOUT`, `ECONNRESET`, `ECONNREFUSED`, `ENETUNREACH`
- DNS resolution failures (`getaddrinfo`, `ENOTFOUND`)
- HTTP 502 (Bad Gateway), 503 (Service Unavailable)
- Responses containing `retry-after` / `Retry-After`

## State Isolation

State files are scoped by UID and agent PID (`$TMPDIR/claude-circuit-breaker-<uid>-<pid>.json`), preventing cross-agent interference when multiple agents run in parallel.

## Bypass

Prefix your command with `# circuit-breaker: override` to bypass a tripped breaker:

```bash
# circuit-breaker: override
az account show
```

## Relationship to Other Plugins

- **rejection-memory**: Blocks repeated identical calls regardless of outcome. Catches behavioral loops.
- **retry-loop-detector**: Warns/blocks consecutive identical tool calls. Catches repetition patterns.
- **circuit-breaker** (this plugin): Blocks calls after consecutive *failures*. Catches genuinely broken tool paths (expired auth, downed services). Transient errors are allowlisted.

These plugins are complementary. A call blocked by rejection-memory or retry-loop-detector never reaches the circuit breaker.

## Configuration

Edit the `TRIP_THRESHOLD` variable in both hook scripts (default: 3).

## Testing

```bash
bash plugins/circuit-breaker/tests/test-circuit-breaker.sh
```
