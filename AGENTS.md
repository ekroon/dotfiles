# AGENTS

## Repository overview

This is a chezmoi-managed dotfiles repository. `.chezmoiroot` points at `root/`, so files under `root/` are the source of truth and render into `$HOME`; do not edit deployed dotfiles directly.

Template data is split between `root/.chezmoi.toml.tmpl`, which derives runtime values such as `.codespaces`, `.repo`, `.dotcom`, and `.email`, and `root/.chezmoidata.yaml`, which owns Homebrew packages, mise tool layers, and agent skill metadata. Most behavior changes should be data-driven there rather than duplicated across templates.

Main subsystems:

- `root/private_dot_config/mise/config.toml.tmpl` renders filtered mise tools from `root/.chezmoidata.yaml`.
- `root/private_dot_config/homebrew/Brewfile.tmpl` renders the managed macOS Brewfile; `root/run_after_00_homebrew_bundle.sh.tmpl` enforces it during local Darwin applies.
- `root/private_dot_config/nvim` is a LazyVim config: `init.lua` only loads `config.lazy`, general config lives in `lua/config`, and plugin overrides/specs live in `lua/plugins`.
- `run_once_after_*` and `run_after_*` templates handle one-time and recurring apply hooks such as `mise install`, tmux plugin setup, Codespaces setup, atuin login, Homebrew, and LaunchAgents.

## Build, test, and lint

There is no project-wide build or test suite. Validate the specific rendered output or tool surface touched by the change.

Core chezmoi checks:

```bash
chezmoi diff
chezmoi apply
chezmoi data
```

Single-file render checks:

```bash
chezmoi cat ~/.config/mise/config.toml
CODESPACES=true GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml
MISE_DISTRO_CODENAME=focal CODESPACES=true GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml
DEVCONTAINER=true GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml
chezmoi cat ~/.config/homebrew/Brewfile
```

Lint/format commands:

```bash
shellcheck install.sh script/codespaces-post-start
stylua --config-path root/private_dot_config/nvim/stylua.toml root/private_dot_config/nvim
```

For templated shell scripts, render the template before running ShellCheck, for example:

```bash
chezmoi execute-template < root/run_after_00_homebrew_bundle.sh.tmpl > /tmp/homebrew-bundle.sh
shellcheck /tmp/homebrew-bundle.sh
```

For Homebrew bundle changes on local macOS:

```bash
chezmoi cat ~/.config/homebrew/Brewfile
brew bundle check --file "$HOME/.config/homebrew/Brewfile" --no-upgrade
```

## Codebase conventions

- Chezmoi naming matters: `dot_*` maps to dotfiles, `private_*` enforces private permissions, `executable_*` marks executables, and `run_once_*` / `run_once_after_*` scripts run once during apply.
- For new managed files, prefer `chezmoi add <target>` to get source names and permissions right; otherwise edit/add the corresponding source file under `root/`.
- Go templates use whitespace trimming (`{{-` / `-}}`) intentionally; preserve nearby trimming style when editing `.tmpl` files.
- Mise tool filters in `root/.chezmoidata.yaml` are OR'd within a filter key and AND'd across keys. Environment detection is Codespaces first, then `DEVCONTAINER=true`, then local. Repository filters use `GITHUB_REPOSITORY`; distro filters use `MISE_DISTRO_CODENAME` or `/etc/os-release` on Linux.
- Use `variants` in `mise_tools` when one logical tool needs different assets, bins, or filters per OS/environment. Prefer musl-matching `github:` tools for Codespaces/devcontainers when glibc compatibility is an issue.
- Homebrew packages are declared in `root/.chezmoidata.yaml`; avoid editing `root/private_dot_config/homebrew/Brewfile.tmpl` just to add or remove packages.
- Neovim plugin files are lowercase with hyphens and return plugin spec lists. Prefer `opts` and `keys` blocks, disable plugins with `enabled = false`, and avoid hand-editing `root/private_dot_config/nvim/lazy-lock.json`.
- Lua is formatted by Stylua with 2 spaces and 120 columns; prefer double-quoted strings and trailing commas in tables.
- Bash scripts use `#!/bin/bash`, `set -e` where failure should abort, quoted variable expansions, and explicit precondition failures. Use `[ ... ]` in bash scripts and `[[ ... ]]` in zsh files.
- Avoid committing secrets or literal machine-specific home paths. Use templates, `$HOME`, environment variables, prompts, or `private_*` files as appropriate.
