#!/bin/bash
set -e # -e: exit on error

if [ ! "$(command -v curl)" ]; then
  echo "Needs curl to install"
  exit 1
fi

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"


curl https://mise.run | sh
~/.local/bin/mise use --global aqua:atuinsh/atuin chezmoi starship aqua:tailscale/tailscale

eval $(~/.local/bin/mise activate bash)
exec $(~/.local/bin/mise which chezmoi) init --apply "--source=$script_dir"
