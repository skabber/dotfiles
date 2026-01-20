# nixos-ripper (Threadripper 1) - Home Manager configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # nixos-ripper specific packages
  home.packages = with pkgs; [
    # Development
    libreoffice
    android-studio
    deno
    rustup
    go
    delve
    zig
    zig-shell-completions
    gopls
    taplo
    zls
    python311Packages.python-lsp-server
    # openvscode-server  # broken in nixpkgs - network issue during build
    zed-editor
    postman
    bruno

    # Media & productivity
    cider
    heroic
    obs-studio
    helvum
    calibre

    # Gaming
    ryubing
    cemu
    bottles
    moonlight-qt
    evdevhook2

    # Hardware tools
    system76-keyboard-configurator
    remmina
    rpi-imager
    via
    dualsensectl
    nvtopPackages.amd

    # Terminal & shell
    ghostty
    warp-terminal
    nushell
    bat
    fd
    eza
    dust
    dua

    # Utilities
    fermyon-spin
    gjs
    vte
    espup
    elf2uf2-rs
    sunshine
    zoom-us
    code-cursor

    # GNOME extensions
    gnomeExtensions.pano
  ];
}
