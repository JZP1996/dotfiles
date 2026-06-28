---
name: pr-feedback-addresser
description: Address PR review feedback by responding to comments, optionally adding thumbs up reactions to accepted feedback, and resolving review threads. Use ONLY when user explicitly asks to "address PR feedback", "respond to review comments", or "resolve PR review threads". Do NOT activate for general PR discussion or review.
---

# PR Feedback Addresser

Systematically address PR review feedback by responding to each comment, acknowledging feedback, and resolving accepted threads.

## When to Activate

- User asks to "address PR feedback"
- User asks to "respond to review comments"
- User asks to "resolve PR comments"
- User mentions "acknowledge feedback" on a PR

## Process

For each review comment on the PR:

1. **Read the feedback**: Understand what the reviewer is asking or suggesting
2. **Reply with one sentence**: Add a brief, professional response acknowledging the feedback
3. **React with thumbs up (if accepting)**: Apply 👍 reaction when you agree and will implement the suggestion
4. **Resolve the thread (if appropriate)**: Use GraphQL API to mark the conversation as resolved when the feedback has been addressed and doesn't require further discussion

## Response Guidelines

### Reply Format

- Keep responses to **one sentence**
- Be professional and appreciative
- Indicate the action taken (if any)

**Good examples**:

- "Good catch, fixed in the latest commit."
- "Thanks for the suggestion, updated to use the recommended pattern."
- "Agreed, refactored to improve readability."
- "Added the missing error handling as suggested."

**Avoid**:

- Multi-paragraph responses
- Defensive or argumentative tone
- Vague acknowledgments like "OK" or "Done"

### When NOT to Resolve

Do not resolve threads if:

- The feedback requires discussion or clarification
- You disagree with the suggestion and want to explain why
- The change hasn't been made yet

In these cases, reply but leave the thread open for further discussion.

## Before Committing Fixes

After implementing feedback, perform a self-review to catch follow-on issues and reduce review iterations:

1. **Check consistency**: Do your changes match patterns in similar files? (e.g., if updating README.md, check SKILL.md and SKILLS.md too)
2. **Verify completeness**: Did you update ALL occurrences? Search for related terms across the codebase
3. **Validate syntax**: Are code examples, JSON, markdown tables, etc. syntactically correct?
4. **Cross-reference guidelines**: Do your changes align with AGENTS.md and other documented standards?
5. **Simulate the next review**: apply the active code review checklist to your changes:
   - Does this match patterns in the rest of the file/codebase?
   - Is this a real issue or would it be filtered as a false positive?
   - Are there specific violations of AGENTS.md or CLAUDE.md?
   - Would a senior engineer flag this?

This proactive check significantly reduces the number of review cycles needed to get a PR approved.

## Implementation

**Important**: Most operations require GraphQL API. REST endpoints have limitations.

### Get PR Review Threads and Comments (GraphQL)

```bash
gh api graphql -f query='
  query {
    repository(owner: "OWNER", name: "REPO") {
      pullRequest(number: PR_NUMBER) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 10) {
              nodes {
                id
                databaseId
                body
              }
            }
          }
        }
      }
    }
  }
'
```

### Reply to a Review Thread (GraphQL)

Use `addPullRequestReviewThreadReply` mutation:

```bash
gh api graphql -f query='
  mutation {
    addPullRequestReviewThreadReply(input: {
      pullRequestReviewThreadId: "PRRT_xxx",
      body: "Thanks, fixed in the latest commit."
    }) {
      comment {
        id
      }
    }
  }
'
```

### Add Thumbs Up Reaction (REST)

Reactions work via REST API using the comment's `databaseId`:

```bash
gh api repos/{owner}/{repo}/pulls/comments/{databaseId}/reactions \
  -X POST -f content="+1"
```

### Resolve Review Thread (GraphQL)

Use the [resolveReviewThread mutation](https://docs.github.com/en/graphql/reference/mutations#resolvereviewthread):

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: {threadId: "PRRT_xxx"}) {
      thread {
        isResolved
      }
    }
  }
'
```

The thread ID (`PRRT_xxx`) is obtained from the initial query above.

## Output

After addressing all feedback, summarize:

```
Addressed 5 review comments on PR #123:
- Replied to each comment with acknowledgment
- Added 👍 reaction to 5 comments
- Resolved 5 review threads
```

## Notes

- Only resolves threads where you've actually addressed the feedback
- Respects ongoing discussions by not resolving threads that need more conversation
- Uses GitHub CLI (`gh`) for all API operations
