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
  # wallbag-rust and gtk-flash live on the nixos host's Gitea; when it is
  # down a full update stalls ~4.5 min in TCP timeouts. Probe first and
  # update only the public inputs when it is unreachable.
  if timeout 5 bash -c '</dev/tcp/nixos.tail69fe1.ts.net/3000' 2>/dev/null; then
    nix flake update
  else
    echo "nixos.tail69fe1.ts.net:3000 unreachable — updating public inputs only"
    nix flake update nixpkgs home-manager kokoro-fastapi-nix pain
  fi
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

# Preflight: the heavy ROCm Tensile libs (rocblas/hipblas/hipblaslt) build
# for hours; warn when the locked nixpkgs rev has no published binaries on
# cache.nixos.org — fresh unstable tips often never get them (rocblas is
# Hydra's longest-pole job and gets superseded by newer evals). Pin to a
# rev with coverage instead: hydra.nixos.org/job/nixpkgs/unstable/
# rocmPackages.rocblas.x86_64-linux/latest
check_rocm_cache() {
  local target="${HOST:-$DEFAULT_HOST}"
  local enable
  enable=$(nix eval --raw ".#nixosConfigurations.$target.config.rocm-dev.enable" 2>/dev/null) || return 0
  [ "$enable" = "true" ] || return 0
  local missing=()
  local pkg out hash
  for pkg in rocblas hipblas hipblaslt; do
    out=$(nix eval --raw ".#nixosConfigurations.$target.pkgs.rocmPackages.$pkg.outPath" 2>/dev/null) || continue
    hash=$(basename "$out"); hash=${hash%%-*}
    curl -fsS -o /dev/null --max-time 15 "https://cache.nixos.org/$hash.narinfo" 2>/dev/null || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "WARNING: no cached binary for ROCm: ${missing[*]}" >&2
    echo "  hours-long local build ahead (or cache unreachable) — pin nixpkgs to the" >&2
    echo "  rev of Hydra's latest successful rocblas build for coverage" >&2
  else
    echo "ROCm preflight: rocblas/hipblas/hipblaslt all cached"
  fi
}
check_rocm_cache

sudo nixos-rebuild switch --flake ".#${HOST:-$DEFAULT_HOST}" --max-jobs "$JOBS" --cores "$CORES"
