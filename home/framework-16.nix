# Framework 16 - Home Manager configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # Framework 16 specific packages
  home.packages = with pkgs; [
    # Development tools
    deno
    opentofu
    postgresql
    go
    gopls
    zig
    zig-shell-completions
    zls
    taplo
    espup
    elf2uf2-rs

    # Editors & IDEs
    code-cursor
    zed-editor
    android-studio
    alacritty

    # Remote & networking
    remmina
    awscli2

    # Terminal tools
    ghostty
    warp-terminal
    nushell

    # Hardware tools
    framework-tool
    inputmodule-control
    via
    nvtopPackages.amd
    system76-keyboard-configurator
    dualsensectl

    # Media & productivity
    calibre
    heroic
    gjs
    vte

    # Gaming
    cemu
    ryubing
    bottles

    # API tools
    bruno
    postman

    # GNOME extras
    gnome-firmware
    gnome-boxes
    gnomeExtensions.resource-monitor

    # Cosmic DE stuff
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
  ];

  # Framework 16 needs HSA override for AMD GPU
  home.sessionVariables = {
    HSA_OVERRIDE_GFX_VERSION = "10.3.0";
  };
}
