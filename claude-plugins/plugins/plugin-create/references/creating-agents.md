# Creating Agents

Agents are autonomous units that execute multi-step workflows. Unlike skills (which provide guidance), agents actively perform tasks with their own context window.

## When to Create an Agent

Create an agent when:
- Multi-step workflows need autonomous execution
- Tasks require specialized personas or expertise
- Fresh context is beneficial (isolates work from main session)
- Parallel execution across multiple agents is needed

**Use a skill instead when:**
- Claude just needs domain knowledge to apply
- No autonomous execution is required
- Guidance should be in the main context

## Agent vs Skill

| Aspect | Agent | Skill |
|--------|-------|-------|
| **Context** | Runs in own context window | Loaded into main context |
| **Execution** | Actively performs tasks | Provides guidance |
| **Invocation** | Task tool or natural language | Auto-triggered by description |
| **Use case** | Multi-step workflows | Domain knowledge |

## Agent Anatomy

Agents are markdown files with YAML frontmatter in the `agents/` directory:

```
my-plugin/
└── agents/
    └── my-agent.md
```

### Agent Definition Structure

```markdown
---
name: my-agent
description: ALWAYS use this agent when [trigger conditions].
color: blue
---

# Agent Title

You are a specialized agent that [role description].

## Instructions

[Detailed instructions for the agent's behavior]
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Agent identifier |
| `description` | Yes | When to use this agent (critical for activation) |
| `color` | No | Display color in UI |

## Creating an Agent: Step-by-Step

### Step 1: Define the Agent's Role

Identify:
- What specific workflows does this agent handle?
- What expertise or persona should it embody?
- When should it be invoked?

### Step 2: Create Agent File

Create `agents/my-agent.md` in your plugin:

```markdown
---
name: my-agent
description: ALWAYS use this agent when the user asks to 'do X', 'perform Y', or mentions [topic].
color: purple
---

# My Agent

You are a specialized agent for [domain]. You understand [expertise areas].

## Core Responsibilities

1. [Primary responsibility]
2. [Secondary responsibility]
3. [Tertiary responsibility]

## Workflow

When invoked, follow these steps:

1. **Assess**: [What to evaluate first]
2. **Plan**: [How to structure the work]
3. **Execute**: [How to perform the work]
4. **Verify**: [How to validate results]

## Guidelines

- [Important guideline 1]
- [Important guideline 2]
- [Important guideline 3]

## Output Format

[Specify expected output structure if applicable]
```

### Step 3: Write Effective Description

The description field is critical for activation. Include:
- **ALWAYS** keyword for reliability
- Specific trigger phrases
- Topics that should invoke this agent

**Example:**

```yaml
description: ALWAYS use this agent for any code review request including "review changes", "review my changes", "code review", "review PR", or when git diffs are detected.
```

### Step 4: Configure Permissions (Optional)

Agents can restrict available tools:

```yaml
---
name: read-only-analyzer
description: Use for analysis tasks that should not modify files.
allowed-tools: Read, Grep, Glob
---
```

### Step 5: Test the Agent

1. Restart Claude Code
2. Use trigger phrases to invoke the agent
3. Verify behavior matches expectations
4. Iterate on instructions

## Invoking Agents

### Via Natural Language

```
"Have the code reviewer check my changes"
"Use the architect agent to review this design"
```

### Via Task Tool

```markdown
Use the Task tool with:
- agent: my-agent
- prompt: [specific task]
```

## Real Example: Code Reviewer Agent

```markdown
---
name: code-reviewer
description: ALWAYS use this agent for any code review request including "review changes", "review my changes", "code review", "review PR", or when git diffs are detected.
color: purple
---

# Code Reviewer

You are a specialized code reviewer that understands engineering best practices and adapts to repository-specific standards.

## Review Process

1. Read PR title and description to understand intent
2. Check AGENTS.md and CLAUDE.md for repo guidelines
3. Analyze diff for issues
4. Score issues by confidence (0-100)
5. Filter to high-confidence issues only

## Guidelines

- Be direct and professional
- Verify issues before flagging
- Respect repository prohibitions
- Limit inline comments to 3-5 per PR
```

## Agent Location by Tier

| Tier | Location |
|------|----------|
| Personal | `skills/local/my-plugin/agents/` |
| Niche | `.claude/skills/my-plugin/agents/` or `.claude/agents/` |
| Org-Specific | `org-agents/plugins/my-plugin/agents/` |
| General | `claude-plugins/plugins/my-plugin/agents/` |

## Common Mistakes

### Weak description

**Bad:**
```yaml
description: Code review agent
```

**Good:**
```yaml
description: ALWAYS use this agent for any code review request including "review changes", "code review", "review PR", or when git diffs are detected.
```

### Missing ALWAYS keyword

Without "ALWAYS", agents may not activate reliably.

### Too broad scope

Agents should be specialized. If an agent tries to do everything, it becomes unfocused.

### No workflow structure

Agents need clear step-by-step instructions. Vague guidance leads to inconsistent behavior.
