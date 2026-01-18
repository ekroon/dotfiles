#!/bin/bash
set -e # -e: exit on error

sudo chsh -s $(which zsh) $(id -un)

if [ ! "$(command -v curl)" ]; then
  echo "Needs curl to install"
  exit 1
fi

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

curl https://mise.run | sh

# Use musl build for chezmoi in Codespaces (x86_64), otherwise use default (for ARM64 compatibility)
if [ "$CODESPACES" = "true" ] && [ "$(uname -m)" = "x86_64" ]; then
  ~/.local/bin/mise use --global aqua:atuinsh/atuin starship fzf "ubi:twpayne/chezmoi[matching=musl]"
else
  ~/.local/bin/mise use --global aqua:atuinsh/atuin starship fzf "ubi:twpayne/chezmoi"
fi

eval "$(~/.local/bin/mise activate bash)"
exec $(~/.local/bin/mise which chezmoi) init --apply "--source=$script_dir"
