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

LOCK_BACKUP=""

if [ "$UPGRADE" = true ]; then
  # Snapshot the lock so the ROCm preflight below can restore it if the new
  # nixpkgs tip lacks cached binaries for the heavy libs
  LOCK_BACKUP=$(mktemp)
  cp flake.lock "$LOCK_BACKUP"
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
    # sudo -n: never block on a password prompt from the EXIT trap (the
    # build may have outlived the sudo timestamp)
    if sudo -n systemctl start "$svc" 2>/dev/null; then
      echo "Restarting $svc..."
    else
      echo "WARNING: could not restart $svc (sudo expired) — run: sudo systemctl start $svc" >&2
    fi
  done
}
cleanup() {
  restore_services
  [ -n "$LOCK_BACKUP" ] && rm -f "$LOCK_BACKUP"
}
trap cleanup EXIT

# Map system hostname -> flake config name. They differ for the Framework
# laptops (e.g. flake framework-13 lives on host nixos-framework-13).
case "$(hostname)" in
  nixos-framework-13) DEFAULT_HOST="framework-13" ;;
  nixos-framework)    DEFAULT_HOST="framework-16" ;;
  *)                  DEFAULT_HOST="$(hostname)" ;;
esac

# Preflight gate: refuse to build when key packages have no cached binaries.
# - ROCm Tensile libs (rocblas/hipblas/hipblaslt): hours-long compiles, and
#   fresh unstable tips often never get them published (rocblas is Hydra's
#   longest-pole job, superseded by newer evals).
# - typescript-language-server: npm registry drift breaks its pinned pnpm
#   hash between nixpkgs revs (seen twice); a 404 means the rev predates the
#   hash fix.
# Pin to a rev with coverage instead: hydra.nixos.org/job/nixpkgs/unstable/
# <pkg>.x86_64-linux/latest. After --upgrade the lock is restored to its
# pre-upgrade state before aborting.
GATE_PKGS_ALWAYS="typescript-language-server"
GATE_PKGS_ROCM="rocblas hipblas hipblaslt"
check_cache_gate() {
  local target="${HOST:-$DEFAULT_HOST}"
  local missing=()
  local pkg out hash enable pkgs="$GATE_PKGS_ALWAYS"
  enable=$(nix eval ".#nixosConfigurations.$target.config.rocm-dev.enable" 2>/dev/null) || true
  if [ "$enable" = "true" ]; then pkgs="$pkgs rocmPackages.rocblas rocmPackages.hipblas rocmPackages.hipblaslt"; fi
  for pkg in $pkgs; do
    out=$(nix eval --raw ".#nixosConfigurations.$target.pkgs.$pkg.outPath" 2>/dev/null) || continue
    hash=$(basename "$out"); hash=${hash%%-*}
    curl -fsS -o /dev/null --max-time 15 "https://cache.nixos.org/$hash.narinfo" 2>/dev/null || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: no cached binary at this nixpkgs rev for: ${missing[*]}" >&2
    echo "  refusing to build — ROCm means hours of local compilation; a 404 on" >&2
    echo "  typescript-language-server means npm drift broke its pnpm hash. Pin" >&2
    echo "  nixpkgs to the rev of Hydra's latest successful build of the package." >&2
    if [ -n "$LOCK_BACKUP" ]; then
      cp "$LOCK_BACKUP" flake.lock
      echo "  flake.lock restored to its pre-upgrade state" >&2
    fi
    exit 1
  fi
  echo "Cache preflight: all gate packages cached"
}
check_cache_gate

sudo nixos-rebuild switch --flake ".#${HOST:-$DEFAULT_HOST}" --max-jobs "$JOBS" --cores "$CORES"
