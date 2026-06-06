# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Bootstrap

Requires access to this repository (it lives under a work GitHub account, so authenticate with the matching account first). Swap the URL if you fork it.

On a fresh machine without chezmoi:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply some-repository
```

Or, if chezmoi is already installed:

```sh
chezmoi init --apply some-repository
```

On first apply, the `run_once_after_initialize` script installs Oh My Zsh and zsh plugins, then prepends a `source` line to `~/.zshrc` (see below).

## Layout

### Deployed to the home directory

- **`dot_agents/`** → `~/.agents/`
  - `skills/symlink_*` → symlinks under `~/.agents/skills/` pointing at the skills bundled in `claude-plugins/`.
- **`dot_claude/`** → `~/.claude/`
  - `CLAUDE.md` → `~/.claude/CLAUDE.md` — Claude Code global instructions.
- **`dot_config/`** → `~/.config/`
  - `ghostty/config` → `~/.config/ghostty/config` — Ghostty terminal config.
- **`dot_zsh/`** → `~/.zsh/`
  - `dot_zshrc.common` → `~/.zsh/.zshrc.common` — cross-machine zsh config (Oh My Zsh, PATH, completion, plugins).
  - `functions/common.zsh` → `~/.zsh/functions/common.zsh` — shared shell functions.

### Run-Only (NOT Deployed)

- **`run_once_after_initialize.sh.tmpl`** — first-run bootstrap (installs Oh My Zsh + zsh plugins, injects the `source` line into `~/.zshrc`).

### Repository-Only (NOT Deployed)

- **`claude-plugins/`** — a personal Claude Code plugin marketplace (19 plugins). Run `claude-plugins/install.sh` to register the marketplace and install every plugin into Claude Code. Excluded from deployment via `.chezmoiignore`.
- **`README.md`**, **`CLAUDE.md`** — repository docs.

## Configure layering

`~/.zshrc` is **not** managed by chezmoi. It stays machine-local because tools (Docker Desktop, fnm, etc.) append to it. Its first line sources the shared, chezmoi-managed config:

```zsh
[[ -f ~/.zsh/.zshrc.common ]] && source ~/.zsh/.zshrc.common
```

So each machine keeps its own `~/.zshrc` for machine-specific bits while the common configuration is shared via `~/.zsh/.zshrc.common`.

## Intentionally NOT Managed

These are left to their owning tools / kept machine-local:

- `~/.zshrc`, `~/.zshenv`, `~/.zprofile` — appended to by Docker, cargo, Homebrew, etc.
- `~/.npmrc`, `~/.config/gh/`, `~/.ssh/` — contain credentials/tokens.
- Tool-managed dirs (`~/.oh-my-zsh`, `~/.cargo`, `~/.config/opencode`, …).

## Platform Handling

`.chezmoiignore` skips zsh files and `~/.config/ghostty` on Windows, since those are macOS/Linux only.

## Common Commands

```sh
chezmoi edit <target>     # edit a managed file's source
chezmoi diff              # preview pending changes
chezmoi apply             # apply changes to the home directory
chezmoi cd                # open a shell in the source directory
chezmoi update            # pull latest from git and apply
```
