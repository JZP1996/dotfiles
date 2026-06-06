# Creating Commands

Commands are user-invoked actions accessed via slash syntax (`/plugin:command-name`). Unlike skills (auto-triggered) or agents (autonomous), commands require explicit user invocation.

## When to Create a Command

Create a command when:
- Users need explicit control over when to trigger functionality
- A specific workflow should run on-demand
- Arguments need to be passed at invocation time
- The action should never auto-trigger

**Use a skill instead when:**
- Functionality should auto-apply based on context
- No explicit invocation is needed

**Use an agent instead when:**
- Autonomous multi-step execution is needed
- Fresh context is beneficial

## Command Anatomy

Commands are markdown files with YAML frontmatter in the `commands/` directory:

```
my-plugin/
└── commands/
    └── my-command.md
```

Or in the niche tier:

```
.claude/commands/
└── my-command.md
```

### Command Definition Structure

```markdown
---
description: Brief description of what this command does
allowed-tools: Bash, Read, Write
---

[Command instructions - what Claude should do when invoked]
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `description` | Yes | Brief description shown in command list |
| `allowed-tools` | No | Restrict which tools the command can use |

## Creating a Command: Step-by-Step

### Step 1: Define the Command's Purpose

Identify:
- What specific action does this command perform?
- What inputs (if any) does it need?
- What output should it produce?

### Step 2: Create Command File

Create `commands/my-command.md`:

```markdown
---
description: Brief description of command functionality
---

Perform the following workflow:

1. **Step 1**: [First action]
2. **Step 2**: [Second action]
3. **Step 3**: [Third action]

## Output

[Specify expected output format]
```

### Step 3: Add Arguments (Optional)

Commands can accept arguments via `$ARGUMENTS`:

```markdown
---
description: Generate a report for the specified date range
---

Generate a report using the provided arguments: $ARGUMENTS

If no arguments provided, prompt the user for:
- Start date
- End date
- Report type
```

Users invoke with: `/plugin:generate-report 2024-01-01 2024-01-31`

### Step 4: Restrict Tools (Optional)

Limit available tools for security:

```markdown
---
description: Analyze code without making changes
allowed-tools: Read, Grep, Glob
---
```

Available tools: `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash`, `Browser`

### Step 5: Test the Command

1. Restart Claude Code
2. Invoke via `/plugin:command-name` or `/user:command-name`
3. Verify behavior
4. Iterate on instructions

## Invoking Commands

### Plugin Commands

```
/plugin-name:command-name [arguments]
```

Example: `/claude-plugins:health`

### User Commands (Niche Tier)

For commands in `.claude/commands/`:

```
/user:command-name [arguments]
```

Example: `/user:commit`

## Real Example: Commit Command

```markdown
---
description: Smart commit workflow with conventional commit message generation
allowed-tools: Bash, AskUserQuestion
---

Perform a smart commit workflow:

1. **Check Status**
   Run `git status` to see staged and unstaged changes

2. **If nothing staged:**
   Show unstaged changes and ask what to stage

3. **Analyze Staged Changes**
   Run `git diff --cached` to understand what's being committed

4. **Generate Commit Message**
   Create a conventional commit message:
   - Type: feat, fix, docs, style, refactor, test, chore
   - Scope: affected area (optional)
   - Description: imperative mood, lowercase, no period

5. **Get User Confirmation**
   Show proposed message and ask to confirm

6. **Execute Commit**
   Only after confirmation, run `git commit`
```

## Command Location by Tier

| Tier | Location | Invocation |
|------|----------|------------|
| Personal | `skills/local/my-plugin/commands/` | `/my-plugin:command` |
| Niche | `.claude/commands/` | `/user:command` |
| Org-Specific | `org-agents/plugins/my-plugin/commands/` | `/my-plugin:command` |
| General | `claude-plugins/plugins/my-plugin/commands/` | `/my-plugin:command` |

## Common Mistakes

### Missing description

Every command needs a `description` field in frontmatter.

### Vague instructions

Commands need clear, step-by-step instructions. Ambiguous guidance leads to inconsistent behavior.

### No argument handling

If a command accepts arguments, handle the case when arguments are missing.

### Overly broad tool access

Restrict tools to what's actually needed. A read-only analysis command shouldn't have `Write` access.
