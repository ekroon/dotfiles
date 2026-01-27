# AGENTS

This repository is a chezmoi-managed dotfiles repo. Source files live under `root/`
and are rendered into $HOME by chezmoi.

## Repository layout
- `.chezmoiroot` points to `root/` as the source root.
- Files under `root/` are authoritative; avoid editing deployed files directly in $HOME.
- `dot_*` maps to dotfiles (e.g., `root/dot_zshrc.tmpl` -> `~/.zshrc`).
- `private_*` maps to private files with 0600 permissions.
- `executable_*` would mark files executable if added in the future.
- `run_once_*` and `run_once_after_*` scripts run once during apply.
- `.tmpl` files use Go text/template; keep whitespace trimming (`{{-` / `-}}`) consistent.
- Template data comes from `root/.chezmoi.toml.tmpl` and `root/.chezmoidata.yaml`.
- Neovim config lives in `root/private_dot_config/nvim`.
- Mise config template is `root/private_dot_config/mise/config.toml.tmpl`.

## Build / lint / test
There is no project-wide build or test suite; validation is per-tool and via chezmoi.

### Core lifecycle
- Bootstrap on a new machine: `./install.sh`.
- Apply all changes: `chezmoi apply`.
- Show pending changes: `chezmoi diff`.
- Update repo + apply: `chezmoi update` (used by `script/codespaces-post-start`).
- Render a single file: `chezmoi cat ~/.config/mise/config.toml`.
- View template data: `chezmoi data` (useful when editing templates).

### Single-file checks (closest thing to "single test")
```bash
GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml
GITHUB_REPOSITORY=ekroon/my-repo chezmoi cat ~/.config/mise/config.toml
```

### Lint / format
- Bash scripts: `shellcheck install.sh` and `shellcheck script/codespaces-post-start`.
- Templated shell scripts: render then lint the output (e.g., `chezmoi cat` into a temp file).
- Lua (Neovim):
```bash
stylua --config-path root/private_dot_config/nvim/stylua.toml root/private_dot_config/nvim
```
- Optional shell formatting (if available): `shfmt -w <file>` to match existing 2-space style.

## Common workflows
### Add or update a dotfile
- Edit or add the source file under `root/`.
- Use `dot_` prefixes for dotfiles and `private_` for secrets/credentials.
- For new files, prefer `chezmoi add <target>` to get naming correct.
- Run `chezmoi diff` then `chezmoi apply` to validate changes.

### Update codespaces tool layers
- Edit `root/.chezmoidata.yaml` (patterns + tool lists).
- Run `chezmoi apply` to regenerate `~/.config/mise/config.toml`.
- Validate with the single-file checks above.

### Neovim configuration changes
- Keep `init.lua` minimal; logic lives in `lua/config` and `lua/plugins`.
- Add plugins via new files in `lua/plugins` or by extending existing ones.
- Disable plugins with `enabled = false` (see `neo-tree.lua`).
- Prefer `opts` and `keys` blocks rather than full custom setup.

## Code style guidelines

### General
- Keep changes minimal and localized; follow existing patterns in nearby files.
- Prefer ASCII; only add Unicode if the file already uses it (e.g., starship symbols).
- Use consistent 2-space indentation unless the file clearly uses another style.
- Preserve comment blocks that explain setup or defaults.
- Use blank lines to separate logical sections; avoid trailing whitespace.

### Bash / Zsh
- Use `#!/bin/bash` for bash scripts; include `set -e` when failure should abort.
- Guard optional tools with `command -v` or `if [ -x ... ]` checks.
- Quote variable expansions unless intentional word splitting is needed.
- Use `[ ... ]` in bash scripts; use `[[ ... ]]` in zsh files (`.zshrc`, `.zshenv`).
- Functions are lower_snake_case (see `add_to_path`); env vars are UPPER_SNAKE_CASE.
- Prefer `$HOME` over `~` in scripts for portability.
- For user-facing failures, print a short message and exit non-zero (see `install.sh`).

### Lua (Neovim config)
- Format with Stylua; config is `root/private_dot_config/nvim/stylua.toml` (2 spaces, 120 cols).
- Use `local` for helpers and variables; avoid globals.
- Import modules via `require("...")`; keep imports near first use unless shared.
- Plugin specs return a list table; each entry is `{ "author/plugin", opts = { ... } }`.
- Prefer `opts = function(_, opts)` to merge/extend defaults.
- Use trailing commas in tables to minimize diffs.
- Prefer double quotes for strings to match existing files.
- Types: use EmmyLua annotations (`---@class`, `---@type`, `---@param`) when it helps LSP.
- Error handling: after `vim.fn.system`, check `vim.v.shell_error` and exit on fatal errors.
- Keymaps should include a `desc` and avoid silent behavior unless necessary.
- Avoid editing `root/private_dot_config/nvim/lazy-lock.json` by hand; it is generated.

### YAML / TOML / JSON
- YAML (`root/.chezmoidata.yaml`): 2-space indent, keep list items aligned.
- TOML (mise/starship): `key = value` style; arrays on separate lines for readability.
- JSON (LazyVim): 2-space indent, no trailing commas.

### Chezmoi templates
- Keep templates simple; prefer data-driven branching over file duplication.
- Use `{{-` / `-}}` trimming where already present to control whitespace.
- Prefer `env` and `default` helpers as in `.chezmoi.toml.tmpl`.
- Template variables in this repo include `.codespaces`, `.repo`, `.email`.
- When adding new template data, update `.chezmoi.toml.tmpl` or `.chezmoidata.yaml`.

### Naming & structure
- Neovim plugin files: lowercase with hyphens (`neo-tree.lua`, `mason-workaround.lua`).
- Neovim config files: lowercase (`options.lua`, `keymaps.lua`, `autocmds.lua`).
- Shell scripts: use clear verbs and numbering in `run_once_after_XX_*` files.
- Prefer explicit names over abbreviations for long-lived configs.

### Error handling & safety
- Bash: check preconditions before running installers; exit with clear messages.
- Lua: handle external command failures with `vim.api.nvim_echo` and `os.exit(1)`.
- Avoid destructive commands or removing user data unless the change explicitly requires it.
- Template branches should set all required values; avoid uninitialized vars.

## Tooling notes
- `shellcheck` is installed via mise (`root/private_dot_config/mise/config.toml.tmpl`).
- `stylua` is configured via `root/private_dot_config/nvim/stylua.toml`.
- After editing tool lists, run `chezmoi apply` and then `mise install` if applicable.
- Use `docs/vscode-configuration.md` for Copilot terminal env notes (`IS_AGENT=1`).

## Key files and intent
- `install.sh`: bootstrap + chezmoi init/apply.
- `script/codespaces-post-start`: runs `chezmoi update`.
- `root/run_once_after_00_mise_install.sh.tmpl`: `mise install` hook.
- `root/run_once_after_01_configuration.sh.tmpl`: tmux plugins, codespaces tooling, atuin login.
- `root/private_dot_config/nvim/init.lua`: entrypoint to LazyVim config.
- `root/private_dot_config/nvim/lua/config/lazy.lua`: lazy.nvim bootstrap + error handling.
- `root/private_dot_config/nvim/lua/plugins/core.lua`: colorscheme config.
- `root/private_dot_config/nvim/lua/plugins/sorbet.lua`: Ruby LSP/sorbet setup.
- `root/private_dot_config/nvim/stylua.toml`: Lua formatter settings.
- `docs/codespaces-tool-layers.md`: tool layering workflow and tests.

## Secrets and safety
- Avoid committing real credentials or tokens; use env vars or templated prompts.
- Prefer `private_` prefix for sensitive files to enforce 0600 permissions.
- If a template needs secrets, keep them in `.chezmoi.toml.tmpl` or prompt interactively.
- Double-check `root/private_dot_config/` changes for accidental secrets.

## Documentation style
- Keep docs short and action-oriented.
- Use fenced code blocks with language hints (bash, json, yaml).
- Wrap long commands only when it improves readability.

## Git hygiene
- Avoid reformatting unrelated files.
- Do not edit `.git/` artifacts.

## Cursor / Copilot rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` files found.
