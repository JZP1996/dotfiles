# Repository guide for AI agents

This is a personal **chezmoi** dotfiles repository. The working directory is the chezmoi source directory (`~/.local/share/chezmoi`). Files here are *source* representations that chezmoi deploys to the home directory.

## How chezmoi maps names

- `dot_foo` → `~/.foo`
- `dot_dir/dot_bar` → `~/.dir/.bar`
- `*.tmpl` files are rendered as Go templates before being written.
- `run_once_<after|before>_<name>.sh.tmpl` are scripts chezmoi executes (not deployed); `once` means run once per content hash, `after`/`before` controls timing relative to file application.

## Conventions to follow

- **Never commit secrets.** Do not add files that contain tokens, passwords, or private keys (e.g. `.npmrc` with `_authToken`, `~/.config/gh/hosts.yml`, `~/.ssh/`). If a config mixes secrets and settings, leave it unmanaged.
- **Prefer machine-local for tool-appended files.** `~/.zshrc`, `~/.zshenv`, `~/.zprofile` are intentionally NOT managed because tools append to them. Shared zsh config lives in `dot_zsh/dot_zshrc.common` and is sourced from a local `~/.zshrc`.
- **Guard optional tools.** When a snippet depends on a tool that may be absent (fnm, brew, a plugin path), wrap it in an existence check so a missing tool does not break shell startup.
- **Use templates for platform differences.** Gate macOS/Linux/Windows-specific content with `{{ if eq .chezmoi.os "..." }}` and/or `.chezmoiignore`, rather than committing machine-specific absolute paths.
- **Keep changes minimal and verifiable.** After editing, validate with `chezmoi execute-template` (for `.tmpl`) and `chezmoi diff` before applying.

## Useful commands

```sh
chezmoi diff                              # preview pending changes
chezmoi apply <target>                    # apply a single target
chezmoi execute-template < file.tmpl      # render a template to check output
chezmoi managed | grep <pattern>          # see what is managed
```

## Do not deploy

`README.md`, this `AGENTS.md`, and the root `CLAUDE.md` symlink are repository docs and are excluded from deployment via `.chezmoiignore`. They must not be written to the home directory.
