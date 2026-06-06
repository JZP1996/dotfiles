# Creating MCP Servers

MCP (Model Context Protocol) servers provide Claude with tool access to external systems. They execute code and have significant security and performance implications.

## When to Use MCP Servers

Use an MCP server when:
- Claude needs to interact with external APIs or services
- Real-time data access is required (not static knowledge)
- Tool-based interaction is more natural than skill guidance

**Do not use MCP when:**
- Static domain knowledge is sufficient (use a skill instead)
- The integration is one-time or rarely used
- Security review cannot be completed

## Context Cost Warning

Each MCP server adds **15-25K tokens** to context for tool definitions and history. Use sparingly.

## MCP Server Configuration

MCP servers are configured in `plugin.json` via the `mcpServers` field.

### Basic Example

```json
{
  "name": "my-mcp-plugin",
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

### Configuration Fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Server type: `stdio` (standard I/O) |
| `command` | Yes | Executable to run |
| `args` | No | Command-line arguments |
| `env` | No | Environment variables |

### Using CLAUDE_PLUGIN_ROOT

The `${CLAUDE_PLUGIN_ROOT}` variable resolves to the plugin's directory, allowing portable paths:

```json
{
  "command": "node",
  "args": ["${CLAUDE_PLUGIN_ROOT}/src/server.js"]
}
```

## Creating an MCP Server: Step-by-Step

### Step 1: Design the Tool Interface

Define what tools the server provides:
- Tool names and descriptions
- Input parameters and types
- Expected outputs

### Step 2: Implement the Server

Create a server that implements the MCP protocol. Common implementations:
- **Node.js**: Use `@modelcontextprotocol/sdk`
- **Python**: Use `mcp` package

**Example Node.js server structure:**

```javascript
// src/server.js
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server({
  name: 'my-server',
  version: '1.0.0',
}, {
  capabilities: {
    tools: {}
  }
});

// Define tools
server.setRequestHandler('tools/list', async () => ({
  tools: [{
    name: 'my_tool',
    description: 'Description of what this tool does',
    inputSchema: {
      type: 'object',
      properties: {
        param: { type: 'string', description: 'Parameter description' }
      },
      required: ['param']
    }
  }]
}));

// Handle tool calls
server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'my_tool') {
    const result = await doSomething(request.params.arguments.param);
    return { content: [{ type: 'text', text: result }] };
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

### Step 3: Configure in plugin.json

```json
{
  "name": "my-mcp-plugin",
  "version": "1.0.0",
  "description": "Plugin description",
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/src/server.js"]
    }
  }
}
```

### Step 4: Handle Credentials Securely

**Never embed credentials in plugin.json or server code.**

Use environment variables:

```json
{
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/src/server.js"],
      "env": {
        "API_KEY": "${MY_API_KEY}"
      }
    }
  }
}
```

Users set environment variables separately (e.g., in `.env` files that are gitignored).

### Step 5: Test Locally

Test the server before distributing:

1. Register the plugin in local marketplace
2. Enable in settings
3. Restart Claude Code
4. Verify tools appear and function correctly

### Step 6: Security Review

For Org-Specific and General tier:
- Document what the server accesses
- List permissions required
- Identify potential risks
- Submit for security review

## Security Considerations

### MCP servers execute code

Unlike skills (which are instructions), MCP servers run actual code. Review carefully:
- What external services are accessed?
- What data is transmitted?
- What permissions are required?

### Credential handling

- Never commit credentials
- Use environment variables
- Document required credentials in README

### Network access

- Validate URLs before fetching
- Avoid sending sensitive data to unapproved services
- Log access for audit trails

### Local vs CI usage

Some MCP servers are **local use only** (e.g., those using personal credentials). Mark clearly:

```json
{
  "description": "My MCP server. LOCAL USE ONLY - not for GitHub Actions."
}
```

## Real Example: Slack MCP

```json
{
  "name": "slack-mcp",
  "version": "1.0.2",
  "description": "Slack MCP server with search fix. LOCAL USE ONLY.",
  "mcpServers": {
    "slack": {
      "type": "stdio",
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/src/patched-server.js"]
    }
  }
}
```

## Common Mistakes

### Embedding credentials

**Bad:** Hardcoding API keys in server code or plugin.json

**Good:** Using environment variables with clear documentation

### Missing error handling

MCP servers should handle errors gracefully and return meaningful messages.

### Excessive tool surface

Each tool adds to context. Provide focused, minimal tool sets.

### No local testing

Always test servers locally before distributing.
