#!/usr/bin/env bash
# Clawdbot setup script - creates secret files

set -e

SECRETS_DIR="$HOME/.secrets/clawdbot"

echo "Setting up Clawdbot secrets directory..."
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Create placeholder files if they don't exist
if [ ! -f "$SECRETS_DIR/telegram-bot-token" ]; then
    echo "YOUR_TELEGRAM_BOT_TOKEN_HERE" > "$SECRETS_DIR/telegram-bot-token"
    chmod 600 "$SECRETS_DIR/telegram-bot-token"
    echo "Created: $SECRETS_DIR/telegram-bot-token (edit with your token from @BotFather)"
fi

if [ ! -f "$SECRETS_DIR/anthropic-api-key" ]; then
    echo "YOUR_ANTHROPIC_API_KEY_HERE" > "$SECRETS_DIR/anthropic-api-key"
    chmod 600 "$SECRETS_DIR/anthropic-api-key"
    echo "Created: $SECRETS_DIR/anthropic-api-key (edit with your key from console.anthropic.com)"
fi

if [ ! -f "$SECRETS_DIR/google-api-key" ]; then
    echo "YOUR_GOOGLE_API_KEY_HERE" > "$SECRETS_DIR/google-api-key"
    chmod 600 "$SECRETS_DIR/google-api-key"
    echo "Created: $SECRETS_DIR/google-api-key (edit with your key from aistudio.google.com)"
fi

# Create environment file for systemd service
echo "Creating systemd environment file..."
cat > "$SECRETS_DIR/env" << 'EOF'
# Clawdbot environment variables
# This file is loaded by the systemd service
EOF
# Append Google API key if it exists and is not placeholder
if [ -f "$SECRETS_DIR/google-api-key" ]; then
    GOOGLE_KEY=$(cat "$SECRETS_DIR/google-api-key")
    if [ "$GOOGLE_KEY" != "YOUR_GOOGLE_API_KEY_HERE" ]; then
        echo "GOOGLE_API_KEY=$GOOGLE_KEY" >> "$SECRETS_DIR/env"
    fi
fi
chmod 600 "$SECRETS_DIR/env"
echo "Created: $SECRETS_DIR/env (systemd environment file)"

echo ""
echo "Secrets directory setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit $SECRETS_DIR/telegram-bot-token with your bot token"
echo "2. Edit $SECRETS_DIR/google-api-key with your Google AI API key (for Gemini)"
echo "   (Optional: $SECRETS_DIR/anthropic-api-key for Claude fallback)"
echo "3. Edit flake.nix and add your Telegram user ID to allowFrom"
echo "   (Get your ID by messaging @userinfobot on Telegram)"
echo "4. Apply the configuration:"
echo "   cd ~/dotfiles/clawdbot && home-manager switch --flake .#jay"
echo "5. Check the service status:"
echo "   systemctl --user status clawdbot-gateway"
