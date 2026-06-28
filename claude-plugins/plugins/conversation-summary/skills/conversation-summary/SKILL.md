---
name: conversation-summary
description: Maintain a running conversation summary to preserve context across sessions. Use when working on long or multi-session tasks that require context preservation.
---

# Conversation Summary

You are maintaining a running conversation summary to preserve context across sessions.

## When to Create

Create the summary file on your **first significant action** in the conversation (not on trivial tool calls like reading a single file). Name it based on the conversation's primary objective.

## File Location

Write the summary to `<output_dir>/YYYY-MM-DD-<topic-slug>.md` where:
- `<output_dir>` is the directory specified in the hook reminder (default: `docs/local/summaries`)
- `YYYY-MM-DD` is today's date
- `<topic-slug>` is a short kebab-case description you choose based on the conversation objective (e.g., `auth-middleware-refactor`, `ci-pipeline-debugging`, `api-versioning-design`)

Create the output directory if it doesn't exist.

## File Structure

Use this template:

```markdown
# Conversation Summary: <Topic>
**Date:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD HH:MM TZ
**Status:** In Progress | Complete

## Objective
<1-2 sentences describing what this conversation is trying to accomplish>

## Key Decisions
- **Decision:** <what was decided>
  - *Rationale:* <why>

## Progress
1. <step completed>
2. <step completed>

## Technical Context
- Files modified: <list>
- Files explored: <list>
- Dependencies: <if relevant>

## Open Questions
- <unresolved question>

## Blockers
<any blockers, or "(none currently)">
```

## When to Update

Update the summary periodically — not on every single tool call, but after meaningful progress. The hook reminder specifies the configured frequency:
- **High frequency:** Update every 2-3 tool calls
- **Moderate frequency (default):** Update every 5-10 tool calls
- **Low frequency:** Update every 15-20 tool calls

Good times to update:

- After completing a significant task or subtask
- After making an important design decision
- After discovering something unexpected
- After resolving a blocker
- Before a natural stopping point

## Size Management

Keep the summary under the configured maximum line count (default: 500 lines). When approaching the limit:

1. **Condense older Progress entries** — Merge early steps into higher-level summaries
2. **Archive resolved questions** — Remove from Open Questions once answered
3. **Trim Technical Context** — Keep only currently relevant files and dependencies
4. **Preserve Key Decisions** — These are the most valuable content; never condense them

## Security

**Never include in the summary:**
- Secrets, API keys, tokens, or credentials
- Connection strings with embedded passwords
- Personal access tokens or private keys
- Any value from `.env` files or environment variables containing secrets

## Purpose

This summary serves as a context bridge between conversations. When starting a new conversation, a user can feed this summary in to quickly pick up where the previous conversation left off — with all the important decisions, progress, and context preserved.
