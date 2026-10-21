#!/usr/bin/env bash
# First-time activation for a host/home in this flake.
#
# Usage: ./scripts/bootstrap.sh <name>
#   <name> is an attribute under nixosConfigurations / darwinConfigurations /
#   homeConfigurations, e.g. Enten (NixOS), Kumeyuri (nix-darwin), or
#   aor@philo (standalone home-manager profile).
#
# On nixos/darwin hosts home-manager runs as a system module, so the system
# switch activates the users' homes too; homeConfigurations only holds
# standalone profiles for machines without a den host.
#
# macOS prerequisites: Nix must already be installed; Homebrew is optional (skipped with a
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

# Inject the same nix.conf settings modules/aspects/trait/nix/conf.nix
# would apply, since a fresh machine hasn't switched once yet to have them.
export NIX_CONFIG="experimental-features = nix-command flakes
substituters = https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://nix-community.cachix.org https://cache.nixos.org/
extra-trusted-public-keys = cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

has_attr() {
  nix eval --no-write-lock-file --json "${repo_root}#${1}" --apply builtins.attrNames 2>/dev/null \
    | grep -qF "\"${name}\""
}

if has_attr nixosConfigurations; then
  echo "==> nixos-rebuild switch (${name})"
  sudo --preserve-env=NIX_CONFIG nixos-rebuild switch --flake "$flake"
elif has_attr darwinConfigurations; then
  echo "==> nix-darwin switch (${name})"
  sudo --preserve-env=NIX_CONFIG nix run nix-darwin -- switch --flake "$flake"
elif has_attr homeConfigurations; then
  echo "==> home-manager switch (${name})"
  nix run home-manager -- switch --flake "$flake"
else
  echo "error: '${name}' not found in nixosConfigurations / darwinConfigurations / homeConfigurations" >&2
  exit 1
fi
