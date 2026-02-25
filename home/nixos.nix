# nixos (Threadripper with NVIDIA GPU) - Home Manager configuration
{ config, pkgs, lib, ... }:

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
  ];

  # Bash configuration (sources local profile)
  programs.bash.enable = true;
  programs.bash.initExtra = ''
    source /home/jay/.bash_profile.local
  '';

  # Bash profile dotfile
  home.file.".bash_profile.local".source = ../bashconfig;

  # OpenClaw configuration
  programs.openclaw = {
    documents = ../openclaw-docs;

    instances.default = {
      enable = true;
      plugins = [];
      config = {
        agents.defaults.model = {
          primary = "google/gemini-2.5-pro";
          fallbacks = [
            "mistral/mistral-large"
            "google/gemini-2.0-flash"
          ];
        };
        agents.defaults.models = {
          "google/gemini-2.5-pro" = { alias = "pro"; };
          "mistral/mistral-large" = { alias = "large"; };
          "google/gemini-2.0-flash" = { alias = "flash"; };
          "google/gemini-2.5-flash-lite" = { alias = "lite"; };
          "mistral/mistral-small" = { alias = "small"; };
        };
        agents.defaults.heartbeat = {
          every = "30m";
          model = "google/gemini-2.5-flash-lite";
          target = "last";
        };
        agents.defaults.subagents = {
          model = "mistral/mistral-small";
          maxConcurrent = 8;
        };
        gateway.mode = "local";
        gateway.bind = "loopback";
        # Tailscale Serve is configured manually to allow routing multiple services
        gateway.controlUi.enabled = true;
        gateway.auth.allowTailscale = true;
        gateway.auth.mode = "token";
        gateway.auth.token = "temptoken123";

        channels.telegram = {
          enabled = true;
          tokenFile = "/home/jay/.config/openclaw/telegram-bot-token";
          allowFrom = [ 8105954598 ];
          groups = {
            "*" = { requireMention = true; };
          };
        };
      };
    };
  };

  # Fix openclaw-gateway to start on boot
  systemd.user.services.openclaw-gateway = {
    Install.WantedBy = [ "default.target" ];
  };

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

  # IronClaw AI assistant service (disabled)
  # systemd.user.services.ironclaw = {
  #   Unit = {
  #     Description = "IronClaw AI Assistant";
  #     After = [ "network-online.target" ];
  #   };
  #   Service = {
  #     ExecStart = "/home/jay/Projects/ironclaw/target/release/ironclaw";
  #     WorkingDirectory = "/home/jay/Projects/ironclaw";
  #     EnvironmentFile = "/home/jay/.config/ironclaw/env";
  #     Environment = [
  #       "LD_LIBRARY_PATH=${pkgs.openssl.out}/lib"
  #       "RUST_LOG=ironclaw::llm=info"
  #     ];
  #     Restart = "on-failure";
  #     RestartSec = 10;
  #   };
  #   Install = {
  #     WantedBy = [ "default.target" ];
  #   };
  # };

  # Disable Caps Lock
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "caps:none" ];
    };
  };
}
