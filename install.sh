#!/bin/bash
set -e # -e: exit on error

if [ ! "$(command -v curl)" ]; then
  echo "Needs curl to install"
  exit 1
fi

sh <(curl -L https://nixos.org/nix/install) --no-daemon --no-modify-profile

source /home/vscode/.nix-profile/etc/profile.d/nix.sh

nix shell 'nixpkgs#acl' --command bash -c 'sudo env PATH=$PATH setfacl -k /tmp'

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

ln -s "${script_dir}/nix" /home/vscode/.config/home-manager

nix run '/home/vscode/.config/home-manager/#homeConfigurations."vscode".activationPackage'

exec chezmoi init --apply "--source=$script_dir"
