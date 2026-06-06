# Code Simplifier Plugin

Simplifies and refines code for clarity, consistency, and maintainability while preserving all functionality.

## Overview

This plugin provides intelligent code simplification that focuses on:

- **Clarity over cleverness** - Readable code beats compact code
- **Project standards** - Follows CLAUDE.md/AGENTS.md conventions
- **Functionality preservation** - Never changes what code does, only how
- **Balanced simplification** - Avoids over-engineering in either direction

## When It Activates

The skill activates when you:

- Ask to "simplify", "clean up", or "refactor" code
- Request "improved readability" or "cleaner code"
- Want code reviewed for maintainability

## Key Behaviors

- Reduces unnecessary complexity and nesting
- Eliminates redundant code and abstractions
- Improves naming for clarity
- **Avoids nested ternaries** - uses switch/if-else instead
- Removes obvious comments that just repeat the code
- Respects existing helpful abstractions

## Usage

```
# After writing code
"Please simplify this code"

# For specific files
"Clean up the authentication logic in auth.ts"

# For broader review
"Review this module for maintainability and simplify where appropriate"
```

## Installation

Add claude-plugins marketplace to your project:

```bash
/plugin marketplace add ~/.local/share/chezmoi/claude-plugins
```

Then enable the plugin:

```bash
/plugin enable code-simplifier
```

## Attribution

Based on the [code-simplifier plugin](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-simplifier) from Anthropic's official Claude plugins.

**Pinned to commit:** `f1be96f0fb58d5aaf2840ca7d7036d5c0923742c`

### Customizations from upstream

- Removed `model: opus` to use default Sonnet (more cost-effective, sufficient for code simplification)
- Adapted skill description for claude-plugins activation patterns
- Structured as claude-plugins plugin format (skills/ directory, plugin.json)

### Update strategy

To update from upstream:
1. Check [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) for updates
2. Compare changes in **upstream's** `plugins/code-simplifier/agents/code-simplifier.md`
3. Apply relevant updates to `skills/SKILL.md`, maintaining our customizations
4. Update the pinned commit SHA in this README

### License

Source repository is Apache 2.0 licensed.
