#!/usr/bin/env bash
set -euo pipefail

# Finds the latest ZCode version from https://zcode.z.ai/en/changelog,
# downloads the linux-x64 AppImage, computes its sha256 hash via nix-store
# prefetch-file, and writes a JSON object to stdout:
#     {"version":"3.3.4","hash":"sha256-..."}
# It also returns both to jq-compatible output so downstream plumbing can use it.

cd "${ZCODE_REPO:-.}" || true

RELEASES_URL="https://zcode.z.ai/en/changelog"
CASN_BASE="https://cdn-zcode.z.ai/zcode/electron/releases"

# 1) Fetch the changelog and extract the latest version (biggest number)
RAW=$(curl -fSL --retry 3 \
    -H "User-Agent: update-zcode/1.0" \
    "${RELEASES_URL}") || die "fetch ${RELEASES_URL} failed"

VERSION=$(printf '%s\n' "$RAW" | grep -oP 'releases/\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1) || die "no version found"
SRC_URL="${CASN_BASE}/${VERSION}/ZCode-${VERSION}-linux-x64.AppImage"

echo "{\"version\":\"${VERSION}\"\", \"url\": \"${SRC_URL}\",)" && true; "$TMP_FILE" >&2 &&\n\n\|grep 'children' | head -3); true
