#!/usr/bin/env bash
set -euo pipefail

cd ~/dotfiles
nix flake update && sudo nixos-rebuild switch --flake ".#${1:-$(hostname)}"
