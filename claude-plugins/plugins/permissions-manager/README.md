# Permissions Manager Skill

Manage Claude Code permissions conversationally by updating settings files.

## Features

- **Permanent permissions**: Add tools/commands to the allow list
- **Project or global scope**: Update `.claude/settings.json` (project) or `~/.claude/settings.json` (global)
- **Natural language**: Responds to phrases like "permanently allow git commands"
- **Permission review**: List current permissions and suggest cleanups

## Installation

Add claude-plugins marketplace to your project:

```bash
/plugin marketplace add ~/.local/share/chezmoi/claude-plugins
```

Then enable the plugin:

```bash
/plugin enable permissions-manager
```

## Usage

Ask Claude to manage permissions:

```
Permanently allow git and gh commands
```

```
Always permit file edits without asking
```

```
Show me my current permissions
```

```
Allow filesystem MCP tools globally
```

## How It Works

1. Parses your request to identify the tools/patterns to allow
2. Reads the appropriate settings file (project or global)
3. Adds the permission to the `permissions.allow` array
4. Writes the updated settings file

## Permission Patterns

Common patterns you can allow:

| Request                | Permission Added     |
| ---------------------- | -------------------- |
| "allow git commands"   | `Bash(git:*)`        |
| "allow gh commands"    | `Bash(gh:*)`         |
| "allow file edits"     | `Edit`, `Write`      |
| "allow filesystem MCP" | `mcp__filesystem__*` |
| "allow git MCP"        | `mcp__git__*`        |
| "allow all bash"       | `Bash(:*)`           |

## Scope

- **Project** (default): Updates `.claude/settings.json` in the current repo
- **Global**: Updates `~/.claude/settings.json` for all projects

Specify scope with phrases like "globally allow" or "allow in this project".

## Support

File issues at https://github.com/~/.local/share/chezmoi/claude-plugins/issues
