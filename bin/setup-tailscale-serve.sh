#!/usr/bin/env bash
# Setup Tailscale Serve for multiple services on nixos
#
# This script configures Tailscale Serve to proxy HTTPS traffic to local services:
#   - https://nixos.tail69fe1.ts.net/         -> nginx (static site + /wallabag/)
#   - https://nixos.tail69fe1.ts.net:3000/    -> Gitea
#   - https://nixos.tail69fe1.ts.net:8443/    -> OpenClaw gateway (Tailscale IP)
#   - https://nixos.tail69fe1.ts.net:8444/    -> IronClaw gateway
#   - https://nixos.tail69fe1.ts.net:9000/    -> RustFS (S3 API + Console)
#   - https://nixos.tail69fe1.ts.net:8182/    -> Playwright MCP
#   - https://nixos.tail69fe1.ts.net:8000/    -> WhisperX transcription
#   - https://nixos.tail69fe1.ts.net:8880/    -> Kokoro TTS

set -euo pipefail

echo "Resetting Tailscale Serve configuration..."
tailscale serve reset

echo "Configuring Tailscale Serve..."

# Port 443 -> nginx (serves static site at / and wallabag at /wallabag/)
tailscale serve --bg --https=443 http://127.0.0.1:80

# Port 3000 -> Gitea
tailscale serve --bg --https=3000 http://127.0.0.1:3000

# Port 8443 -> OpenClaw gateway (listens on localhost:18789)
tailscale serve --bg --https=8443 http://127.0.0.1:18789

# Port 8182 -> Playwright MCP
tailscale serve --bg --https=8182 http://127.0.0.1:8182

# Port 8444 -> IronClaw gateway
tailscale serve --bg --https=8444 http://127.0.0.1:8444

# Port 8000 -> WhisperX transcription
tailscale serve --bg --https=8000 http://127.0.0.1:8000

# Port 8880 -> Kokoro TTS (internal port 8881 to avoid Docker bind conflict)
tailscale serve --bg --https=8880 http://127.0.0.1:8881

# Port 9000 -> RustFS (S3 API + Console)
tailscale serve --bg --https=9000 http://127.0.0.1:9000

echo ""
echo "Tailscale Serve configuration complete!"
echo ""
tailscale serve status
echo ""
echo "Services available at:"
echo "  https://nixos.tail69fe1.ts.net/           - Static site"
echo "  https://nixos.tail69fe1.ts.net/wallabag/  - Wallabag"
echo "  https://nixos.tail69fe1.ts.net:3000/      - Gitea"
echo "  https://nixos.tail69fe1.ts.net:8443/      - OpenClaw gateway"
echo "  https://nixos.tail69fe1.ts.net:8444/      - IronClaw gateway"
echo "  https://nixos.tail69fe1.ts.net:9000/      - RustFS (S3 + Console)"
echo "  https://nixos.tail69fe1.ts.net:8000/      - WhisperX transcription"
echo "  https://nixos.tail69fe1.ts.net:8880/      - Kokoro TTS"
echo "  https://nixos.tail69fe1.ts.net:8182/      - Playwright MCP"
