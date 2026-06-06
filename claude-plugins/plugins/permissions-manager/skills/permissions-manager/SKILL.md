---
name: permissions-manager
description: Manage Claude Code permissions by updating settings files. Use when user asks to permanently allow, always permit, or auto-approve tools, commands, or operations. Also use when asked to show, list, or review current permissions.
---

# Permissions Manager

Manage Claude Code permissions by updating `.claude/settings.json` (project) or `~/.claude/settings.json` (global).

## When to Activate

- User asks to "permanently allow" or "always permit" something
- User asks to "auto-approve" or "stop asking about" certain operations
- User asks to "show permissions" or "list what's allowed"
- User mentions "settings.json" in context of permissions

## Permission Syntax

Claude Code permissions use these patterns:

### Tool Names

- `Edit` - File editing
- `Write` - File writing/creation
- `Read` - File reading
- `Glob` - File pattern matching
- `Grep` - Content searching
- `WebFetch` - Web requests
- `WebSearch` - Web searches

### Bash Patterns

- `Bash(git:*)` - All git commands
- `Bash(gh:*)` - All GitHub CLI commands
- `Bash(npm:*)` - All npm commands
- `Bash(:*)` - All bash commands (use with caution)

### MCP Tool Patterns

- `mcp__filesystem__*` - All filesystem MCP tools
- `mcp__git__*` - All git MCP tools
- `mcp__memory__*` - All memory MCP tools

## Process

### Validation Steps

Before updating settings:

1. **Parse carefully**: Ensure the permission pattern matches user's stated intent
2. **Confirm risky patterns**: Always ask user to confirm before adding:
   - `Bash(:*)` - allows ALL bash commands
   - `Write` without context - allows writing to any file
   - Patterns with wildcards affecting security-sensitive operations
3. **Show what will be added**: Display the exact permission string before writing
4. **Read before write**: Always read existing settings to preserve other configuration

### To Add Permissions

1. **Determine scope**: Project (`.claude/settings.json`) or global (`~/.claude/settings.json`)
2. **Read current settings**: Load existing JSON, preserve other fields
3. **Parse user request**: Map natural language to permission patterns
4. **Update permissions.allow**: Add new patterns, avoid duplicates
5. **Write settings file**: Save with proper formatting

### Settings File Structure

```json
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash(git:*)",
      "Bash(gh:*)",
      "mcp__filesystem__*"
    ],
    "deny": []
  }
}
```

### To List Permissions

1. Read both project and global settings files
2. Display allowed patterns from each scope
3. Note which scope each permission comes from

## Natural Language Mapping

| User Says                        | Permission Pattern   |
| -------------------------------- | -------------------- |
| "git commands", "git operations" | `Bash(git:*)`        |
| "github cli", "gh commands"      | `Bash(gh:*)`         |
| "file edits", "editing files"    | `Edit`               |
| "file writes", "creating files"  | `Write`              |
| "filesystem operations"          | `mcp__filesystem__*` |
| "all bash", "any command"        | `Bash(:*)`           |
| "npm commands"                   | `Bash(npm:*)`        |
| "docker commands"                | `Bash(docker:*)`     |

## Scope Detection

- **Global indicators**: "globally", "everywhere", "all projects", "always"
- **Project indicators**: "this project", "this repo", "here", "locally"
- **Default**: Project scope (safer)

## Example Interactions

### User: "Permanently allow git and gh commands"

1. Scope: Project (default)
2. Patterns: `Bash(git:*)`, `Bash(gh:*)`
3. Read `.claude/settings.json`
4. Add to `permissions.allow`
5. Write updated file
6. Confirm: "Added `Bash(git:*)` and `Bash(gh:*)` to project permissions."

### User: "Globally allow file edits"

1. Scope: Global (`~/.claude/settings.json`)
2. Patterns: `Edit`
3. Read global settings
4. Add to `permissions.allow`
5. Write updated file
6. Confirm: "Added `Edit` to global permissions."

### User: "What permissions do I have?"

1. Read `.claude/settings.json` (project)
2. Read `~/.claude/settings.json` (global)
3. Display both:

   ```
   Project permissions (.claude/settings.json):
   - Bash(git:*)
   - Bash(gh:*)

   Global permissions (~/.claude/settings.json):
   - Edit
   - Write
   ```

## Safety Notes

- Always confirm before adding `Bash(:*)` (allows all commands)
- Warn about security implications of broad permissions
- Suggest specific patterns over wildcards when possible
