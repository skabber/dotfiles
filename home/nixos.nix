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
        gateway.mode = "local";

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
}
