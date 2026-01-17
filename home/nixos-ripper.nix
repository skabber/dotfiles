# nixos-ripper (Threadripper 1) - Home Manager configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # nixos-ripper specific packages
  home.packages = with pkgs; [
    # Development
    deno
    rustup
    go
    zig
    zig-shell-completions
    gopls
    taplo
    zls
    python311Packages.python-lsp-server
    openvscode-server
    zed-editor

    # Media
    cider
    heroic

    # Hardware tools
    system76-keyboard-configurator
    remmina
    rpi-imager
    via
    dualsensectl
    nvtopPackages.amd

    # Gaming
    ryubing
    bottles

    # Utilities
    fermyon-spin
    gjs
    vte
    espup
    nushell
    warp-terminal
    elf2uf2-rs
    gnomeExtensions.pano
    zoom-us
  ];
}
