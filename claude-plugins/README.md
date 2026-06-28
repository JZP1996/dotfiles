# Personal Claude Code Marketplace

Curated Claude Code plugins for personal use. Managed via chezmoi.

## Layout

```text
~/.local/share/chezmoi/
├── claude-plugins/                   ← this dir (NOT deployed)
│   ├── .claude-plugin/
│   │   └── marketplace.json
│   ├── external-plugins.json         ← upstream marketplaces/plugins installed directly
│   ├── disabled-plugins.json         ← installed plugins disabled by default
│   ├── plugins/<name>/...
│   └── install.sh                    ← register marketplace + install plugins
└── dot_agents/
    └── skills/
        ├── <name>/SKILL.md           ← personal skill (deployed as-is)
        └── symlink_<name>.tmpl       ← symlinks into claude-plugins/plugins/<name>/skills/<name>
```

- `claude-plugins/` is ignored by chezmoi (see `.chezmoiignore`) because Claude
  Code reads plugins directly from this source path — no need to deploy.
- `dot_agents/skills/` deploys to `~/.agents/skills/`, exposing pure-skill
  plugins (and personal skills) to OpenCode and any other agent that reads
  `~/.agents/skills/`.

## Setup on a new machine

1. `chezmoi init` clones this repo and runs `chezmoi apply` (creates the
   `~/.agents/skills/*` symlinks and personal skills).
2. Install the marketplace and plugins into Claude Code:

   ```bash
   ~/.local/share/chezmoi/claude-plugins/install.sh
   ```

   Idempotent. Re-run anytime to install newly added plugins and update external
   plugins.

## Add a plugin

1. Create the directory under `plugins/`:

   ```text
   plugins/<plugin-name>/
   ├── .claude-plugin/
   │   └── plugin.json          { "name": "...", "version": "...", "description": "..." }
   └── skills/
       └── <plugin-name>/       (directory name MUST match SKILL.md frontmatter `name`)
           └── SKILL.md
   ```

2. Register it in `.claude-plugin/marketplace.json` under `plugins`.

3. If the plugin is a pure SKILL (no hooks/agents specific to Claude Code's
   lifecycle), also expose it to other agents by adding a symlink template to
   `~/.local/share/chezmoi/dot_agents/skills/symlink_<plugin-name>.tmpl`
   containing:

   ```text
   {{ "{{ .chezmoi.sourceDir }}" }}/claude-plugins/plugins/<plugin-name>/skills/<plugin-name>
   ```

   Then `chezmoi apply ~/.agents`.

4. Install into Claude Code:

   ```bash
   ./install.sh
   ```

## Add a personal (non-plugin) skill

Drop a directory with `SKILL.md` directly under
`~/.local/share/chezmoi/dot_agents/skills/<name>/SKILL.md`. Run `chezmoi apply`.

## External plugins

Some plugins are installed directly from their upstream marketplace rather than
vendored into this repository. `install.sh` refreshes those marketplaces and
updates already-installed external plugins on every run.

Declare them in `external-plugins.json`:

```json
{
   "marketplaces": [
      {
         "name": "karpathy-skills",
         "source": "multica-ai/andrej-karpathy-skills",
         "plugins": ["andrej-karpathy-skills"]
      },
      {
         "name": "claude-plugins-official",
         "source": "anthropics/claude-plugins-official",
         "plugins": ["code-review", "code-simplifier", "skill-creator"]
      }
   ]
}
```

Declare plugins that should be installed but disabled by default in
`disabled-plugins.json`:

```json
{
   "plugins": [
      "plugin-dev@claude-plugins-official"
   ]
}
```

Enable one manually when needed:

```bash
claude plugin enable plugin-dev@claude-plugins-official
```

If an external plugin contains a pure skill that should also be exposed through
`~/.agents/skills/`, add a symlink template pointing at Claude Code's marketplace
checkout, for example:

```text
{{ "{{ .chezmoi.homeDir }}" }}/.claude/plugins/marketplaces/karpathy-skills/skills/karpathy-guidelines
```

## References

- [Claude Code plugins](https://docs.claude.com/en/docs/claude-code/plugins)
- [Plugin marketplaces](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces)
- [OpenCode agent skills](https://opencode.ai/docs/skills)
