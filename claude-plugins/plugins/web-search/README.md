# Web Search Plugin

Search the web using Copilot CLI instead of native WebSearch tool.

## Why This Plugin?

The native `WebSearch` tool has limitations in Microsoft's internal network. This plugin uses Copilot CLI which integrates with GitHub's infrastructure and works reliably.

## Usage

The skill auto-triggers when you ask Claude to:
- "Search for..."
- "Look up..."
- "What's new in..."
- "Find the latest..."

## Requirements

- Copilot CLI installed and authenticated
- See [setup guide](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)

## Limitations

For details on why native WebSearch doesn't work, see [docs/web-search-limitations.md](../../docs/web-search-limitations.md).
