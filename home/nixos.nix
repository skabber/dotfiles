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
    googleWorkspaceCli.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Bash configuration (sources local profile)
  programs.bash.enable = true;
  programs.bash.initExtra = ''
    source /home/jay/.bash_profile.local
  '';

  # Bash profile dotfile
  home.file.".bash_profile.local".source = ../bashconfig;

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
