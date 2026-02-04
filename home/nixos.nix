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
        agents.defaults.model.primary = "google/gemini-2.0-flash";
        gateway.mode = "local";
        gateway.bind = "loopback";
        gateway.tailscale.mode = "serve";
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

  # Disable Caps Lock
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "caps:none" ];
    };
  };
}
