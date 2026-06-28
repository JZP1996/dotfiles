---
name: python-playbook
description: Personal Python tooling preferences. Use for coding tasks in Python when choosing a package, environment, or dependency manager and the project has not already specified one.
---

# Python Playbook

These preferences apply ONLY when the current project has not already specified a choice. Existing project conventions (lockfiles, config files, documentation, established patterns) always take precedence.

## Package / Environment Manager

- Prefer `uv`. Scale its usage to the project rather than forcing the full toolchain everywhere:
  - Full projects: manage dependencies (`uv add` / `uv remove`), the Python version, and the lockfile with uv.
  - Simple projects: `uv venv` to create an environment; prefer `uv run` to execute without manually activating the venv.
  - Single-file scripts: use PEP 723 inline metadata and `uv run script.py` so uv fetches deps automatically — no project needed.
- Install and pin Python versions with `uv python install`; prefer a **recent (not latest)** stable release.
- Run one-off CLI tools with `uvx` (e.g. `uvx ruff`) instead of installing them globally.
- Commit `uv.lock` to the repository for applications (reproducible installs); libraries may omit it. When a `uv.lock` is present, sync from it with `uv sync`.

## Lint / Format

- Use `ruff` (replaces black + isort + flake8): `ruff format` to format, `ruff check --fix` to lint and autofix.

## Testing

- Use `pytest` over the stdlib `unittest`: plain `assert` statements, fixtures for setup, and `@pytest.mark.parametrize` for table-driven cases. It also runs existing `unittest` test cases.
