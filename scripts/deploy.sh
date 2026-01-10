#!/usr/bin/env bash
set -euo pipefail

HOSTNAME=$(hostname)
CONFIG_DIR="$HOME/dotfiles/hosts/$HOSTNAME"

echo "🔧 Deploying to: $HOSTNAME"
echo "📁 Config directory: $CONFIG_DIR"

# Create symlink to /etc/nixos
echo "🔗 Creating symlink: /etc/nixos -> $CONFIG_DIR"
sudo ln -sfn "$CONFIG_DIR" /etc/nixos

# Build configuration
echo "🏗️  Building configuration..."
sudo nixos-rebuild build --flake "$HOME/dotfiles#$HOSTNAME"

# Show new generation info
echo ""
echo "✅ Build complete! Review the generation info above."
echo ""
read -p "Switch to new configuration? (y/n): " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "🔄 Switching to new configuration..."
  sudo nixos-rebuild switch --flake "$HOME/dotfiles#$HOSTNAME"

  echo ""
  echo "✅ Configuration switched successfully!"
  echo "💡 Rollback command: sudo nixos-rebuild switch --rollback"
else
  echo "❌ Build cancelled."
  exit 1
fi