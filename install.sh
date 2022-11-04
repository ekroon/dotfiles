#!/bin/sh

set -e # -e: exit on error

bin_dir="$HOME/.local/bin"
if [ ! "$(command -v chezmoi)" ]; then
  if [ "$(command -v curl)" ]; then
    sh -c "$(curl -fsLS https://chezmoi.io/get)" -- -b "$bin_dir"
  elif [ "$(command -v wget)" ]; then
    sh -c "$(wget -qO- https://chezmoi.io/get)" -- -b "$bin_dir"
  else
    echo "To install chezmoi, you must have curl or wget installed." >&2
    exit 1
  fi
fi

# check if PATH contains $bin_dir
if ! echo "$PATH" | grep -q "$bin_dir"; then
  export PATH="$bin_dir:$PATH"
fi

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"
# exec: replace current process with chezmoi init

exec chezmoi init --apply "--source=$script_dir"
