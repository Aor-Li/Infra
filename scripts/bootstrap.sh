#!/usr/bin/env bash
# First-time activation for a host/home in this flake.
#
# Usage: ./scripts/bootstrap.sh <name>
#   <name> is an attribute under nixosConfigurations / darwinConfigurations /
#   homeConfigurations, e.g. Enten (NixOS), Kumeyuri (nix-darwin), or
#   aor@philo (standalone home-manager profile).
#
# For a nixos/darwin host this also switches any homeConfigurations named
# "<user>@<name>", since home-manager here always runs standalone rather
# than as a nixos/darwin module.
#
# macOS prerequisites: Lix must already be installed
# (https://install.lix.systems); Homebrew is optional (skipped with a
# warning if missing). A working proxy is recommended for fetching flake
# inputs from GitHub.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <name>" >&2
  exit 1
fi

name="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake="${repo_root}#${name}"

# Inject the same nix.conf settings modules/aspects/trait/01-nix/conf.nix
# would apply, since a fresh machine hasn't switched once yet to have them.
export NIX_CONFIG="experimental-features = nix-command flakes
substituters = https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://nix-community.cachix.org https://cache.nixos.org/
extra-trusted-public-keys = cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

has_attr() {
  nix eval --no-write-lock-file --json "${repo_root}#${1}" --apply builtins.attrNames 2>/dev/null \
    | grep -qF "\"${name}\""
}

# Switch every homeConfigurations entry named "<user>@<name>" for this host.
switch_matching_homes() {
  local homes
  homes="$(
    nix eval --no-write-lock-file --json "${repo_root}#homeConfigurations" --apply builtins.attrNames 2>/dev/null \
      | jq -r --arg suffix "@${name}" '.[] | select(endswith($suffix))'
  )"
  [ -z "$homes" ] && return 0
  local home_name
  while IFS= read -r home_name; do
    echo "==> home-manager switch (${home_name})"
    nix run home-manager -- switch --flake "${repo_root}#${home_name}"
  done <<< "$homes"
}

if has_attr nixosConfigurations; then
  echo "==> nixos-rebuild switch (${name})"
  sudo --preserve-env=NIX_CONFIG nixos-rebuild switch --flake "$flake"
  switch_matching_homes
elif has_attr darwinConfigurations; then
  echo "==> nix-darwin switch (${name})"
  sudo --preserve-env=NIX_CONFIG nix run nix-darwin -- switch --flake "$flake"
  switch_matching_homes
elif has_attr homeConfigurations; then
  echo "==> home-manager switch (${name})"
  nix run home-manager -- switch --flake "$flake"
else
  echo "error: '${name}' not found in nixosConfigurations / darwinConfigurations / homeConfigurations" >&2
  exit 1
fi
