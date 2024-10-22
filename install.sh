#!/bin/bash
set -e # -e: exit on error

if [ ! "$(command -v curl)" ]; then
  echo "Needs curl to install"
  exit 1
fi

sh <(curl -L https://nixos.org/nix/install) --no-daemon --no-modify-profile

source /home/vscode/.nix-profile/etc/profile.d/nix.sh

mkdir -p $HOME/.config/nix 2>/dev/null
echo "experimental-features = nix-command flakes fetch-closure" > $HOME/.config/nix/nix.conf

# nix shell 'nixpkgs#acl.bin' --command bash -c 'sudo env PATH=$PATH setfacl -k /tmp'

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# install devbox
export FORCE=1
curl -fsSL https://get.jetify.com/devbox | bash
unset FORCE

echo 'eval "$(devbox global shellenv)"' >> $HOME/.bashrc
. $HOME/.bashrc

devbox global add acl atuin chezmoi starship tailscale
eval "$(devbox global shellenv --preserve-path-stack)" && hash -r

exec chezmoi init --apply "--source=$script_dir"