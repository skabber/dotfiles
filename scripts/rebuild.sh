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

# Cap at 8 to avoid OOM on high-core-count machines with large services loaded
JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -gt 8 ] && JOBS=8
[ "$JOBS" -lt 1 ] && JOBS=1

if [ "$UPGRADE" = true ]; then
  nix flake update
fi

# Stop memory-hungry services before building so Nix has headroom
STOPPED_SERVICES=()
for svc in ollama; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo "Stopping $svc before rebuild..."
    sudo systemctl stop "$svc"
    STOPPED_SERVICES+=("$svc")
  fi
done

restore_services() {
  for svc in "${STOPPED_SERVICES[@]:-}"; do
    [ -n "$svc" ] || continue
    echo "Restarting $svc..."
    sudo systemctl start "$svc"
  done
}
trap restore_services EXIT

sudo nixos-rebuild switch --flake ".#${HOST:-$(hostname)}" --max-jobs "$JOBS"
