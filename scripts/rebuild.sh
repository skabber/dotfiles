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

# Per-build core cap. cores=0 (the Nix default) lets each build use ALL cores,
# so a single ROCm kernel build (rocblas/miopen) OOMs regardless of --max-jobs.
# Must be passed on the CLI too: the running system's nix.conf still has
# cores=0 until this rebuild succeeds, so nix.settings alone can't save it.
CORES=4

# Cap concurrent builds. With CORES above, total parallel compile jobs ~=
# JOBS*CORES (4*4=16) keeps peak RAM bounded on memory-heavy ROCm builds.
JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -gt 4 ] && JOBS=4
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

# Map system hostname -> flake config name. They differ for the Framework
# laptops (e.g. flake framework-13 lives on host nixos-framework-13).
case "$(hostname)" in
  nixos-framework-13) DEFAULT_HOST="framework-13" ;;
  nixos-framework)    DEFAULT_HOST="framework-16" ;;
  *)                  DEFAULT_HOST="$(hostname)" ;;
esac

sudo nixos-rebuild switch --flake ".#${HOST:-$DEFAULT_HOST}" --max-jobs "$JOBS" --cores "$CORES"
