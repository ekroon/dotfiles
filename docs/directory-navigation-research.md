# Research: Directory Navigation & Project Management for Your macOS Setup

## Executive Summary

You have a rich but organically-grown `~/develop/` directory with 10 top-level categories (ekroon, github, scripts, tries, tabctl, mcp, golang, games, codespaces), your own `ekroon/try` tool for quick date-prefixed scratch projects, and no directory-jumping tool like zoxide installed. After analyzing your current setup (WezTerm + tmux + Oh-My-Zsh + mise + fzf + Starship), your existing `try` tool, and the broader landscape, I recommend a **layered approach** combining multiple complementary tools rather than one monolithic solution. The three strongest options are: **(1) Extend `ekroon/try`** with promote/bookmark/codespaces features, **(2) Add `zoxide` + `fzf`** for frecency-based jumping across all directories, and **(3) Optionally adopt `ghq`** for organizing github repository clones. For tmux-based project switching, **`sesh`** is an excellent fit since it integrates zoxide, tmux sessions, and fzf into a unified workflow.

---

## Your Current State

### Directory Layout (`~/develop/`)

```
~/develop/
├── codespaces/          # Empty — intended for codespace-related local work
├── ekroon/              # 48 personal repos (try, tabctl, adventofcode, etc.)
├── games/               # DragonRuby
├── github/              # 8 work-related repos (copilot-scratch, graphql-platform, etc.)
├── golang/              # Go workspace (GOPATH-style)
├── mcp/                 # MCP experiments
├── scripts/             # 14 utility/script projects
├── tabctl/              # Active tabctl development
└── tries/               # 16 date-prefixed try projects (managed by ekroon/try)
```

### Current Tools

| Tool | Purpose | Config Location |
|------|---------|-----------------|
| **ekroon/try** | Quick project creation/selection with TUI | `dot_zshrc.tmpl:42-44`[^1] |
| **fzf** | Fuzzy finder (installed via mise) | `.chezmoidata.yaml`[^2] |
| **tmux** | Terminal multiplexer (prefix: Ctrl+Space) | `private_dot_config/tmux/tmux.conf`[^3] |
| **WezTerm** | Terminal emulator with workspaces | `dot_wezterm.lua`[^4] |
| **direnv** | Per-directory env vars | `dot_zshrc.tmpl:35-38`[^1] |
| **Starship** | Minimal prompt (directory-aware) | `private_dot_config/starship.toml`[^5] |
| **Obsidian** | Notes (iCloud-synced MainVault) | External to chezmoi |

### What's Missing

- **No frecency-based directory jumping** (no zoxide/autojump/z installed)
- **No bookmark system** for pinning important directories
- **No promote workflow** (moving a try project → permanent location)
- **No codespaces scratch directory** strategy (the `codespaces/` dir is empty)
- **No tmux session management** tied to projects (no sesh/tmuxinator)
- **No repo organization convention** (github repos scattered across `ekroon/`, `github/`, `scripts/`)

---

## Recommended Approach: Layered Tooling

Rather than replacing `try` with a single monolithic tool, layer complementary tools that each solve one problem well:

```
┌──────────────────────────────────────────────────────────┐
│                    Your Workflow                          │
├──────────────────────────────────────────────────────────┤
│  Layer 4: sesh          (tmux session ↔ project binding) │
│  Layer 3: ekroon/try    (quick project creation/promote) │
│  Layer 2: ghq           (repo clone organization)        │
│  Layer 1: zoxide + fzf  (universal directory jumping)    │
│  Layer 0: ~/develop/    (directory convention)            │
└──────────────────────────────────────────────────────────┘
```

---

## Layer 1: zoxide + fzf (Universal Directory Jumping)

### What It Solves
- Instantly jump to any recently/frequently used directory
- Interactive fuzzy search across all your directories
- Works across ALL of `~/develop/`, not just `tries/`

### How It Works
zoxide tracks every `cd` you do and builds a frecency database (frequency × recency). You type `z proj` and it jumps to the best-matching directory you've visited. With `zi`, it opens an fzf-powered interactive picker.[^6]

### Installation (via mise)

Add to your mise config or install directly:

```bash
mise use -g zoxide
```

Add to `dot_zshrc.tmpl`:
```bash
eval "$(zoxide init zsh)"
```

### Key Commands

| Command | Description |
|---------|-------------|
| `z foo` | Jump to best match for "foo" |
| `z foo bar` | Jump to best match containing both "foo" and "bar" |
| `zi` | Interactive picker with fzf (shows all tracked dirs) |
| `zoxide query -ls` | List all tracked directories with scores |
| `zoxide add ~/develop/ekroon/try` | Manually seed a directory |

### Why This Fits You
- **Zero config**: learns from your usage automatically
- **Integrates with fzf**: which you already have installed
- **Solves "most recent" switching**: your primary stated need
- **Works everywhere**: not limited to git repos or tries
- **Codespaces compatible**: works in any shell environment

### Bookmarking with zoxide
While zoxide doesn't have explicit bookmarks, you can simulate them:
```bash
# Add a bookmark alias in .zshrc
bookmark() { zoxide add "$1" && zoxide query --score "$1"; }
# Boost a directory's score by visiting it repeatedly
zoxide add ~/develop/github/graphql-platform
zoxide add ~/develop/github/graphql-platform
zoxide add ~/develop/github/graphql-platform
```

For true bookmarks, a simple shell function is more natural (see Layer 3 extensions).

---

## Layer 2: ghq (Repository Organization) — Optional but Recommended

### What It Solves
- Standardizes where git repos are cloned
- Provides `ghq list` for finding any repo instantly
- Includes `ghq migrate` for moving existing repos into the structure
- Has a `ghq create` for new repos

### How It Works
ghq organizes repos under a root directory using the URL structure:[^7]

```
~/develop/ghq/                        # ghq.root
├── github.com/
│   ├── ekroon/
│   │   ├── try/
│   │   ├── tabctl/
│   │   └── chezmoi/
│   └── github/
│       ├── copilot-scratch/
│       └── graphql-platform/
└── ...
```

### Installation

```bash
mise use -g ghq
# or
brew install ghq
```

Configure the root to coexist with your current layout:
```bash
git config --global ghq.root ~/develop/ghq
```

### Migration Strategy

ghq has a built-in `migrate` command that moves existing repos into the ghq structure:[^7]

```bash
# Migrate existing repos one at a time
ghq migrate ~/develop/ekroon/try
ghq migrate ~/develop/github/graphql-platform
# Verify
ghq list
```

### Integration with fzf

```bash
# Add to .zshrc — jump to any ghq-managed repo
ghq-cd() {
  local dir
  dir=$(ghq list -p | fzf --preview 'ls -la {}' --height 40%)
  if [[ -n "$dir" ]]; then
    cd "$dir"
  fi
}
```

### Why This Fits You
- **Cleans up your directory mess**: your stated concern about `~/develop/` being messy
- **Works with `gh repo clone`**: ghq can intercept clone operations
- **Codespaces-compatible naming**: repos are organized by `host/owner/repo`
- **Coexists with try**: tries stay in `~/develop/tries/`, repos go in `~/develop/ghq/`

### Trade-offs
- **Migration effort**: you'd need to move ~70 repos (can be scripted)
- **Muscle memory**: paths change from `~/develop/ekroon/foo` to `~/develop/ghq/github.com/ekroon/foo`
- **Not required**: zoxide alone may be sufficient if you're happy with your current layout

---

## Layer 3: Extending ekroon/try (Promote, Bookmark, Codespaces)

Your `try` tool is a solid Bubbletea-based Go TUI that currently supports:[^8]

- Interactive project selection with substring search
- New project creation with date prefixes (`YYYY-MM-DD-name`)
- Sorted by modification time (most recent first)
- Shell integration via `try init`

### Recommended Extensions

#### 1. Promote Command

Move a try project to a permanent location:

```go
// New subcommand: try promote
// Moves ~/develop/tries/2026-02-28-normalize-url-rs → ~/develop/ekroon/normalize-url-rs
```

Implementation sketch:
```bash
# Shell function alternative (add to .zshrc while Go version is WIP)
try-promote() {
    local project=$(ls ~/develop/tries | fzf --prompt="Promote which project? ")
    if [[ -z "$project" ]]; then return 1; fi
    
    # Strip date prefix
    local name=$(echo "$project" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
    local dest="${1:-$HOME/develop/ekroon}/$name"
    
    echo "Moving ~/develop/tries/$project → $dest"
    read -q "REPLY?Proceed? (y/n) " || return 1
    echo
    mv ~/develop/tries/"$project" "$dest"
    echo "Promoted to $dest"
}
```

#### 2. Bookmark System

Add a bookmarks file that `try` reads alongside the tries directory:

```bash
# ~/.config/try/bookmarks (simple text file)
~/develop/github/graphql-platform
~/develop/ekroon/tabctl
~/develop/scripts/tabctl-rust-migration
```

The TUI could show bookmarks in a separate section above the tries list.

#### 3. Codespaces Scratch Integration

For notes/scratch that persist beyond codespace lifetime, two approaches:

**Option A: Obsidian (you mentioned this)**
- You already have an iCloud-synced vault
- Create a `Codespaces/` folder in your vault for per-repo notes
- Use the existing Obsidian search for retrieval

**Option B: Local scratch directory with git sync**
```bash
# ~/develop/codespaces-notes/ — git repo synced to a private GitHub repo
mkdir -p ~/develop/codespaces-notes
cd ~/develop/codespaces-notes && git init
# Structure: one dir per repo
# ~/develop/codespaces-notes/github-github/
# ~/develop/codespaces-notes/graphql-platform/
```

**Recommendation**: Stick with Obsidian. You already use it, it syncs via iCloud, and it has better search/linking than flat files. The `codespaces/` dir in `~/develop/` can be repurposed or removed.

---

## Layer 4: sesh (tmux Session Manager) — Strong Recommendation

### What It Solves
- Binds tmux sessions to project directories
- Unified fuzzy picker for tmux sessions + zoxide directories
- Automatic session creation when navigating to a directory
- Named sessions with custom startup commands

### How It Works
sesh integrates tmux, zoxide, and fzf into a single workflow. When you press a keybinding, it shows all your tmux sessions AND zoxide-tracked directories in one fzf picker. Selecting a directory either attaches to an existing session or creates one.[^9]

### Installation

```bash
brew install sesh
# Requires: tmux (✓), zoxide (Layer 1), fzf (✓)
```

### Configuration (`~/.config/sesh/sesh.toml`)

```toml
# Cache zoxide results for speed
cache = true

[default_session]
startup_command = "nvim"
preview_command = "eza --all --git --icons --color=always {}"

# Pin important projects as named sessions
[[session]]
name = "tabctl 📊"
path = "~/develop/tabctl"
startup_command = "nvim"

[[session]]
name = "dotfiles ⚙️"
path = "~/.local/share/chezmoi"
startup_command = "nvim"

[[session]]
name = "graphql 🔷"
path = "~/develop/github/graphql-platform"

# Wildcard: all tries get the same treatment
[[wildcard]]
pattern = "~/develop/tries/*"
startup_command = "nvim"

[[wildcard]]
pattern = "~/develop/ekroon/*"
startup_command = "nvim"
```

### tmux Keybinding

Add to your tmux.conf:
```bash
# Ctrl+Space then T to open sesh picker
bind-key "T" display-popup -E -w 40% "sesh connect \"$(
  sesh list -i | fzf --no-sort --ansi --border-label ' sesh ' \
    --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
    --bind 'tab:down,btab:up' \
    --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list -i)' \
    --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -it)' \
    --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -ic)' \
    --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -iz)' \
    --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d . ~)' \
    --bind 'ctrl-d:execute(tmux kill-session -t {2..})+reload(sesh list)'
)\""
```

### Why This Is a Strong Fit
- **You already use tmux**: prefix is Ctrl+Space, TPM plugins installed[^3]
- **Bridges all your needs**: recent projects (zoxide), bookmarks (session configs), quick projects (wildcards for tries)
- **Session per project**: each tmux session = one project context, easy switching
- **WezTerm compatible**: sesh runs inside tmux, WezTerm is the outer layer
- **1.8K stars, actively maintained**: Go-based, same ecosystem as your tools[^9]

---

## Alternative Tools Considered but Not Recommended

| Tool | Why Not |
|------|---------|
| **autojump / z** | Older, slower alternatives to zoxide — zoxide is strictly better[^6] |
| **nnn / yazi** | Terminal file managers — overkill for directory jumping; better for file ops |
| **broot** | Tree-based navigation — good but overlaps with fzf+zoxide |
| **ProjectMan** | npm-based bookmark manager — too simple, Node dependency unnecessary |
| **Banco** | Project-level notes/tasks/bookmarks — interesting but Go-based and last updated 2020[^10] |
| **MPM** | Project manager — abandoned (GitHub 404) |
| **tmuxinator** | YAML-based tmux sessions — sesh is more modern and dynamic[^9] |
| **WezTerm workspaces** | You already use these but they're separate from tmux; sesh is better for project switching |

---

## Implementation Plan

### Phase 1: Quick Wins (30 minutes)

1. **Install zoxide** via mise and add shell init to `dot_zshrc.tmpl`
2. **Seed zoxide** with your key directories:
   ```bash
   for dir in ~/develop/*/; do zoxide add "$dir"; done
   for dir in ~/develop/ekroon/*/; do zoxide add "$dir"; done
   for dir in ~/develop/github/*/; do zoxide add "$dir"; done
   ```
3. **Test**: `z tabctl`, `z graphql`, `zi` (interactive)

### Phase 2: Session Management (1 hour)

1. **Install sesh** via Homebrew
2. **Create `~/.config/sesh/sesh.toml`** with your key sessions and wildcards
3. **Add tmux keybinding** for the sesh picker
4. **Test**: `Ctrl+Space T` → pick a project → get a tmux session with nvim

### Phase 3: Try Extensions (when you have time)

1. **Add `try-promote` shell function** to `dot_zshrc.tmpl`
2. **Consider adding ghq** if you want to reorganize repos
3. **Extend `ekroon/try`** in Go with promote and bookmark subcommands

### Phase 4: Codespaces Notes (optional)

1. **Use Obsidian** — create a `Codespaces/` folder in your vault
2. **Remove or repurpose** the empty `~/develop/codespaces/` directory
3. **If you need terminal-accessible notes**: symlink an Obsidian subfolder:
   ```bash
   ln -s ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/MainVault/Codespaces ~/develop/codespace-notes
   ```

---

## Chezmoi Integration Notes

All tool additions should be managed via your chezmoi dotfiles:

| Change | File |
|--------|------|
| zoxide init | `root/dot_zshrc.tmpl` (add `eval "$(zoxide init zsh)"`) |
| zoxide install | `root/private_dot_config/mise/config.toml.tmpl` (add to `[tools]`) |
| sesh install | Homebrew or mise |
| sesh config | `root/private_dot_config/sesh/sesh.toml` (new file) |
| tmux keybinding | `root/private_dot_config/tmux/tmux.conf` |
| try-promote | `root/dot_zshrc.tmpl` (shell function) |
| ghq config | `root/dot_gitconfig.tmpl` (add `[ghq]` section) |

---

## Confidence Assessment

| Claim | Confidence | Notes |
|-------|------------|-------|
| zoxide is the best frecency jumper | **High** | Well-established, 25K+ stars, Rust-based, fastest in class |
| sesh fits your tmux workflow | **High** | Direct integration with tmux + zoxide, actively maintained |
| ghq would help organize repos | **Medium** | Good tool but migration cost is real; zoxide may be sufficient |
| try-promote is useful | **High** | Clear gap in current try functionality based on your stated needs |
| Obsidian is better than codespaces/ dir | **High** | You already use it, iCloud sync handles persistence |
| Banco/MPM are viable alternatives | **Low** | Both appear abandoned or low-activity |

---

## Footnotes

[^1]: `root/dot_zshrc.tmpl:41-44` — try initialization and TRY_PROJECTS_DIR config
[^2]: `root/.chezmoidata.yaml` — mise tool lists including fzf
[^3]: `root/private_dot_config/tmux/tmux.conf` — tmux config with Ctrl+Space prefix, TPM
[^4]: `root/dot_wezterm.lua` — WezTerm config with workspaces and multiplexing
[^5]: `root/private_dot_config/starship.toml` — Starship prompt config
[^6]: [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) — smarter cd command, 25K+ stars
[^7]: [x-motemen/ghq](https://github.com/x-motemen/ghq) — remote repository management, `README.adoc` documents `migrate` command
[^8]: [ekroon/try](https://github.com/ekroon/try) — `main.go` full source, Bubbletea TUI with date-prefixed project creation
[^9]: [joshmedeski/sesh](https://github.com/joshmedeski/sesh) — 1.8K stars, tmux+zoxide session manager, `README.md` documents wildcard configs and session management
[^10]: [claudiodangelis/banco](https://github.com/claudiodangelis/banco) — filesystem-based project management with notes/tasks/bookmarks modules
