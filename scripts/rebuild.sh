#!/usr/bin/env bash
set -euo pipefail

UPGRADE=false
HOST=""

for arg in "$@"; do
  case "$arg" in
    --upgrade) UPGRADE=true ;;
    *) HOST="$arg" ;;
  esac
done

cd ~/dotfiles

if [ "$UPGRADE" = true ]; then
  nix flake update
fi

sudo nixos-rebuild switch --flake ".#${HOST:-$(hostname)}"
