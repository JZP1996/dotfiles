---
name: plugin-create
description: "This skill should be used when the user wants to 'create a new Claude skill',
  'add a skill to Claude Code', 'make a Claude plugin', 'create a Claude MCP server',
  'add a Claude agent definition', 'create a Claude command', 'add Claude Code hooks',
  'make a skill for my repo', 'create an org-specific skill', 'add a local skill',
  'configure Claude Code skills', 'fix skill discovery issues',
  'set up a Claude MCP server', 'add a subagent definition', 'build a plugin component',
  or troubleshoot why Claude Code components aren't showing up in the plugin list."
---

# Component Builder

Create and manage Claude Code, Codex, GitHub Copilot, and other coding agent plugin components (skills, plugins, MCP servers, agents, commands, hooks) across all tiers.

## Tier Selection

Before creating any component, determine which tier matches your audience:

| Tier | Who Needs It? | Location | Review |
|------|---------------|----------|--------|
| **General** | All teams | `claude-plugins/plugins/` | CODEOWNERS + security review |
| **Org-Specific** | Your entire org (e.g., Edge, Teams) | `your-org-agents/plugins/` | Org CODEOWNERS |
| **Niche** | This repo's contributors only | Target repo's `.claude/skills/` | Standard PR review |
| **Personal** | Just you | `skills/local/` (gitignored) | Self |

**Quick decision:**
- "Just me" → Personal
- "This repo only" → Niche
- "My whole org" → Org-Specific
- "All teams" → General

## Component Types

Claude Code plugins can contain multiple component types. Select the type needed:

| Component | Purpose | Key File | Trigger |
|-----------|---------|----------|---------|
| **Skill** | Domain knowledge auto-applied by context | `skills/SKILL.md` | Description matching |
| **Agent** | Multi-step workflow automation | `agents/*.md` | Natural language or Task tool |
| **MCP Server** | External system tool access | `mcpServers` in `plugin.json` | Tool invocation |
| **Command** | User-invoked slash commands | `commands/*.md` | `/plugin:command-name` |
| **Hook** | Event-driven automation | `hooks` in `plugin.json` | Lifecycle events |
| **Plugin** | Packaging unit for all components | `.claude-plugin/plugin.json` | N/A (container) |

**Which component type?**
- "Claude should know this domain automatically" → **Skill**
- "Run a multi-step workflow when asked" → **Agent**
- "Need tool access to an external API/system" → **MCP Server**
- "Users type /something to invoke it" → **Command**
- "Something should happen on events (pre-commit, etc.)" → **Hook**
- "Bundle multiple components together" → **Plugin**

## Plugin Anatomy

A plugin can contain any combination of components:

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json           # Plugin manifest (name, version, description, mcpServers, hooks)
├── skills/
│   └── SKILL.md              # Skill definition with YAML frontmatter (optional)
├── agents/
│   └── my-agent.md           # Agent definition (optional)
├── commands/
│   └── my-command.md         # Slash command definition (optional)
├── hooks/
│   └── hooks.json            # Hook configurations (optional)
├── references/               # Detailed docs loaded as needed (optional)
├── scripts/                  # Executable utilities (optional)
└── assets/                   # Output resources — templates, images (optional)
```

## Progressive Disclosure

Components use a loading hierarchy to manage context efficiently:

1. **Metadata** (name + description) — always in context (~100 words)
2. **Main content** (SKILL.md body, agent instructions) — loaded when triggered (<5K words)
3. **Bundled resources** — loaded as needed by Claude (unlimited)

Keep main content lean. Move detailed documentation to `references/` files.

## Quick Creation Guide

### Create a Skill

Domain knowledge that Claude auto-applies.

**Personal tier:**
```bash
cd skills/local && cp -r example-skill.template/ my-skill/
```

**Niche tier:**
```bash
mkdir -p .claude/skills/my-skill/{.claude-plugin,skills}
```

Key files: `plugin.json` + `skills/SKILL.md` with YAML frontmatter.

See `references/creating-skills.md` for detailed guidance.

### Create an Agent

Autonomous multi-step workflow executor.

**Create file:** `agents/my-agent.md`

```markdown
---
name: my-agent
description: ALWAYS use this agent when [trigger conditions].
---

# Agent Title

[Instructions for agent behavior]
```

See `references/creating-agents.md` for detailed guidance.

### Create a Command

User-invoked slash command.

**Create file:** `commands/my-command.md`

```markdown
---
description: Brief description of command
allowed-tools: Bash, Read
---

[Instructions for command execution]
```

Invoke via `/plugin:command-name` or `/user:command-name`.

See `references/creating-commands.md` for detailed guidance.

### Create a Hook

Event-driven automation.

**Configure in `hooks/hooks.json`:**

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "./hooks/format.sh", "timeout": 10}]
    }]
  }
}
```

See `references/creating-hooks.md` for detailed guidance.

### Create an MCP Server

External system tool access. **Warning:** Each MCP server adds 15-25K tokens to context.

**Configure in `plugin.json`:**

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Plugin with MCP server",
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/src/server.js"]
    }
  }
}
```

See `references/creating-mcp-servers.md` for detailed guidance.

### Create a Plugin

Package for bundling components.

**Create `plugin.json`:**

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Brief description"
}
```

See `references/creating-plugins.md` for detailed guidance.

## Validation Checklist

### All Components

- [ ] Names match across: directory, `plugin.json`, component frontmatter, marketplace entry
- [ ] Plugin registered in appropriate `marketplace.json` (except Niche tier)
- [ ] Enabled in settings (`settings.local.json` for Personal, `settings.json` for others)
- [ ] Claude Code restarted after changes

### Skills

- [ ] `SKILL.md` has valid YAML frontmatter (`name` and `description`)
- [ ] Description uses third person ("This skill should be used when...")
- [ ] Description includes specific trigger phrases
- [ ] Body uses imperative/infinitive form
- [ ] Body is lean (<5K words)

### Agents

- [ ] Frontmatter includes `name` and `description`
- [ ] Description includes "ALWAYS" for reliable activation
- [ ] Instructions are clear and step-by-step

### Commands

- [ ] Frontmatter includes `description`
- [ ] `$ARGUMENTS` handled if command accepts input
- [ ] `allowed-tools` restricted appropriately

### Hooks

- [ ] Hook scripts are executable (`chmod +x`)
- [ ] Timeout is set
- [ ] Scripts fail gracefully (exit 0)

### MCP Servers

- [ ] No credentials embedded in code or config
- [ ] Server tested locally before distribution
- [ ] Security review completed (Org/General tier)

### Org-Specific/General Tier

- [ ] Security boundaries documented (CAN/CANNOT/MUST CONFIRM)
- [ ] Security review completed

## Common Mistakes

### Weak trigger description

**Bad:** `"Provides guidance for deployment."`

**Good:** `"This skill should be used when the user asks to 'deploy to production', 'run deployment', or 'rollback a release'."`

### Name mismatches

Directory name, `plugin.json` name, frontmatter name, and marketplace entry must all match. Mismatches prevent discovery.

### Wrong tier selection

Choose the narrowest tier that serves your audience. Don't put repo-specific tools in claude-plugins.

### Missing ALWAYS in agent description

Agents without "ALWAYS" in the description may not activate reliably.

### Embedded credentials (MCP)

Never embed API keys or tokens. Use environment variables.

### Too much content

**Bad:** A single 4,000-word SKILL.md with all documentation inline.

**Good:** A lean SKILL.md (<2K words) with `references/detailed-guide.md` for extended content. Progressive disclosure keeps context lean.

### Forgetting to restart

Changes to plugins require restarting Claude Code.

## Troubleshooting

### Component does not appear in `/plugin` list

1. Verify plugin structure exists with `plugin.json`
2. Verify marketplace registration (Personal/Org/General tiers)
3. Verify names match across all locations
4. Restart Claude Code

### Component appears but is not enabled

| Tier | Check |
|------|-------|
| Personal | `.claude/settings.local.json` has `"my-plugin@local-skills": true` |
| Niche | `.claude/settings.json` has `"my-plugin": true` |
| Org-Specific | Plugin enabled in `~/.claude/settings.json` |
| General | Plugin enabled in `~/.claude/settings.json` |

### Skill enabled but does not auto-activate

1. Check `description` field — includes specific trigger phrases?
2. Test with `/my-skill` to manually invoke
3. Verify description is not too short or vague

### Agent does not activate

1. Check description includes "ALWAYS"
2. Verify trigger phrases match expected user input
3. Test via Task tool directly

### Hook does not run

1. Verify script is executable (`chmod +x`)
2. Check `matcher` regex matches expected tools
3. Check hook script runs successfully standalone
4. Check timeout is sufficient

### MCP server not available

1. Verify `mcpServers` in `plugin.json` is correct
2. Check server executable exists at specified path
3. Test server manually
4. Check Claude Code logs for errors

### Plugin errors tab shows issues

1. Open `/plugin` → Errors tab
2. Check for JSON syntax errors
3. Verify all source paths are correct

## Key Rules

1. **Names must match** — directory, `plugin.json`, frontmatter, marketplace entry
2. **Choose the right tier** — Personal, Niche, Org-Specific, or General
3. **Security boundaries required** — Org-Specific/General components must document CAN/CANNOT/MUST CONFIRM
4. **Restart required** — Always restart Claude Code after adding or modifying components
5. **No embedded secrets** — Use environment variables for credentials

## Reference Files

For detailed guidance on each component type:

- **Skills**: `references/creating-skills.md`
- **Plugins**: `references/creating-plugins.md`
- **MCP Servers**: `references/creating-mcp-servers.md`
- **Agents**: `references/creating-agents.md`
- **Commands**: `references/creating-commands.md`
- **Hooks**: `references/creating-hooks.md`

## Related Resources

- **plugin-manager** — manage marketplace plugins (`/plugin` command)
- **`plugins/SKILLS.md`** — contributing skills to claude-plugins marketplace
- **`docs/org-agents-guide.md`** — creating org-specific agents repositories
