# Conversation Summary Plugin

Injects a conversation summary reminder into Claude's context on every tool call via a PreToolUse hook. The agent maintains a running summary file that captures key decisions, progress, and context — preserving the full arc of a conversation for future sessions.

## Opt-In Required

This plugin is **disabled by default**. To enable it, create a `.conversation-summary.json` config file in one of these locations:

| Location | Scope |
|----------|-------|
| `~/.conversation-summary.json` | User-global (all repos) |
| `<repo-root>/.conversation-summary.json` | Repo-specific |

The home directory config takes precedence over the repo root config.

## Configuration

```json
{
  "enabled": true,
  "output_dir": "docs/local/summaries",
  "max_lines": 500,
  "update_frequency": "moderate"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `enabled` | No | `true` | Master kill switch. Set to `false` to disable. |
| `output_dir` | No | `docs/local/summaries` | Relative path from repo root. Must not contain `..` or start with `/`. |
| `max_lines` | No | `500` | Maximum lines in the summary file. Capped at 2000. |
| `update_frequency` | No | `"moderate"` | `"high"` (every 2-3 tool calls), `"moderate"` (every 5-10), `"low"` (every 15-20). |

### Minimal Config

```json
{"enabled": true}
```

This uses all defaults: summaries in `docs/local/summaries/`, max 500 lines, moderate update frequency.

## How It Works

1. On every tool call, Claude Code invokes the `summarize-context.sh` hook
2. The hook checks for a `.conversation-summary.json` config file
3. If opted-in, it returns `additionalContext` reminding the agent to update the summary
4. The **skill** (loaded into the agent's system prompt) provides full instructions on:
   - Where to write the summary file (`docs/local/summaries/YYYY-MM-DD-<topic>.md`)
   - How to structure it (Objective, Key Decisions, Progress, Technical Context, Open Questions, Blockers)
   - When to update it (based on configured frequency)
   - How to keep it under the line limit

**Key insight:** The hook doesn't generate the summary — the agent does. The hook only injects a lightweight reminder into the agent's context.

## Summary File

**Location:** `docs/local/summaries/YYYY-MM-DD-<topic-slug>.md`

**Example:** `docs/local/summaries/2026-03-09-auth-middleware-refactor.md`

The agent creates the file on its first significant action and names it based on the conversation's primary objective. Files are gitignored (`docs/local/*`).

## Picking Up Previous Sessions

The plugin includes a **pick-up-where-I-left-off skill** that lets you continue from a previous session using natural language. Instead of remembering exact file paths, just say:

- "Pick up where I left off on auth-refactor"
- "Continue work on CI pipeline"
- "What was I working on yesterday?"
- "Load summary for API versioning"
- "Continue from last time"

The skill automatically searches your summary directory for matching files and loads the relevant context.

### Summary Matching Logic

1. Finds your summary directory (from config or default `docs/local/summaries/`)
2. Matches your keyword against summary filenames
3. If one match: loads it automatically
4. If multiple matches: lists them for you to choose
5. If no matches: shows all available summaries

### Relationship with `/user:recover`

This skill and `/user:recover` are complementary:

| Feature | Pick Up Skill | `/user:recover` |
|---------|--------------|-----------------|
| **Purpose** | Load a specific conversation summary | Broad session recovery |
| **Activation** | Natural language ("pick up where I left off") | Slash command |
| **Scope** | Conversation summary files only | git status, SESSION-BOOTSTRAP.md, repo knowledge |

Use both together for complete context loading: `/user:recover` for session state, then "pick up where I left off on X" for specific conversation context.

## Dependencies

- `bash` (4.0+)
- `jq` (optional — pure bash fallback when unavailable)
- `git` (for repo root detection)

No external dependencies. No installation required.

## Security

- **No `eval`** — config parsing uses jq or bash regex
- **Validated config injection** — user-controlled config values (output_dir, max_lines, update_frequency) are validated and sanitized before injection into `additionalContext`
- **Path validation** — output directory must be relative, no `..` traversal, no absolute paths
- **Control character rejection** — config files with control characters are rejected
- **Fail-safe** — every error path outputs `{}` and exits 0 (never blocks tool execution)
- **Gitignored output** — summary files live in `docs/local/` (already gitignored)

## Testing

```bash
bash plugins/conversation-summary/tests/test-summarize-context.sh
```

Tests cover opt-in/opt-out, config field validation, path traversal rejection, security edge cases (injection, control characters), jq fallback, output structure, and performance.

## Cross-Platform Support

Works on macOS (BSD), Linux (GNU), and Windows (WSL/Git Bash). Uses POSIX-compatible constructs for maximum compatibility.
