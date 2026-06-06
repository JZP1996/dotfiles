---
name: pick-up-where-i-left-off
description: Pick up where you left off by loading a previous conversation summary. Use when asked to "pick up where I left off", "continue from last time", "load summary for", "what was I working on", or "restore context from a previous conversation".
---

# Pick Up Where You Left Off

Load a conversation summary to continue from where a previous session ended.

**Important:** This skill loads conversation summary files created by the conversation-summary plugin. It does NOT replace `/user:recover`, which provides broader session recovery (git status, SESSION-BOOTSTRAP.md, repo knowledge). Use both together for complete context loading.

## Step 1: Determine the Summary Directory

1. Check for a `.conversation-summary.json` config file:
   - First check `$HOME/.conversation-summary.json`
   - Then check the repository root for `.conversation-summary.json`
2. If a config file is found, read the `output_dir` field for a custom summary directory.
3. **Validate the path:** If a custom `output_dir` was found, verify that it:
   - Is a **relative path** (does not start with `/`)
   - Does **not** contain `..` (no parent directory traversal)
   - If validation fails, warn the user that the configured path is invalid and fall back to the default.
4. If no config file is found, `output_dir` is not set, or validation failed, use the default: `docs/local/summaries/`.

## Step 2: List Available Summaries

Use the Glob tool to find all `*.md` files in the summary directory (e.g., `docs/local/summaries/*.md`).

- If no files are found, tell the user no conversation summaries exist yet and suggest enabling the conversation-summary plugin by creating a `.conversation-summary.json` config file with `{"enabled": true}`.
- If files are found, proceed to matching.

## Step 3: Match by Keyword

If the user specified a topic (e.g., "continue work on auth-refactor"):

1. **Exact slug match:** Check if the topic matches the slug portion of any filename exactly (the part after the `YYYY-MM-DD-` date prefix, without the `.md` extension). For example, "auth-refactor" matches `2026-03-09-auth-refactor.md`.
2. **Partial slug match:** Check if the topic appears as a substring within any filename's slug portion. For example, "auth" matches `2026-03-09-auth-middleware-refactor.md`.
3. **Date match:** If the topic looks like a date (e.g., "2026-03-09", "yesterday", "last week"), match summaries by their date prefix.

**Matching priority:** Exact slug match > Partial slug match > Date match.

### Single Match

If exactly one summary matches, proceed directly to Step 5 (Load the Summary).

### Multiple Matches

If multiple summaries match, list them with their dates and let the user choose:

```
Found 3 summaries matching "auth":

1. 2026-03-09-auth-middleware-refactor.md
2. 2026-03-08-auth-debugging.md
3. 2026-03-05-auth-token-migration.md

Which one would you like to load?
```

### No Matches

If no summaries match the keyword, inform the user and list all available summaries as suggestions:

```
No summaries found matching "database" in docs/local/summaries/.

Available summaries:
- 2026-03-09-auth-middleware-refactor.md
- 2026-03-08-ci-pipeline-debugging.md

Would you like to load one of these instead?
```

## Step 4: No Topic Specified

If the user did not specify a topic (e.g., "pick up where I left off", "what was I working on"):

1. List the most recent 5-10 summaries sorted by filename date (most recent first).
2. Ask which one the user would like to load.

## Step 5: Load the Summary

Read the matched summary file using the Read tool.

## Step 6: Present Context

After reading the summary, present the key sections to the user:

- **Objective** -- What the conversation was trying to accomplish
- **Key Decisions** -- Important decisions made and their rationale
- **Progress** -- Steps completed so far
- **Open Questions** -- Unresolved questions or issues
- **Blockers** -- Any blockers noted

Then ask the user how they would like to proceed.

## Scope Clarification

This skill is specifically for loading conversation summary files from the `docs/local/summaries/` directory (or a custom directory configured via `.conversation-summary.json`). It does not:

- Replace `/user:recover` -- use that for broad session recovery
- Modify SESSION-BOOTSTRAP.md -- that is managed by session protocol
- Replay conversation transcripts -- it loads the summary, not the raw history
- Auto-trigger at session start -- it only activates when the user asks
