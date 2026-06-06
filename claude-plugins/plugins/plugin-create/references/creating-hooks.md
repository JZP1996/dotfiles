# Creating Hooks

Hooks are event-driven automation that runs when specific Claude Code events occur (e.g., after editing a file). They execute code and have significant security implications.

## When to Use Hooks

Use hooks when:
- Automation should run on specific events (post-edit, pre-commit)
- Consistent processing is needed without manual invocation
- Linting, formatting, or validation should auto-run

**Do not use hooks when:**
- Manual control is preferred (use a command)
- The automation is complex or requires context (use an agent)
- Security review cannot be completed

## Hook Events

| Event | When It Fires |
|-------|---------------|
| `PreToolUse` | Before a tool is used |
| `PostToolUse` | After a tool completes |

## Hook Configuration

Hooks can be configured in two locations:

### Option 1: In plugin.json

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Plugin with hooks",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.js\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

> **Note:** Use a Node.js shim (`run-hook.js`) for Windows compatibility. See [Windows Compatibility](#windows-compatibility) for details. For Unix-only hooks, `bash "quoted-path"` also works.

### Option 2: Separate hooks.json

Create `hooks/hooks.json`:

```json
{
  "description": "Run formatter after editing files",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.js\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Configuration Fields

### Hook Entry

| Field | Required | Description |
|-------|----------|-------------|
| `matcher` | Yes | Regex pattern for tool names (e.g., `Write\|Edit`) |
| `hooks` | Yes | Array of hook actions to execute |

### Hook Action

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Action type: `command` |
| `command` | Yes | Shell command or script path |
| `timeout` | No | Timeout in seconds |

## Creating a Hook: Step-by-Step

### Step 1: Identify the Event

Determine:
- What event should trigger the hook?
- What tools should match?
- What action should run?

### Step 2: Create the Hook Script

Create an executable script in `hooks/`:

```bash
#!/bin/bash
# hooks/format.sh

# Get the file that was edited (passed via environment)
FILE="$CLAUDE_FILE_PATH"

# Run formatter
if [[ "$FILE" == *.cs ]]; then
    dotnet csharpier "$FILE"
fi
```

Make it executable:

```bash
chmod +x hooks/format.sh
```

### Step 3: Configure the Hook

In `hooks/hooks.json`:

```json
{
  "description": "Run CSharpier after editing C# files",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.js\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Step 4: Test Locally

1. Register the plugin
2. Restart Claude Code
3. Perform the triggering action (e.g., edit a file)
4. Verify hook executes correctly

## Real Example: CSharpier Formatting

```json
{
  "description": "Run CSharpier after editing C# files for fast, consistent formatting",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.js\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

With script `hooks/csharpier-format.sh`:

```bash
#!/bin/bash

# Only run for C# files
if [[ "$CLAUDE_FILE_PATH" != *.cs ]]; then
    exit 0
fi

# Run CSharpier
dotnet csharpier "$CLAUDE_FILE_PATH" 2>/dev/null || true
```

## Security Considerations

### Hooks execute code

Unlike skills (instructions) or commands (user-invoked), hooks run automatically. Review carefully:
- What code executes?
- What files are accessed?
- What could go wrong?

### Timeout protection

Always set reasonable timeouts to prevent runaway processes:

```json
{
  "type": "command",
  "command": "./my-hook.sh",
  "timeout": 10
}
```

### Fail safely

Hook scripts should handle errors gracefully and not break the user's workflow:

```bash
#!/bin/bash
# Always exit 0 to not block Claude
my-command "$FILE" 2>/dev/null || true
```

### Audit trail

Log hook executions for debugging:

```bash
echo "$(date): Formatted $FILE" >> /tmp/hook-log.txt
```

## Hook Location by Tier

| Tier | Location |
|------|----------|
| Personal | `skills/local/my-plugin/hooks/` |
| Niche | `.claude/skills/my-plugin/hooks/` |
| Org-Specific | `org-agents/plugins/my-plugin/hooks/` |
| General | `claude-plugins/plugins/my-plugin/hooks/` |

## Common Mistakes

### Missing executable permission

Hook scripts must be executable (`chmod +x`).

### No timeout

Hooks without timeouts can hang indefinitely.

### Breaking on failure

Hooks should fail gracefully, not block Claude's workflow:

**Bad:**
```bash
#!/bin/bash
formatter "$FILE"  # Will fail if formatter not installed
```

**Good:**
```bash
#!/bin/bash
formatter "$FILE" 2>/dev/null || true
```

### Overly broad matcher

Match only the tools you need:

**Bad:**
```json
{"matcher": ".*"}  // Matches everything
```

**Good:**
```json
{"matcher": "Write|Edit"}  // Only file modifications
```

## Windows Compatibility

Hooks execute via `cmd.exe → node shim → bash → script.sh` on Windows. Follow these practices:

### Node.js Shim Pattern (Recommended)

On Windows, Claude Code spawns hook commands via `cmd.exe /d /s /c "command"`, which misparses paths containing spaces. The recommended solution is a **Node.js shim** — a thin `.js` wrapper that calls `execFileSync("bash", [scriptPath])`, bypassing shell interpretation for the bash invocation.

Create a `run-hook.js` alongside your shell script:

```javascript
#!/usr/bin/env node
"use strict";
// Template: copy this file and update SCRIPT for each hook plugin.
// If updating the shim logic, update ALL run-hook.js copies across plugins.
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const SCRIPT = "my-hook.sh";

let input = "";
try { input = fs.readFileSync(0, "utf8"); } catch { }

try {
  const result = execFileSync("bash", [path.join(__dirname, SCRIPT)], {
    input, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"],
  });
  if (result) process.stdout.write(result);
} catch (err) {
  if (err.code === "ENOENT") {
    process.stderr.write("run-hook.js: bash not found in PATH\n");
  } else if (err.stderr) {
    process.stderr.write(err.stderr);
  }
  if (err.stdout) process.stdout.write(err.stdout);
  else process.stdout.write("{}");
}
```

Then reference the `.js` file in `hooks.json`:

```json
{
  "type": "command",
  "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.js\"",
  "timeout": 10
}
```

**Why this works:**
1. `node.exe` is a native Windows executable that correctly handles quoted path arguments via the Windows CRT (`CommandLineToArgvW`)
2. `execFileSync("bash", [scriptPath])` calls `CreateProcess` directly — **no shell interpretation for the bash invocation**
3. `path.join(__dirname, SCRIPT)` resolves the script path correctly regardless of spaces
4. stdin (JSON from Claude Code) is piped through to the bash script, and stdout is piped back
5. Works identically on Unix — `node` and `bash` are available everywhere

### Simple Pattern (Unix-Only Hooks)

If your hook will **only** run on Unix/macOS (not Windows), you can skip the shim:

```json
{
  "type": "command",
  "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh\"",
  "timeout": 10
}
```

**Do NOT use bare paths:**
```json
{
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh"
}
```
This will fail on any Windows system where the repo path contains spaces.

### Path Normalization

Windows paths may use backslashes. Define a `_normalize_path()` helper and use it for
all path variables rather than normalizing each one inline:

```bash
# Normalize to forward slashes for POSIX compatibility.
_normalize_path() {
    local p="$1"
    # Convert Windows backslashes to forward slashes
    if [[ "$p" == *\\* ]]; then
        p="${p//\\//}"
    fi
    printf '%s' "$p"
}

# Usage — normalize every path that may arrive Windows-style
CWD="$(_normalize_path "${CWD:-}")"
HOME="$(_normalize_path "${HOME:-}")"
FILE_PATH="$(_normalize_path "$FILE_PATH")"
```

### Command Availability

Don't assume Unix tools are in PATH. Check before use:

```bash
# Check before using git
if command -v git >/dev/null 2>&1; then
    REPO_ROOT=$(_normalize_path "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)") || true
fi
```
