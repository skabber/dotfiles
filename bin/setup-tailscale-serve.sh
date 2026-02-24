#!/usr/bin/env bash
# Setup Tailscale Serve for multiple services on nixos
#
# This script configures Tailscale Serve to proxy HTTPS traffic to local services:
#   - https://nixos.tail69fe1.ts.net/         -> nginx (static site + /wallabag/)
#   - https://nixos.tail69fe1.ts.net:3000/    -> Gitea
#   - https://nixos.tail69fe1.ts.net:8443/    -> ironclaw gateway
#   - https://nixos.tail69fe1.ts.net:8182/    -> Playwright MCP

set -euo pipefail

echo "Resetting Tailscale Serve configuration..."
tailscale serve reset

echo "Configuring Tailscale Serve..."

# Port 443 -> nginx (serves static site at / and wallabag at /wallabag/)
tailscale serve --bg --https=443 http://127.0.0.1:80

# Port 3000 -> Gitea
tailscale serve --bg --https=3000 http://127.0.0.1:3000

# Port 8443 -> ironclaw gateway
tailscale serve --bg --https=8443 http://127.0.0.1:3001

# Port 8182 -> Playwright MCP
tailscale serve --bg --https=8182 http://127.0.0.1:8182

echo ""
echo "Tailscale Serve configuration complete!"
echo ""
tailscale serve status
echo ""
echo "Services available at:"
echo "  https://nixos.tail69fe1.ts.net/           - Static site"
echo "  https://nixos.tail69fe1.ts.net/wallabag/  - Wallabag"
echo "  https://nixos.tail69fe1.ts.net:3000/      - Gitea"
echo "  https://nixos.tail69fe1.ts.net:8443/      - IronClaw Gateway"
echo "  https://nixos.tail69fe1.ts.net:8182/      - Playwright MCP"
