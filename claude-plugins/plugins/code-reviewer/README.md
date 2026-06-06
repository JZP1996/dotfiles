# Code Reviewer Plugin

Generic code reviewer agent that works across any repository.

## Features

- **Repo-agnostic**: Works with any repository
- **Auto-detects guidelines**: Searches for `AGENTS.md` in repository root
- **Linear MCP integration**: Queries Linear tickets for requirements
- **PR tagging**: Automatically tags reviewed PRs with `ai-reviewed` label
- **Opt-out mechanism**: Skip reviews on specific PRs using the `skip-ai-review` label
- **Author reminder on approval**: Tags PR author (if human) with a reminder to review vibe-coded work

## Installation

See the main [README.md](../../README.md#importing-as-plugin) for plugin installation instructions.

## Repository Setup

To get repo-specific code review guidelines, create `AGENTS.md` in your repository root. This [open standard](https://agents.md/) works with both Claude Code and [GitHub Copilot](https://github.blog/changelog/2025-08-28-copilot-coding-agent-now-supports-agents-md-custom-instructions/).

### Example `AGENTS.md`

```markdown
# [Your Repo] Code Review Guidelines

## Engineering Guidelines

Always review against: `@docs/engineering-guidelines.md`

## Repo-Specific Patterns

### Exception Handling

- [Your team's standards]

### Naming Conventions

- [Your team's standards]

### [Technology-Specific] Patterns

- [Your team's standards]

## GitHub Repository Context

- Organization: `[your-org]`
- Repository: `[your-repo]`
- Always use `gh cli` for GitHub operations
```

## Agent Usage

### What Happens

1. Agent loads base review logic from `plugins/code-reviewer/agents/code-reviewer.md`
2. Agent searches for and loads your repo's `AGENTS.md`
3. Agent combines both contexts to perform comprehensive review
4. PR is tagged with `ai-reviewed` label
5. Timestamp comment added to PR

## Tracking Reviews

Find all AI-reviewed PRs:

```bash
# List all reviewed PRs
gh pr list --label "ai-reviewed" --state all

# Review metrics for this month
gh pr list --label "ai-reviewed" --state all \
  --search "created:>=$(date -v-30d +%Y-%m-%d)" --json number,title,createdAt
```

## Skipping Reviews

You can opt out of AI review on specific PRs by adding the `skip-ai-review` label:

```bash
# Skip AI review on a PR
gh pr edit <PR_NUMBER> --add-label "skip-ai-review"

# Remove the label to resume reviews on future pushes
gh pr edit <PR_NUMBER> --remove-label "skip-ai-review"
```

When the `skip-ai-review` label is present:

- The review workflow exits early with success status
- No API calls are made to Claude/Vertex AI
- No comments or labels are added to the PR
- The label can be removed at any time to resume reviews on subsequent pushes

**Use cases:**

- PRs containing only generated code or dependency updates
- Cases where AI review would not provide value

## Support

- **Base agent**: Maintained in `plugins/code-reviewer/agents/code-reviewer.md`
- **Repo guidelines**: Owned by each team in their repo's `AGENTS.md`
- **Issues**: File in claude-plugins repository

## Test Coverage Recommendations

Test coverage suggestions are **off by default** to reduce false positive noise. The reviewer will NOT flag missing tests unless your repository explicitly opts in.

### Why Off by Default?

Generic "add tests" comments on trivial changes (catch blocks, config updates, bug fixes < 10 lines) create noise without value. Developers reported 100% noise on test recommendations for small changes.

### Opting In to Test Coverage Checks

To enable test coverage recommendations for your repository, add explicit requirements to your `AGENTS.md` or `CLAUDE.md`:

```markdown
# Code Review Requirements

## Test Coverage

- All new public APIs must have corresponding test coverage
- Bug fixes should include regression tests when feasible
```

When the repository explicitly requires test coverage, the reviewer will:
- Flag new public APIs/endpoints without tests (High severity)
- Flag complex new logic without tests (High severity)
- Still skip test recommendations for trivial defensive fixes

### What Counts as "Explicit Requirement"?

The reviewer looks for explicit language in `AGENTS.md` or `CLAUDE.md` such as:
- "require test coverage"
- "must have tests"
- "test coverage required"
- Specific test coverage policies for certain change types

Generic statements like "write good code" or "follow best practices" do NOT enable test recommendations.
