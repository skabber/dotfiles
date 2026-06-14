#!/usr/bin/env bash
# ExecStopPost for the template unit — clears the Tailscale Serve mapping even
# if the main process crashed. Idempotent.
set -euo pipefail

PR="$1"
ENV_FILE="/srv/show-friends/previews/${PR}/preview.env"
[ -f "${ENV_FILE}" ] || exit 0
set -a; . "${ENV_FILE}"; set +a

tailscale serve reset --https="${FPORT}" 2>/dev/null || true
