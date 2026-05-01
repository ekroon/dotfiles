# Mise tool filters

This repo defines mise tools in one `mise_tools` list in `.chezmoidata.yaml`.
Each entry is either a plain string, installed everywhere, or an object with
optional filters.

## Configuration

```yaml
mise_tools:
  - fzf
  - name: "github:BurntSushi/ripgrep[matching=musl]"
    filters:
      environment: [codespace, devcontainer]
  - name: ripgrep-all
    filters:
      environment: [codespace]
      repo: ["github/*"]
```

Object fields:

- `name`: mise tool name
- `alias`: optional `[tool_alias]` value
- `version`: optional version, defaults to `latest`
- `asset_pattern` and `bin_path`: optional structured mise tool settings
- `filters`: optional match rules

## Filter syntax

Filters are OR'd within a list and AND'd across filter keys. Missing filters
match everywhere.

| Filter | Values |
|--------|--------|
| `os` | Go OS values such as `darwin` or `linux` |
| `environment` | `local`, `codespace`, or `devcontainer` |
| `repo` | Exact `org/repo`, org prefix `org/*`, or catch-all `*` |

Repository filters match `GITHUB_REPOSITORY`. Environment is derived as:
Codespaces first, then `DEVCONTAINER=true`, then local.

## Testing

Preview the generated config without applying:

```bash
# Local/default render
chezmoi cat ~/.config/mise/config.toml

# Codespace render for a GitHub repo
CODESPACES=true GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml

# Devcontainer render
DEVCONTAINER=true GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml
```

## Notes

- Prefer `github:` tools with `matching=musl` for Codespaces and devcontainers
  to avoid glibc issues.
- `repo: ["github/*"]` preserves the previous org-wide Codespaces layer behavior.
