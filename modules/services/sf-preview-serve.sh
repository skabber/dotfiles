#!/usr/bin/env bash
# Build + launch the preview stack. Runs INSIDE `nix develop` so that
# worker-build, trunk, wrangler and sqld are on PATH.
set -euo pipefail

PR="$1"
ENV_FILE="/srv/show-friends/previews/${PR}/preview.env"
set -a; . "${ENV_FILE}"; set +a
cd "${SRC_DIR}"

export WRANGLER_SEND_METRICS=false
export CLOUDFLARE_TELEMETRY_DISABLED=1

echo "==> building worker"
( cd crates/worker && worker-build --release )
echo "==> building frontend"
( cd crates/frontend && trunk build --release --public-url / )

# SPA runtime config. /api is same-origin (routed by the _worker.js below).
cat > crates/frontend/dist/config.js <<EOF
window.__SHOW_FRIENDS_CONFIG__ = {
  TURSO_DATABASE_URL: "",
  TURSO_READ_TOKEN: "",
  API_BASE: "",
  VAPID_PUBLIC_KEY: ""
};
EOF

# Pages _worker.js: route /api/* to the local wrangler-dev worker, everything
# else to the asset binding (which honours _redirects for SPA fallback).
cat > crates/frontend/dist/_worker.js <<EOF
const WORKER_URL = "http://127.0.0.1:${WPORT}";
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/api/")) {
      const target = new URL(url.pathname + url.search, WORKER_URL);
      return fetch(new Request(target, request));
    }
    return env.ASSETS.fetch(request);
  },
};
EOF

# Worker secrets — points at the per-PR local sqld.
cat > crates/worker/.dev.vars <<EOF
TURSO_DATABASE_URL=http://127.0.0.1:${SQPORT}
TURSO_WRITE_TOKEN=anything
SESSION_SECRET=${SESSION_SECRET}
PAGES_ORIGIN=https://${DOMAIN}:${FPORT}
EOF

# Seed the per-PR DB from the latest prod backup so previews run against real
# data instead of an empty DB. Falls back to an empty DB on any failure (bad
# token, worker down, no backup yet) so previews never block on the restore.
# --no-mark-migrations preserves the dump's _migrations (prod's applied list)
# so the turso-migrate.sh run below applies only migrations new to this PR.
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "==> seeding ${DB_FILE} from latest prod backup"
  if ./scripts/restore-backup.sh --db-file "${DB_FILE}" --no-mark-migrations; then
    echo "    restore OK"
  else
    echo "    !! restore failed; continuing with an empty DB"
    rm -f "${DB_FILE}"
  fi
else
  echo "==> no R2 backup token (CLOUDFLARE_API_TOKEN unset); starting with empty DB"
fi

echo "==> starting sqld on 127.0.0.1:${SQPORT}"
sqld --db-path "${DB_FILE}" --http-listen-addr "127.0.0.1:${SQPORT}" &
SQLD_PID=$!

cleanup() {
  echo "==> stopping preview ${PR}"
  kill "${SQLD_PID}" 2>/dev/null || true
  if [ -n "${WORKER_PID:-}" ]; then kill "${WORKER_PID}" 2>/dev/null || true; fi
  tailscale serve reset --https="${FPORT}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> waiting for sqld to accept connections"
for _ in $(seq 1 30); do
  if (exec 3<>/dev/tcp/127.0.0.1/${SQPORT}) 2>/dev/null; then exec 3>&- 3<&-; break; fi
  sleep 1
done

echo "==> applying migrations"
TURSO_DATABASE_URL="http://127.0.0.1:${SQPORT}" TURSO_WRITE_TOKEN=anything ./scripts/turso-migrate.sh

echo "==> starting worker on 127.0.0.1:${WPORT}"
( cd crates/worker && exec wrangler dev --port "${WPORT}" --ip 127.0.0.1 ) &
WORKER_PID=$!

echo "==> registering tailscale serve on :${FPORT}"
tailscale serve --bg --https="${FPORT}" "http://127.0.0.1:${FPORT}"

echo "==> starting pages (public) on 127.0.0.1:${FPORT}"
cd crates/frontend
# Pin compatibility date: pages dev otherwise defaults to today, which can be
# newer than the bundled workerd supports (and newer than the worker's own
# wrangler.toml date). Match the worker's pinned date.
exec wrangler pages dev dist --port "${FPORT}" --ip 127.0.0.1 --compatibility-date 2026-01-01
