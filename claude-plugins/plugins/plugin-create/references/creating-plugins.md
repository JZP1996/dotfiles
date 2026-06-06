# Creating Plugins

A plugin is the packaging unit for Claude Code extensions. One plugin can contain skills, agents, commands, hooks, and MCP servers.

## When to Create a Plugin

Create a plugin when:
- Bundling related components (e.g., a skill + supporting agent + commands)
- Distributing capabilities via marketplace
- Organizing reusable tooling for a team or organization

## Plugin Anatomy

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json           # Plugin manifest (required)
├── skills/
│   └── SKILL.md              # Skill definitions (optional)
├── agents/
│   └── my-agent.md           # Agent definitions (optional)
├── commands/
│   └── my-command.md         # Slash commands (optional)
├── hooks/
│   └── hooks.json            # Hook configurations (optional)
├── references/               # Detailed documentation (optional)
├── scripts/                  # Executable utilities (optional)
└── assets/                   # Templates, images, etc. (optional)
```

## Plugin Manifest (plugin.json)

The `plugin.json` file is the plugin's manifest. It defines metadata and optionally configures MCP servers.

### Minimal Example

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Brief description of plugin capabilities"
}
```

### With MCP Server

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Plugin with external API access",
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/src/server.js"]
    }
  }
}
```

### Fields Reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Plugin identifier (lowercase, hyphens) |
| `version` | Yes | Semantic version (e.g., "1.0.0") |
| `description` | Yes | Brief description for plugin list |
| `mcpServers` | No | MCP server configurations |

## Marketplace Registration

Plugins are distributed via marketplaces. Each marketplace has a `marketplace.json` file.

### Personal Marketplace (skills/local/)

```json
{
  "plugins": [
    {"name": "my-plugin", "source": "./my-plugin", "description": "Personal plugin"}
  ]
}
```

### Org/General Marketplace

```json
{
  "plugins": [
    {"name": "my-plugin", "source": "./plugins/my-plugin", "description": "Shared plugin"}
  ]
}
```

### Adding Marketplace to Settings

Users add marketplaces via:

```bash
/plugin marketplace add ~/.local/share/chezmoi/claude-plugins
```

Or manually in `~/.claude/settings.json`:

```json
{
  "marketplaces": [
    "~/.local/share/chezmoi/claude-plugins"
  ]
}
```

## Creating a Plugin: Step-by-Step

### Step 1: Plan Components

Identify what components the plugin needs:
- **Skill** if Claude should auto-apply domain knowledge
- **Agent** if multi-step workflows are needed
- **Command** if users invoke via slash command
- **Hook** if automation should run on events
- **MCP Server** if external tool access is needed

### Step 2: Create Directory Structure

```bash
mkdir -p my-plugin/.claude-plugin
mkdir -p my-plugin/skills      # if adding skills
mkdir -p my-plugin/agents      # if adding agents
mkdir -p my-plugin/commands    # if adding commands
```

### Step 3: Create plugin.json

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Description of what this plugin provides"
}
```

### Step 4: Add Components

Add component files to appropriate directories. See reference guides:
- `references/creating-skills.md`
- `references/creating-agents.md`
- `references/creating-commands.md`
- `references/creating-hooks.md`
- `references/creating-mcp-servers.md`

### Step 5: Register in Marketplace

Add plugin to appropriate `marketplace.json`.

### Step 6: Enable Plugin

Enable in settings:

```json
{
  "enabledPlugins": {
    "my-plugin@marketplace-name": true
  }
}
```

### Step 7: Restart Claude Code

Restart to pick up new plugin.

## Version Management

- Use semantic versioning: MAJOR.MINOR.PATCH
- Increment MAJOR for breaking changes
- Increment MINOR for new features
- Increment PATCH for bug fixes

## Common Mistakes

### Missing plugin.json

Every plugin needs `.claude-plugin/plugin.json`. Without it, the plugin won't be discovered.

### Name mismatches

The plugin directory name, `plugin.json` name, and marketplace entry name must all match.

### Forgetting to register

Plugins must be registered in a `marketplace.json` to be discoverable (except niche-tier skills in `.claude/skills/` which are auto-discovered).

### Not restarting

Changes to plugins require restarting Claude Code.
