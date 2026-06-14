#!/usr/bin/env bash
# Checkout the PR ref into SRC_DIR. Runs as User=jay (no nix needed).
set -euo pipefail

PR="$1"
ENV_FILE="/srv/show-friends/previews/${PR}/preview.env"
set -a; . "${ENV_FILE}"; set +a

GIT_REMOTE="${GIT_REMOTE:-gitea@nixos.tail69fe1.ts.net:skabber/show-friends.git}"

mkdir -p "${SRC_DIR}"
cd "${SRC_DIR}"

if [ ! -d .git ]; then
  echo "==> cloning ${GIT_REMOTE}"
  git clone --quiet "${GIT_REMOTE}" .
fi

# Disable any prompts during checkout of a detached PR ref.
export GIT_TERMINAL_PROMPT=0

echo "==> fetching ${REF}"
git fetch --quiet --force origin "${REF}"
git checkout --force --quiet FETCH_HEAD

echo "==> prepared PR ${PR} at $(git rev-parse HEAD)"
