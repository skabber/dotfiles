# nixos (Threadripper with NVIDIA GPU) - Home Manager configuration
{ config, pkgs, lib, googleWorkspaceCli, ... }:

{
  imports = [
    ./common.nix
  ];

  # Machine-specific packages
  home.packages = with pkgs; [
    retroarch
    warp-terminal
    alacritty
    system76-keyboard-configurator
    playwright-mcp
    googleWorkspaceCli.packages.${pkgs.system}.default
  ];

  # Bash configuration (sources local profile)
  programs.bash.enable = true;
  programs.bash.initExtra = ''
    source /home/jay/.bash_profile.local
  '';

  # Bash profile dotfile
  home.file.".bash_profile.local".source = ../bashconfig;

  # OpenClaw configuration (disabled)
  # programs.openclaw = {
  #   documents = ../openclaw-docs;
  #
  #   instances.default = {
  #     enable = true;
  #     plugins = [];
  #     config = {
  #       agents.defaults.model = {
  #         primary = "google/gemini-2.5-pro";
  #         fallbacks = [
  #           "mistral/mistral-large"
  #           "google/gemini-2.0-flash"
  #         ];
  #       };
  #       agents.defaults.models = {
  #         "google/gemini-2.5-pro" = { alias = "pro"; };
  #         "mistral/mistral-large" = { alias = "large"; };
  #         "google/gemini-2.0-flash" = { alias = "flash"; };
  #         "google/gemini-2.5-flash-lite" = { alias = "lite"; };
  #         "mistral/mistral-small" = { alias = "small"; };
  #         "ollama/qwen3.5:9b" = { alias = "qwen"; };
  #       };
  #       models.providers.ollama = {
  #         baseUrl = "http://nixos-ripper.tail69fe1.ts.net:11434";
  #         models = [
  #           { id = "qwen3.5:9b"; name = "qwen3.5:9b"; }
  #         ];
  #       };
  #       agents.defaults.heartbeat = {
  #         every = "30m";
  #         model = "google/gemini-2.5-flash-lite";
  #         target = "last";
  #       };
  #       agents.defaults.subagents = {
  #         model = "mistral/mistral-small";
  #         maxConcurrent = 8;
  #       };
  #       gateway.mode = "local";
  #       gateway.bind = "loopback";
  #       # Tailscale Serve is configured manually to allow routing multiple services
  #       gateway.controlUi.enabled = true;
  #       gateway.controlUi.allowedOrigins = [ "https://nixos.tail69fe1.ts.net:8443" ];
  #       # Workaround: Nix store uses hardlinks (nlink>1) which OpenClaw's
  #       # openVerifiedFileSync rejects. Copy assets to a local dir instead.
  #       gateway.controlUi.root = "/home/jay/.openclaw/control-ui";
  #       gateway.auth.allowTailscale = true;
  #       gateway.auth.mode = "token";
  #       gateway.auth.token = "temptoken123";
  #
  #       channels.telegram = {
  #         enabled = true;
  #         tokenFile = "/home/jay/.config/openclaw/telegram-bot-token";
  #         allowFrom = [ 8105954598 ];
  #         groups = {
  #           "*" = { requireMention = true; };
  #         };
  #       };
  #     };
  #   };
  # };

  # # Remove stale HM backup so the next activation can back up openclaw.json
  # # without hitting "would be clobbered" (openclaw rewrites the managed file at runtime)
  # home.activation.cleanOpenclawBackup = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  #   rm -f "$HOME/.openclaw/openclaw.json.backup"
  # '';

  # # Copy OpenClaw control-ui assets to break Nix store hardlinks (nlink>1)
  # # which OpenClaw's openVerifiedFileSync rejects
  # home.activation.openclawControlUi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   chmod -R u+w "$HOME/.openclaw/control-ui" 2>/dev/null || true
  #   rm -rf "$HOME/.openclaw/control-ui"
  #   ${pkgs.coreutils}/bin/cp -rL --no-preserve=mode,links \
  #     ${pkgs.openclaw-gateway}/lib/openclaw/dist/control-ui \
  #     "$HOME/.openclaw/control-ui"
  # '';

  # # Generate GOG keyring env file from password file for openclaw-gateway
  # home.activation.gogKeyringEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   if [ -f "$HOME/.config/gogcli/keyring-password" ]; then
  #     printf "GOG_KEYRING_PASSWORD=%s\n" "$(cat "$HOME/.config/gogcli/keyring-password")" > "$HOME/.config/gogcli/keyring-env"
  #   fi
  # '';

  # # Fix openclaw-gateway to start on boot and use correct binary
  # # The HM module wrapper points to an older openclaw binary that lacks plugin
  # # extensions, causing all plugins (including Telegram) to be rejected as unsafe.
  # # Override ExecStart to use the openclaw-gateway package directly.
  # systemd.user.services.openclaw-gateway = {
  #   Install.WantedBy = [ "default.target" ];
  #   Service.EnvironmentFile = "/home/jay/.config/gogcli/keyring-env";
  #   Service.ExecStart = lib.mkForce "${pkgs.openclaw-gateway}/bin/openclaw gateway --port 18789";
  # };

  # Playwright MCP server (SSE on port 8182)
  systemd.user.services.playwright-mcp = {
    Unit = {
      Description = "Playwright MCP Server";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.playwright-mcp}/bin/mcp-server-playwright --port 8182 --host 0.0.0.0";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # IronClaw AI assistant service
  systemd.user.services.ironclaw = {
    Unit = {
      Description = "IronClaw AI Assistant";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "/home/jay/Projects/ironclaw/target/release/ironclaw";
      WorkingDirectory = "/home/jay/Projects/ironclaw";
      EnvironmentFile = "/home/jay/.config/ironclaw/env";
      Environment = [
        "LD_LIBRARY_PATH=${pkgs.openssl.out}/lib"
        "RUST_LOG=ironclaw::llm=info"
      ];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # RustFS S3-compatible object storage
  systemd.user.services.rustfs = {
    Unit = {
      Description = "RustFS Object Storage";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "/home/jay/Projects/rustfs/target/release/rustfs --address 127.0.0.1:9000 --console-enable /home/jay/buckets";
      WorkingDirectory = "/home/jay/Projects/rustfs";
      EnvironmentFile = "/home/jay/.config/rustfs/env";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Disable Caps Lock
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "caps:none" ];
    };
  };
}
