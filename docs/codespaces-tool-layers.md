# Codespaces tool layers

This repo installs a baseline toolset via mise and optionally layers extra tools based on the
`GITHUB_REPOSITORY` environment variable. This lets you apply org-wide defaults like `github/*`
and still add specific tools for exact repos such as `github/github`.

## Configuration

Tool layers are defined in `.chezmoidata.yaml` at the repository root:

```yaml
# Default tools installed in all codespaces
codespaces_default_tools:
  - direnv
  - "github:BurntSushi/ripgrep[matching=musl]"
  - "github:sharkdp/fd[matching=musl]"
  - "github:sharkdp/bat[matching=musl]"

# Pattern-based layers (all matching patterns apply)
codespaces_tool_layers:
  - pattern: "github/*"
    tools:
      - ripgrep-all
  - pattern: "github/github"
    tools:
      - "npm:@github/copilot"
  # Example: add tools for your personal org
  # - pattern: "ekroon/*"
  #   tools:
  #     - my-custom-tool
```

## Pattern syntax

| Pattern | Matches |
|---------|---------|
| `org/repo` | Exact match only |
| `org/*` | Any repo in that org |
| `*` | All repos (catch-all) |

All matching patterns have their tools installed (layered, not exclusive).

## How it works

1. chezmoi reads `.chezmoidata.yaml` at `chezmoi apply` time
2. `mise/config.toml.tmpl` iterates over `codespaces_tool_layers`
3. Each pattern is matched against the `GITHUB_REPOSITORY` environment variable
4. All matching patterns have their tools added to the generated mise config
5. `run_once_after_01_configuration.sh` runs `mise install`

## Adding new patterns

Edit `.chezmoidata.yaml` and add a new layer:

```yaml
codespaces_tool_layers:
  # ... existing layers ...
  - pattern: "myorg/*"
    tools:
      - my-tool
      - another-tool
```

Then run `chezmoi apply` to regenerate the mise config.

## Testing

Preview the generated config without applying:

```bash
# Test with github/github repo
GITHUB_REPOSITORY=github/github chezmoi cat ~/.config/mise/config.toml

# Test with your personal org
GITHUB_REPOSITORY=ekroon/my-repo chezmoi cat ~/.config/mise/config.toml
```

## Notes

- Prefer `github:` tools with `matching=musl` for Codespaces to avoid glibc issues
- Tools in `codespaces_default_tools` are always installed in codespaces
- Pattern matching uses `hasPrefix` for `org/*` patterns and `eq` for exact matches
