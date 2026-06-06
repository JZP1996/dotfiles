# PR Feedback Addresser Skill

Systematically address PR review feedback by responding to comments and resolving accepted feedback.

## Features

- **Comment responses**: Adds a one-sentence reply to each review comment
- **Reaction support**: Applies thumbs up reaction to accepted feedback
- **Thread resolution**: Resolves review threads via GitHub GraphQL API
- **Batch processing**: Handles all feedback on a PR in one pass

## Installation

Add the personal marketplace to your project:

```bash
/plugin marketplace add ~/.local/share/chezmoi/claude-plugins
```

## Usage

Ask Claude to address feedback on a PR:

```
Address the feedback on PR #123
```

Or:

```
Respond to review comments on this PR
```

## How It Works

1. Fetches all review comments on the PR
2. For each comment:
   - Adds a one-sentence response acknowledging the feedback
   - Applies a thumbs up reaction if accepting the feedback
   - Resolves the review thread using the GraphQL API

## Example Output

When the skill addresses feedback, you'll see:

**Reply posted to thread:**

> Good catch, fixed in the latest commit.

**Reaction added:**

The comment will show a 👍 reaction from your GitHub account.

**Thread resolved:**

The review thread will be marked as "Resolved" in the PR conversation, collapsing it from view.

**Summary:**

```
Addressed 5 review comments on PR #123:
- Replied to each comment with acknowledgment
- Added 👍 reaction to 5 comments
- Resolved 5 review threads
```

## GitHub API Usage

The skill uses:

- `gh api graphql` for replying to comments ([addPullRequestReviewThreadReply](https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthreadreply))
- `gh api graphql` for resolving review threads ([resolveReviewThread](https://docs.github.com/en/graphql/reference/mutations#resolvereviewthread))
- `gh api` REST for adding reactions to comments

## Requirements

- GitHub CLI (`gh`) authenticated with appropriate permissions
- Write access to the repository

## Support

File issues at https://github.com/~/.local/share/chezmoi/claude-plugins/issues
