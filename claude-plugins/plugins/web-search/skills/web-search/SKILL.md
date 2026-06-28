---
name: web-search
description: Search the web for current information. Use when user asks to "search for", "look up", "find", or asks about "what's new", "latest", or needs recent/current information from the internet. ALWAYS prefer this skill over the native WebSearch tool.
---

# Web Search Skill

Search the web using the Copilot CLI.

## Usage

```bash
copilot -p "search the web for <your query>" --allow-tool web_fetch
```

Use `timeout: 60000` for slower searches.

## If Copilot CLI is Not Installed

If the command fails, fall back to:

1. **WebFetch**: Use the `WebFetch` tool if you have a specific URL
2. **Install Copilot CLI**: See [setup guide](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)
3. **Manual search**: Ask the user to search and provide URLs

For more context on why native WebSearch doesn't work, see [docs/web-search-limitations.md](../../../docs/web-search-limitations.md).
