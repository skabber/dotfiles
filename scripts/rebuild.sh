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

cd "$(dirname "$0")/.."

JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -lt 1 ] && JOBS=1

if [ "$UPGRADE" = true ]; then
  nix flake update
fi

sudo nixos-rebuild switch --flake ".#${HOST:-$(hostname)}" --max-jobs "$JOBS"
