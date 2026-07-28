#!/usr/bin/env bash
set -euo pipefail

UPGRADE=false
HOST=""

for arg in "$@"; do
  case "$arg" in
    --upgrade) UPGRADE=true ;;
    --*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *) HOST="$arg" ;;
  esac
done

cd "$(dirname "$0")/.."

if [ -n "$HOST" ] && [ ! -d "hosts/$HOST" ]; then
  echo "error: unknown host '$HOST' (expected one of: $(ls hosts))" >&2
  exit 1
fi

# Per-build core cap. cores=0 (the Nix default) lets each build use ALL cores,
# so a single ROCm kernel build (rocblas/miopen) OOMs regardless of --max-jobs.
# Passed on the CLI because the running system's nix.conf cap only takes
# effect after a successful rebuild. Override with CORES=/JOBS= env vars.
CORES=${CORES:-8}

# Cap concurrent builds. Total parallel compile jobs ~= JOBS*CORES; on the
# 64-core ripper this gives 4*8=32 (~half the machine), keeping peak RAM
# bounded while leaving big ROCm builds 8 cores to work with.
JOBS=${JOBS:-$(( $(nproc) / CORES / 2 ))}
[ "$JOBS" -gt 4 ] && JOBS=4
[ "$JOBS" -lt 2 ] && JOBS=2

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
