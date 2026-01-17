# Framework 13 - Home Manager configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # Framework 13 specific packages
  home.packages = with pkgs; [
    # Development
    zls
    code-cursor
    zed-editor
    awscli2
    espup
    bruno

    # Media & productivity
    cider
    heroic
    libreoffice
    obs-studio
    audacity
    lmstudio

    # Gaming
    cemu
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
    helvum

    # Other
    gjs
    vte
    gnome-boxes
    gnomeExtensions.resource-monitor
    gnomeExtensions.wireless-hid
    android-studio
    postgresql
    elf2uf2-rs
  ];
}
