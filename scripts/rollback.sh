#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Rolling back to previous configuration..."
sudo nixos-rebuild switch --rollback
echo "✅ Rollback complete!"