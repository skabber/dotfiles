# Framework 13 - Home Manager configuration
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./common.nix
  ];

  # Framework 13 specific packages
  home.packages = with pkgs; [
    # Development
    code-cursor
    zed-editor
    awscli2
    espup
    bruno

    # Media & productivity
    # cider
    heroic
    libreoffice
    obs-studio
    audacity
    lmstudio

    # Gaming
    ryubing
    bottles

    # Hardware tools
    system76-keyboard-configurator
    framework-tool
    via
    dualsensectl
    nvtopPackages.amd

    # Terminal
    ghostty
    warp-terminal
    nushell

    # Other
    gjs
    vte
    android-studio

    # Cosmic DE
    cosmic-term
    cosmic-edit
    cosmic-bg
    cosmic-osd
    cosmic-comp
    cosmic-randr
    cosmic-panel
    cosmic-icons
    cosmic-greeter
    cosmic-files
    cosmic-applets
    cosmic-settings
    cosmic-launcher
    cosmic-screenshot
    cosmic-applibrary
    cosmic-design-demo
    cosmic-notifications
    cosmic-settings-daemon
    cosmic-workspaces-epoch
    postgresql
    elf2uf2-rs
  ];
}
