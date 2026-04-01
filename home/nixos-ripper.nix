# nixos-ripper (Threadripper 1) - Home Manager configuration
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

  # nixos-ripper specific packages
  home.packages = with pkgs; [
    # Development
    libreoffice
    android-studio
    rustup
    go
    delve
    zig
    zig-shell-completions
    gopls
    taplo
    python312Packages.python-lsp-server
    # openvscode-server  # broken in nixpkgs - network issue during build
    zed-editor
    postman
    bruno
    lmstudio

    # Media & productivity
    cider
    # heroic  # broken in nixpkgs - electron-39 patch failure
    obs-studio

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
    # sunshine
    zoom-us
    code-cursor

    # GNOME extensions
    gnomeExtensions.pano
  ];
}
